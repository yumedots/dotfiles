#include "notifybus.h"

#include <poll.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/eventfd.h>
#include <unistd.h>

#include <systemd/sd-bus.h>

#define QUEUE_SIZE 64
#define KEY_SIZE 128

typedef struct {
	uint32_t id;
	uint32_t reason;
	int is_action;
	char key[KEY_SIZE];
} event;

static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static event queue[QUEUE_SIZE];
static int queue_head;
static int queue_count;
static int wake_fd = -1;
static sd_bus *bus;
static void *callback_ctx;
static nb_notify_fn on_notify;
static nb_close_fn on_close;

static void push(event *entry)
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

void nb_emit_closed(uint32_t id, uint32_t reason)
{
	event entry = { .id = id, .reason = reason };
	push(&entry);
}

void nb_emit_action(uint32_t id, const char *key)
{
	event entry = { .id = id, .is_action = 1 };
	strncpy(entry.key, key, KEY_SIZE - 1);
	push(&entry);
}

static void drain(void)
{
	for (;;) {
		event entry;

		pthread_mutex_lock(&lock);

		if (queue_count == 0) {
			pthread_mutex_unlock(&lock);
			return;
		}

		entry = queue[queue_head];
		queue_head = (queue_head + 1) % QUEUE_SIZE;
		queue_count--;

		pthread_mutex_unlock(&lock);

		if (entry.is_action)
			sd_bus_emit_signal(bus, "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "ActionInvoked", "us", entry.id, entry.key);
		else
			sd_bus_emit_signal(bus, "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "NotificationClosed", "uu", entry.id, entry.reason);
	}
}

static int read_hint(sd_bus_message *m, nb_note *note)
{
	const char *key;
	const char *contents;
	char type;
	int r = sd_bus_message_read(m, "s", &key);

	if (r < 0)
		return r;

	r = sd_bus_message_peek_type(m, &type, &contents);

	if (r < 0)
		return r;

	if (strcmp(key, "urgency") == 0 && strcmp(contents, "y") == 0) {
		uint8_t value;
		r = sd_bus_message_read(m, "v", "y", &value);
		note->urgency = value;
		return r;
	}

	if ((strcmp(key, "desktop-entry") == 0 || strcmp(key, "desktop_entry") == 0) && strcmp(contents, "s") == 0)
		return sd_bus_message_read(m, "v", "s", &note->desktop);

	if ((strcmp(key, "image-path") == 0 || strcmp(key, "image_path") == 0) && strcmp(contents, "s") == 0)
		return sd_bus_message_read(m, "v", "s", &note->image_path);

	if (strcmp(key, "sender-pid") == 0 && strlen(contents) == 1) {
		int64_t value = 0;

		if (contents[0] == 'i' || contents[0] == 'u' || contents[0] == 'x' || contents[0] == 't') {
			r = sd_bus_message_enter_container(m, 'v', contents);
			if (r < 0)
				return r;
			r = sd_bus_message_read_basic(m, contents[0], &value);
			if (r < 0)
				return r;
			note->pid = (int32_t)value;
			return sd_bus_message_exit_container(m);
		}
	}

	if ((strcmp(key, "image-data") == 0 || strcmp(key, "image_data") == 0 || strcmp(key, "icon_data") == 0) && strcmp(contents, "(iiibiiay)") == 0) {
		const void *data;
		size_t size;
		int32_t has_alpha;
		int32_t bits;

		r = sd_bus_message_enter_container(m, 'v', contents);
		if (r < 0)
			return r;
		r = sd_bus_message_enter_container(m, 'r', "iiibiiay");
		if (r < 0)
			return r;
		r = sd_bus_message_read(m, "iiibii", &note->image_width, &note->image_height, &note->image_stride, &has_alpha, &bits, &note->image_channels);
		if (r < 0)
			return r;
		r = sd_bus_message_read_array(m, 'y', &data, &size);
		if (r < 0)
			return r;

		note->image_data = bits == 8 ? data : NULL;
		note->image_size = (uint32_t)size;
		note->image_alpha = has_alpha;

		r = sd_bus_message_exit_container(m);
		if (r < 0)
			return r;
		return sd_bus_message_exit_container(m);
	}

	return sd_bus_message_skip(m, "v");
}

static int method_notify(sd_bus_message *m, void *userdata, sd_bus_error *error)
{
	nb_note note;
	const char *action;
	int r;

	(void)userdata;
	(void)error;
	memset(&note, 0, sizeof(note));

	r = sd_bus_message_read(m, "susss", &note.app, &note.replaces, &note.icon, &note.summary, &note.body);
	if (r < 0)
		return r;

	r = sd_bus_message_enter_container(m, 'a', "s");
	if (r < 0)
		return r;

	while ((r = sd_bus_message_read(m, "s", &action)) > 0) {
		if (note.action_count < NB_MAX_ACTIONS)
			note.actions[note.action_count++] = action;
	}

	if (r < 0)
		return r;

	r = sd_bus_message_exit_container(m);
	if (r < 0)
		return r;

	r = sd_bus_message_enter_container(m, 'a', "{sv}");
	if (r < 0)
		return r;

	while ((r = sd_bus_message_enter_container(m, 'e', "sv")) > 0) {
		r = read_hint(m, &note);
		if (r < 0)
			return r;

		r = sd_bus_message_exit_container(m);
		if (r < 0)
			return r;
	}

	if (r < 0)
		return r;

	r = sd_bus_message_exit_container(m);
	if (r < 0)
		return r;

	r = sd_bus_message_read(m, "i", &note.timeout);
	if (r < 0)
		return r;

	if (note.pid == 0) {
		sd_bus_creds *creds = NULL;
		pid_t pid = 0;

		if (sd_bus_query_sender_creds(m, SD_BUS_CREDS_PID, &creds) >= 0) {
			sd_bus_creds_get_pid(creds, &pid);
			note.pid = (int32_t)pid;
		}

		sd_bus_creds_unref(creds);
	}

	uint32_t id = on_notify(callback_ctx, &note);

	return sd_bus_reply_method_return(m, "u", id);
}

static int method_close(sd_bus_message *m, void *userdata, sd_bus_error *error)
{
	uint32_t id;
	int r;

	(void)userdata;
	(void)error;

	r = sd_bus_message_read(m, "u", &id);
	if (r < 0)
		return r;

	on_close(callback_ctx, id);
	sd_bus_emit_signal(bus, "/org/freedesktop/Notifications", "org.freedesktop.Notifications", "NotificationClosed", "uu", id, (uint32_t)3);

	return sd_bus_reply_method_return(m, NULL);
}

static int method_capabilities(sd_bus_message *m, void *userdata, sd_bus_error *error)
{
	(void)userdata;
	(void)error;

	return sd_bus_reply_method_return(m, "as", 5, "actions", "body", "body-markup", "body-hyperlinks", "icon-static");
}

static int method_info(sd_bus_message *m, void *userdata, sd_bus_error *error)
{
	(void)userdata;
	(void)error;

	return sd_bus_reply_method_return(m, "ssss", "yudaemond", "yudae", "1.0", "1.2");
}

static const sd_bus_vtable vtable[] = {
	SD_BUS_VTABLE_START(0),
	SD_BUS_METHOD("Notify", "susssasa{sv}i", "u", method_notify, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("CloseNotification", "u", "", method_close, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("GetCapabilities", "", "as", method_capabilities, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_METHOD("GetServerInformation", "", "ssss", method_info, SD_BUS_VTABLE_UNPRIVILEGED),
	SD_BUS_SIGNAL("NotificationClosed", "uu", 0),
	SD_BUS_SIGNAL("ActionInvoked", "us", 0),
	SD_BUS_VTABLE_END
};

int nb_run(void *ctx, nb_notify_fn notify, nb_close_fn close_fn)
{
	int r;

	callback_ctx = ctx;
	on_notify = notify;
	on_close = close_fn;

	wake_fd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
	if (wake_fd < 0)
		return -1;

	r = sd_bus_open_user(&bus);
	if (r < 0)
		return r;

	r = sd_bus_add_object_vtable(bus, NULL, "/org/freedesktop/Notifications", "org.freedesktop.Notifications", vtable, NULL);
	if (r < 0)
		return r;

	r = sd_bus_request_name(bus, "org.freedesktop.Notifications", SD_BUS_NAME_QUEUE);
	if (r < 0)
		return r;

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
