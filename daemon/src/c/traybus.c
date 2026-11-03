#define _GNU_SOURCE
#include "traybus.h"

#include <poll.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/eventfd.h>
#include <time.h>
#include <unistd.h>

#include <systemd/sd-bus.h>

#define MAX_ITEMS 32
#define QUEUE_SIZE 64
#define KEY_SIZE 320
#define CALL_TIMEOUT 800000

typedef struct {
	char *service;
	char *path;
	char *key;
	char *id;
	char *title;
	char *icon_name;
	char *theme_path;
	char *status;
	char *menu_path;
	char *menu_json;
	int32_t item_is_menu;
	int32_t pixmap_width;
	int32_t pixmap_height;
	uint32_t pixmap_size;
	uint8_t *pixmap;
} item;

typedef struct {
	int kind;
	int32_t id;
	char key[KEY_SIZE];
} action;

typedef struct {
	char *data;
	size_t length;
	size_t capacity;
} buffer;

static item items[MAX_ITEMS];
static int item_count;
static sd_bus *bus;
static int wake_fd = -1;
static void *callback_ctx;
static tb_update_fn on_update;
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static action queue[QUEUE_SIZE];
static int queue_head;
static int queue_count;

static void put(buffer *b, const char *text, size_t length)
{
	if (b->length + length + 1 > b->capacity) {
		b->capacity = (b->length + length + 1) * 2;
		b->data = realloc(b->data, b->capacity);
	}

	memcpy(b->data + b->length, text, length);
	b->length += length;
	b->data[b->length] = 0;
}

static void puts_(buffer *b, const char *text)
{
	put(b, text, strlen(text));
}

static void put_string(buffer *b, const char *text)
{
	puts_(b, "\"");

	for (; text && *text; text++) {
		unsigned char c = (unsigned char)*text;
		char piece[8];

		if (c == '"' || c == '\\') {
			piece[0] = '\\';
			piece[1] = (char)c;
			put(b, piece, 2);
		} else if (c < 0x20) {
			int n = snprintf(piece, sizeof(piece), "\\u%04x", c);
			put(b, piece, (size_t)n);
		} else {
			put(b, (const char *)&c, 1);
		}
	}

	puts_(b, "\"");
}

static void set(char **slot, const char *value)
{
	free(*slot);
	*slot = strdup(value ? value : "");
}

static void free_item(item *it)
{
	free(it->service);
	free(it->path);
	free(it->key);
	free(it->id);
	free(it->title);
	free(it->icon_name);
	free(it->theme_path);
	free(it->status);
	free(it->menu_path);
	free(it->menu_json);
	free(it->pixmap);
	memset(it, 0, sizeof(*it));
}

static void publish(void)
{
	tb_item out[MAX_ITEMS];

	for (int i = 0; i < item_count; i++) {
		item *it = &items[i];

		out[i].key = it->key;
		out[i].id = it->id ? it->id : "";
		out[i].title = it->title ? it->title : "";
		out[i].icon_name = it->icon_name ? it->icon_name : "";
		out[i].theme_path = it->theme_path ? it->theme_path : "";
		out[i].status = it->status ? it->status : "";
		out[i].menu_json = it->menu_json ? it->menu_json : "[]";
		out[i].has_menu = it->menu_path && it->menu_path[0] && strcmp(it->menu_path, "/NO_DBUSMENU") != 0;
		out[i].item_is_menu = it->item_is_menu;
		out[i].pixmap_width = it->pixmap_width;
		out[i].pixmap_height = it->pixmap_height;
		out[i].pixmap_size = it->pixmap_size;
		out[i].pixmap = it->pixmap;
	}

	on_update(callback_ctx, out, item_count);
}

static int read_variant_string(sd_bus_message *m, char **slot, const char *contents)
{
	const char *text;
	int r = sd_bus_message_enter_container(m, 'v', contents);

	if (r < 0)
		return r;

	r = sd_bus_message_read_basic(m, contents[0], &text);
	if (r < 0)
		return r;

	set(slot, text);

	return sd_bus_message_exit_container(m);
}

static int read_pixmaps(sd_bus_message *m, item *it)
{
	int r = sd_bus_message_enter_container(m, 'v', "a(iiay)");

	if (r < 0)
		return r;

	r = sd_bus_message_enter_container(m, 'a', "(iiay)");
	if (r < 0)
		return r;

	for (;;) {
		int32_t width, height;
		const void *data;
		size_t size;

		r = sd_bus_message_enter_container(m, 'r', "iiay");
		if (r <= 0)
			break;

		r = sd_bus_message_read(m, "ii", &width, &height);
		if (r < 0)
			return r;

		r = sd_bus_message_read_array(m, 'y', &data, &size);
		if (r < 0)
			return r;

		if (width > it->pixmap_width && size >= (size_t)width * (size_t)height * 4) {
			free(it->pixmap);
			it->pixmap = malloc(size);
			memcpy(it->pixmap, data, size);
			it->pixmap_width = width;
			it->pixmap_height = height;
			it->pixmap_size = (uint32_t)size;
		}

		r = sd_bus_message_exit_container(m);
		if (r < 0)
			return r;
	}

	if (r < 0)
		return r;

	r = sd_bus_message_exit_container(m);
	if (r < 0)
		return r;

	return sd_bus_message_exit_container(m);
}

static void fetch_props(item *it)
{
	sd_bus_message *reply = NULL;
	sd_bus_error error = SD_BUS_ERROR_NULL;
	int r;

	r = sd_bus_call_method(bus, it->service, it->path, "org.freedesktop.DBus.Properties", "GetAll", &error, &reply, "s", "org.kde.StatusNotifierItem");
	sd_bus_error_free(&error);

	if (r < 0)
		return;

	free(it->pixmap);
	it->pixmap = NULL;
	it->pixmap_width = it->pixmap_height = 0;
	it->pixmap_size = 0;

	if (sd_bus_message_enter_container(reply, 'a', "{sv}") < 0)
		goto done;

	for (;;) {
		const char *name;
		const char *contents;
		char type;

		r = sd_bus_message_enter_container(reply, 'e', "sv");
		if (r <= 0)
			break;

		if (sd_bus_message_read(reply, "s", &name) < 0)
			break;

		if (sd_bus_message_peek_type(reply, &type, &contents) < 0)
			break;

		if (strcmp(name, "Id") == 0 && strcmp(contents, "s") == 0)
			r = read_variant_string(reply, &it->id, "s");
		else if (strcmp(name, "Title") == 0 && strcmp(contents, "s") == 0)
			r = read_variant_string(reply, &it->title, "s");
		else if (strcmp(name, "IconName") == 0 && strcmp(contents, "s") == 0)
			r = read_variant_string(reply, &it->icon_name, "s");
		else if (strcmp(name, "IconThemePath") == 0 && strcmp(contents, "s") == 0)
			r = read_variant_string(reply, &it->theme_path, "s");
		else if (strcmp(name, "Status") == 0 && strcmp(contents, "s") == 0)
			r = read_variant_string(reply, &it->status, "s");
		else if (strcmp(name, "Menu") == 0 && strcmp(contents, "o") == 0)
			r = read_variant_string(reply, &it->menu_path, "o");
		else if (strcmp(name, "ItemIsMenu") == 0 && strcmp(contents, "b") == 0) {
			int value = 0;
			r = sd_bus_message_read(reply, "v", "b", &value);
			it->item_is_menu = value;
		} else if (strcmp(name, "IconPixmap") == 0 && strcmp(contents, "a(iiay)") == 0)
			r = read_pixmaps(reply, it);
		else
			r = sd_bus_message_skip(reply, "v");

		if (r < 0)
			break;

		if (sd_bus_message_exit_container(reply) < 0)
			break;
	}

done:
	sd_bus_message_unref(reply);
}

static int menu_node(sd_bus_message *m, buffer *out, int top)
{
	int32_t id;
	int r = sd_bus_message_enter_container(m, 'r', "ia{sv}av");

	if (r < 0)
		return r;

	r = sd_bus_message_read(m, "i", &id);
	if (r < 0)
		return r;

	char label[1024] = "";
	char kind[32] = "";
	char icon[512] = "";
	char toggle[32] = "";
	char children_display[32] = "";
	int enabled = 1, visible = 1, state = -1;

	r = sd_bus_message_enter_container(m, 'a', "{sv}");
	if (r < 0)
		return r;

	for (;;) {
		const char *name;
		const char *contents;
		char type;

		r = sd_bus_message_enter_container(m, 'e', "sv");
		if (r <= 0)
			break;

		if (sd_bus_message_read(m, "s", &name) < 0)
			return -1;
		if (sd_bus_message_peek_type(m, &type, &contents) < 0)
			return -1;

		const char *text = NULL;

		if (strcmp(contents, "s") == 0 && (strcmp(name, "label") == 0 || strcmp(name, "type") == 0 || strcmp(name, "icon-name") == 0 || strcmp(name, "toggle-type") == 0 || strcmp(name, "children-display") == 0)) {
			r = sd_bus_message_read(m, "v", "s", &text);
			if (r < 0)
				return r;

			char *dest = strcmp(name, "label") == 0 ? label : strcmp(name, "type") == 0 ? kind : strcmp(name, "icon-name") == 0 ? icon : strcmp(name, "toggle-type") == 0 ? toggle : children_display;
			size_t cap = strcmp(name, "label") == 0 ? sizeof(label) : strcmp(name, "icon-name") == 0 ? sizeof(icon) : 32;
			snprintf(dest, cap, "%s", text);
		} else if (strcmp(contents, "b") == 0 && (strcmp(name, "enabled") == 0 || strcmp(name, "visible") == 0)) {
			int value = 1;
			r = sd_bus_message_read(m, "v", "b", &value);
			if (r < 0)
				return r;
			if (strcmp(name, "enabled") == 0)
				enabled = value;
			else
				visible = value;
		} else if (strcmp(contents, "i") == 0 && strcmp(name, "toggle-state") == 0) {
			r = sd_bus_message_read(m, "v", "i", &state);
			if (r < 0)
				return r;
		} else {
			r = sd_bus_message_skip(m, "v");
			if (r < 0)
				return r;
		}

		r = sd_bus_message_exit_container(m);
		if (r < 0)
			return r;
	}

	r = sd_bus_message_exit_container(m);
	if (r < 0)
		return r;

	if (!top) {
	char head[64];
	int n = snprintf(head, sizeof(head), "{\"id\":%d,\"text\":", id);
	put(out, head, (size_t)n);

	char stripped[1024];
	size_t at = 0;
	for (size_t i = 0; label[i] && at + 1 < sizeof(stripped); i++) {
		if (label[i] == '_' && label[i + 1] == '_') {
			stripped[at++] = '_';
			i++;
		} else if (label[i] != '_') {
			stripped[at++] = label[i];
		}
	}
	stripped[at] = 0;

	put_string(out, stripped);
	puts_(out, ",\"icon\":");
	put_string(out, icon);
	puts_(out, enabled ? ",\"enabled\":true" : ",\"enabled\":false");
	puts_(out, visible ? ",\"visible\":true" : ",\"visible\":false");
	puts_(out, strcmp(kind, "separator") == 0 ? ",\"isSeparator\":true" : ",\"isSeparator\":false");

	int checked = state == 1;
	puts_(out, checked ? ",\"checkState\":2" : ",\"checkState\":0");
	puts_(out, ",\"children\":[");
	}

	r = sd_bus_message_enter_container(m, 'a', "v");
	if (r < 0)
		return r;

	int first = 1;

	for (;;) {
		r = sd_bus_message_enter_container(m, 'v', "(ia{sv}av)");
		if (r <= 0)
			break;

		if (!first)
			puts_(out, ",");
		first = 0;

		r = menu_node(m, out, 0);
		if (r < 0)
			return r;

		r = sd_bus_message_exit_container(m);
		if (r < 0)
			return r;
	}

	if (!top) {
		puts_(out, "],\"hasChildren\":");
		puts_(out, first ? "false" : "true");
		puts_(out, "}");
	}

	r = sd_bus_message_exit_container(m);
	if (r < 0)
		return r;

	return sd_bus_message_exit_container(m);
}

static void fetch_menu(item *it)
{
	if (!it->menu_path || !it->menu_path[0] || strcmp(it->menu_path, "/NO_DBUSMENU") == 0) {
		set(&it->menu_json, "[]");
		return;
	}

	sd_bus_message *call = NULL;
	sd_bus_message *reply = NULL;
	sd_bus_error error = SD_BUS_ERROR_NULL;

	if (sd_bus_message_new_method_call(bus, &call, it->service, it->menu_path, "com.canonical.dbusmenu", "GetLayout") < 0)
		return;

	sd_bus_message_append(call, "ii", 0, -1);
	sd_bus_message_open_container(call, 'a', "s");
	sd_bus_message_close_container(call);

	int r = sd_bus_call(bus, call, CALL_TIMEOUT, &error, &reply);
	sd_bus_message_unref(call);

	if (r < 0)
		fprintf(stderr, "tray menu call failed: %s\n", error.message ? error.message : "?");

	sd_bus_error_free(&error);

	if (r < 0)
		return;

	uint32_t revision;
	buffer out = { 0 };

	puts_(&out, "[");

	int mr = sd_bus_message_read(reply, "u", &revision);
	if (mr >= 0)
		mr = menu_node(reply, &out, 1);
	if (mr >= 0) {
		puts_(&out, "]");
		set(&it->menu_json, out.data);
	} else {
		fprintf(stderr, "tray menu parse failed: %d\n", mr);
	}

	free(out.data);
	sd_bus_message_unref(reply);
}

static item *find_item(const char *key)
{
	for (int i = 0; i < item_count; i++)
		if (strcmp(items[i].key, key) == 0)
			return &items[i];

	return NULL;
}

static void refresh(item *it, int with_menu)
{
	fetch_props(it);

	if (with_menu)
		fetch_menu(it);
}

static void push(const action *entry);

static void add_item(const char *service, const char *path)
{
	char key[KEY_SIZE];

	snprintf(key, sizeof(key), "%s%s", service, path);

	if (find_item(key) || item_count >= MAX_ITEMS)
		return;

	item *it = &items[item_count];
	memset(it, 0, sizeof(*it));
	set(&it->service, service);
	set(&it->path, path);
	set(&it->key, key);
	item_count++;

	action entry = { .kind = 12 };
	snprintf(entry.key, KEY_SIZE, "%s", key);
	push(&entry);
}

static void remove_service(const char *service)
{
	int changed = 0;

	for (int i = 0; i < item_count;) {
		if (strcmp(items[i].service, service) != 0) {
			i++;
			continue;
		}

		char key[KEY_SIZE];
		snprintf(key, sizeof(key), "%s", items[i].key);

		free_item(&items[i]);
		memmove(&items[i], &items[i + 1], (size_t)(item_count - i - 1) * sizeof(item));
		memset(&items[item_count - 1], 0, sizeof(item));
		item_count--;
		changed = 1;

		sd_bus_emit_signal(bus, "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher", "StatusNotifierItemUnregistered", "s", key);
	}

	if (changed)
		publish();
}

static int method_register_item(sd_bus_message *m, void *userdata, sd_bus_error *error)
{
	const char *service;
	char name[256];
	char path[256];
	const char *sender = sd_bus_message_get_sender(m);
	const char *slash;

	(void)userdata;
	(void)error;

	if (sd_bus_message_read(m, "s", &service) < 0)
		return -1;

	if (service[0] == '/') {
		snprintf(name, sizeof(name), "%s", sender ? sender : "");
		snprintf(path, sizeof(path), "%s", service);
	} else if ((slash = strchr(service, '/')) != NULL) {
		snprintf(name, sizeof(name), "%.*s", (int)(slash - service), service);
		snprintf(path, sizeof(path), "%s", slash);
	} else {
		snprintf(name, sizeof(name), "%s", service);
		snprintf(path, sizeof(path), "/StatusNotifierItem");
	}

	if (name[0])
		add_item(name, path);

	return sd_bus_reply_method_return(m, NULL);
}

static int method_register_host(sd_bus_message *m, void *userdata, sd_bus_error *error)
{
	(void)userdata;
	(void)error;

	return sd_bus_reply_method_return(m, NULL);
}

static int property_items(sd_bus *b, const char *p, const char *i, const char *name, sd_bus_message *reply, void *userdata, sd_bus_error *error)
{
	(void)b;
	(void)p;
	(void)i;
	(void)name;
	(void)userdata;
	(void)error;

	int r = sd_bus_message_open_container(reply, 'a', "s");
	if (r < 0)
		return r;

	for (int n = 0; n < item_count; n++) {
		r = sd_bus_message_append(reply, "s", items[n].key);
		if (r < 0)
			return r;
	}

	return sd_bus_message_close_container(reply);
}

static int property_host(sd_bus *b, const char *p, const char *i, const char *name, sd_bus_message *reply, void *userdata, sd_bus_error *error)
{
	(void)b;
	(void)p;
	(void)i;
	(void)name;
	(void)userdata;
	(void)error;

	return sd_bus_message_append(reply, "b", 1);
}

static int property_version(sd_bus *b, const char *p, const char *i, const char *name, sd_bus_message *reply, void *userdata, sd_bus_error *error)
{
	(void)b;
	(void)p;
	(void)i;
	(void)name;
	(void)userdata;
	(void)error;

	return sd_bus_message_append(reply, "i", 0);
}

static const sd_bus_vtable watcher_vtable[] = {
	SD_BUS_VTABLE_START(0),
	SD_BUS_METHOD("RegisterStatusNotifierItem", "s", "", method_register_item, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("RegisterStatusNotifierHost", "s", "", method_register_host, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_PROPERTY("RegisteredStatusNotifierItems", "as", property_items, 0, 0),
	SD_BUS_PROPERTY("IsStatusNotifierHostRegistered", "b", property_host, 0, 0),
	SD_BUS_PROPERTY("ProtocolVersion", "i", property_version, 0, 0),
	SD_BUS_SIGNAL("StatusNotifierItemRegistered", "s", 0),
	SD_BUS_SIGNAL("StatusNotifierItemUnregistered", "s", 0),
	SD_BUS_SIGNAL("StatusNotifierHostRegistered", "", 0),
	SD_BUS_VTABLE_END
};

static int on_owner_changed(sd_bus_message *m, void *userdata, sd_bus_error *error)
{
	const char *name, *old_owner, *new_owner;

	(void)userdata;
	(void)error;

	if (sd_bus_message_read(m, "sss", &name, &old_owner, &new_owner) < 0)
		return 0;

	if (new_owner[0] == 0 && old_owner[0] != 0) {
		remove_service(old_owner);
		remove_service(name);
	}

	return 0;
}

static int on_item_signal(sd_bus_message *m, void *userdata, sd_bus_error *error)
{
	const char *sender = sd_bus_message_get_sender(m);
	int menu_signal = userdata != NULL;

	(void)error;

	for (int i = 0; i < item_count; i++) {
		if (sender && strcmp(items[i].service, sender) != 0) {
			sd_bus_creds *creds = NULL;

			if (sd_bus_get_name_creds(bus, items[i].service, SD_BUS_CREDS_UNIQUE_NAME, &creds) < 0)
				continue;

			const char *unique = NULL;
			sd_bus_creds_get_unique_name(creds, &unique);
			int same = unique && strcmp(unique, sender) == 0;
			sd_bus_creds_unref(creds);

			if (!same)
				continue;
		}

		refresh(&items[i], menu_signal);
		publish();
	}

	return 0;
}

static void push(const action *entry)
{
	pthread_mutex_lock(&lock);

	if (queue_count < QUEUE_SIZE) {
		queue[(queue_head + queue_count) % QUEUE_SIZE] = *entry;
		queue_count++;
	}

	pthread_mutex_unlock(&lock);

	if (wake_fd >= 0) {
		uint64_t one = 1;
		ssize_t ignored = write(wake_fd, &one, sizeof(one));
		(void)ignored;
	}
}

void tb_activate(const char *key, int32_t kind)
{
	action entry = { .kind = (int)kind };
	snprintf(entry.key, KEY_SIZE, "%s", key);
	push(&entry);
}

void tb_menu_event(const char *key, int32_t id)
{
	action entry = { .kind = 10, .id = id };
	snprintf(entry.key, KEY_SIZE, "%s", key);
	push(&entry);
}

void tb_menu_open(const char *key)
{
	action entry = { .kind = 11 };
	snprintf(entry.key, KEY_SIZE, "%s", key);
	push(&entry);
}

static void perform(const action *entry)
{
	item *it = find_item(entry->key);

	if (!it)
		return;

	if (entry->kind == 12) {
		refresh(it, 1);
		publish();
		sd_bus_emit_signal(bus, "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher", "StatusNotifierItemRegistered", "s", it->key);
		return;
	}

	if (entry->kind <= 2) {
		static const char *names[] = { "Activate", "SecondaryActivate", "ContextMenu" };
		sd_bus_call_method_async(bus, NULL, it->service, it->path, "org.kde.StatusNotifierItem", names[entry->kind], NULL, NULL, "ii", 0, 0);
		return;
	}

	if (entry->kind == 10) {
		sd_bus_call_method_async(bus, NULL, it->service, it->menu_path, "com.canonical.dbusmenu", "Event", NULL, NULL, "isvu", entry->id, "clicked", "i", 0, (uint32_t)time(NULL));
		return;
	}

	if (entry->kind == 11 && it->menu_path && it->menu_path[0]) {
		sd_bus_message *reply = NULL;
		sd_bus_error error = SD_BUS_ERROR_NULL;

		sd_bus_call_method(bus, it->service, it->menu_path, "com.canonical.dbusmenu", "AboutToShow", &error, &reply, "i", 0);
		sd_bus_error_free(&error);
		sd_bus_message_unref(reply);

		fetch_menu(it);
		publish();
	}
}

static void drain(void)
{
	for (;;) {
		action entry;

		pthread_mutex_lock(&lock);

		if (queue_count == 0) {
			pthread_mutex_unlock(&lock);
			return;
		}

		entry = queue[queue_head];
		queue_head = (queue_head + 1) % QUEUE_SIZE;
		queue_count--;

		pthread_mutex_unlock(&lock);

		perform(&entry);
	}
}

int tb_run(void *ctx, tb_update_fn update)
{
	int r;
	char host[64];

	callback_ctx = ctx;
	on_update = update;

	wake_fd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
	if (wake_fd < 0)
		return -1;

	r = sd_bus_open_user(&bus);
	if (r < 0)
		return r;

	r = sd_bus_add_object_vtable(bus, NULL, "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher", watcher_vtable, NULL);
	if (r < 0)
		return r;

	r = sd_bus_add_match(bus, NULL, "type='signal',sender='org.freedesktop.DBus',interface='org.freedesktop.DBus',member='NameOwnerChanged'", on_owner_changed, NULL);
	if (r < 0)
		return r;

	r = sd_bus_add_match(bus, NULL, "type='signal',interface='org.kde.StatusNotifierItem'", on_item_signal, NULL);
	if (r < 0)
		return r;

	r = sd_bus_add_match(bus, NULL, "type='signal',interface='com.canonical.dbusmenu'", on_item_signal, (void *)1);
	if (r < 0)
		return r;

	r = sd_bus_request_name(bus, "org.kde.StatusNotifierWatcher", SD_BUS_NAME_QUEUE);
	if (r < 0)
		return r;

	snprintf(host, sizeof(host), "org.kde.StatusNotifierHost-%d", (int)getpid());
	sd_bus_request_name(bus, host, 0);
	sd_bus_emit_signal(bus, "/StatusNotifierWatcher", "org.kde.StatusNotifierWatcher", "StatusNotifierHostRegistered", "");

	for (;;) {
		struct pollfd fds[2];
		uint64_t usec = UINT64_MAX;
		int timeout = -1;

		drain();

		while ((r = sd_bus_process(bus, NULL)) > 0)
			;

		if (r < 0)
			return r;

		sd_bus_get_timeout(bus, &usec);

		if (usec != UINT64_MAX)
			timeout = (int)((usec + 999) / 1000);

		fds[0].fd = sd_bus_get_fd(bus);
		fds[0].events = (short)sd_bus_get_events(bus);
		fds[0].revents = 0;
		fds[1].fd = wake_fd;
		fds[1].events = POLLIN;
		fds[1].revents = 0;

		poll(fds, 2, timeout);

		if (fds[1].revents & POLLIN) {
			uint64_t sink;
			ssize_t ignored = read(wake_fd, &sink, sizeof(sink));
			(void)ignored;
		}
	}
}
