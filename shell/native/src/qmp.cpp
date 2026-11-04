#include "qmp.h"

#include <QMetaObject>
#include <QByteArray>
#include <QThread>
#include <QDebug>

#undef signals
#include <gio/gio.h>
#include <gio/gunixfdlist.h>

#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

#include <cstring>
#include <functional>
#include <mutex>
#include <thread>

namespace {

const char *kListenerXml =
	"<node>"
	"<interface name='org.qemu.Display1.Listener'>"
	"<method name='Scanout'><arg type='u'/><arg type='u'/><arg type='u'/><arg type='u'/><arg type='ay'/></method>"
	"<method name='Update'><arg type='i'/><arg type='i'/><arg type='i'/><arg type='i'/><arg type='u'/><arg type='u'/><arg type='ay'/></method>"
	"<method name='UpdateDMABUF'><arg type='i'/><arg type='i'/><arg type='i'/><arg type='i'/></method>"
	"<method name='Disable'/>"
	"<method name='MouseSet'><arg type='i'/><arg type='i'/><arg type='i'/></method>"
	"<method name='CursorDefine'><arg type='i'/><arg type='i'/><arg type='i'/><arg type='i'/><arg type='ay'/></method>"
	"<property name='Interfaces' type='as' access='read'/>"
	"</interface>"
	"<interface name='org.qemu.Display1.Listener.Unix.Map'>"
	"<method name='ScanoutMap'><arg type='h'/><arg type='u'/><arg type='u'/><arg type='u'/><arg type='u'/><arg type='u'/></method>"
	"<method name='UpdateMap'><arg type='i'/><arg type='i'/><arg type='i'/><arg type='i'/></method>"
	"</interface>"
	"<interface name='org.qemu.Display1.Listener.Unix.ScanoutDMABUF2'>"
	"<method name='ScanoutDMABUF2'><arg type='ah'/><arg type='u'/><arg type='u'/><arg type='u'/><arg type='u'/><arg type='au'/><arg type='au'/><arg type='u'/><arg type='u'/><arg type='u'/><arg type='u'/><arg type='t'/><arg type='b'/></method>"
	"</interface>"
	"</node>";

int qmpConnect(const char *path) {
	int fd = socket(AF_UNIX, SOCK_STREAM, 0);
	sockaddr_un addr{};
	addr.sun_family = AF_UNIX;
	std::snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", path);
	if (connect(fd, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) < 0) {
		close(fd);
		return -1;
	}
	return fd;
}

bool qmpSend(int fd, const char *body, int passFd) {
	QByteArray msg = QByteArray(body) + "\n";
	if (passFd < 0) return send(fd, msg.constData(), msg.size(), 0) == msg.size();

	iovec iov{const_cast<char *>(msg.constData()), static_cast<size_t>(msg.size())};
	char cbuf[CMSG_SPACE(sizeof(int))];
	msghdr mh{};
	mh.msg_iov = &iov;
	mh.msg_iovlen = 1;
	mh.msg_control = cbuf;
	mh.msg_controllen = sizeof(cbuf);
	cmsghdr *cm = CMSG_FIRSTHDR(&mh);
	cm->cmsg_level = SOL_SOCKET;
	cm->cmsg_type = SCM_RIGHTS;
	cm->cmsg_len = CMSG_LEN(sizeof(int));
	std::memcpy(CMSG_DATA(cm), &passFd, sizeof(int));
	return sendmsg(fd, &mh, 0) == msg.size();
}

bool qmpWait(int fd, const char *needle) {
	char buf[8192];
	QByteArray acc;
	while (true) {
		ssize_t n = recv(fd, buf, sizeof(buf), 0);
		if (n <= 0) return false;
		acc.append(buf, n);
		int p;
		while ((p = acc.indexOf('\n')) >= 0) {
			QByteArray line = acc.left(p);
			acc.remove(0, p + 1);
			if (line.contains("error")) return false;
			if (line.contains(needle)) return true;
		}
	}
}

} // namespace

struct QmpDisplay::Impl {
	QmpDisplay *q = nullptr;
	std::thread thread;
	GMainContext *context = nullptr;
	GMainLoop *loop = nullptr;
	GMainContext *listenerContext = nullptr;
	GMainLoop *listenerLoop = nullptr;
	std::thread listenerThread;
	GDBusConnection *control = nullptr;
	GDBusConnection *listener = nullptr;
	GCancellable *cancel = nullptr;
	bool running = false;
	QString qmpPath;
	int width = 0;
	int height = 0;

	std::mutex frameMutex;
	Frame pendingFrame;
	std::mutex mapMutex;
	Map pendingMap;
	std::mutex pixmapMutex;
	Pixmap pendingPixmap;
	bool hasPixmap = false;

	void post(std::function<void()> fn) {
		auto *heap = new std::function<void()>(std::move(fn));
		g_main_context_invoke_full(context, G_PRIORITY_DEFAULT, [](gpointer data) -> gboolean {
			auto *f = static_cast<std::function<void()> *>(data);
			(*f)();
			delete f;
			return G_SOURCE_REMOVE;
		}, heap, nullptr);
	}

	void call(const char *iface, const char *method, GVariant *params) {
		if (!control) return;
		g_dbus_connection_call(control, nullptr, "/org/qemu/Display1/Console_0", iface, method, params,
			nullptr, G_DBUS_CALL_FLAGS_NONE, -1, nullptr, nullptr, nullptr);
	}

	void callSync(const char *iface, const char *method, GVariant *params) {
		if (!control) return;
		GError *err = nullptr;
		GVariant *r = g_dbus_connection_call_sync(control, nullptr, "/org/qemu/Display1/Console_0", iface, method,
			params, nullptr, G_DBUS_CALL_FLAGS_NONE, 5000, nullptr, &err);
		if (r) g_variant_unref(r);
		if (err) g_error_free(err);
	}

	static void onMethod(GDBusConnection *, const gchar *, const gchar *, const gchar *iface, const gchar *method,
	                     GVariant *params, GDBusMethodInvocation *inv, gpointer user) {
		auto *d = static_cast<Impl *>(user);
		if (g_str_equal(iface, "org.qemu.Display1.Listener.Unix.ScanoutDMABUF2") && g_str_equal(method, "ScanoutDMABUF2")) {
			GVariant *fds = g_variant_get_child_value(params, 0);
			guint32 x = g_variant_get_uint32(g_variant_get_child_value(params, 1));
			guint32 y = g_variant_get_uint32(g_variant_get_child_value(params, 2));
			guint32 w = g_variant_get_uint32(g_variant_get_child_value(params, 3));
			guint32 h = g_variant_get_uint32(g_variant_get_child_value(params, 4));
			GVariant *offsets = g_variant_get_child_value(params, 5);
			GVariant *strides = g_variant_get_child_value(params, 6);
			guint32 planes = g_variant_get_uint32(g_variant_get_child_value(params, 7));
			guint32 fourcc = g_variant_get_uint32(g_variant_get_child_value(params, 8));
			guint32 bw = g_variant_get_uint32(g_variant_get_child_value(params, 9));
			guint32 bh = g_variant_get_uint32(g_variant_get_child_value(params, 10));
			guint64 modifier = g_variant_get_uint64(g_variant_get_child_value(params, 11));
			gboolean y0top = g_variant_get_boolean(g_variant_get_child_value(params, 12));
			GUnixFDList *fdlist = g_dbus_message_get_unix_fd_list(g_dbus_method_invocation_get_message(inv));
			Frame frame;
			frame.fourcc = fourcc;
			frame.modLo = static_cast<uint32_t>(modifier & 0xffffffffu);
			frame.modHi = static_cast<uint32_t>(modifier >> 32);
			frame.x = x; frame.y = y; frame.w = w; frame.h = h;
			frame.bw = bw; frame.bh = bh; frame.y0top = y0top;
			if (planes > 0 && planes < 4 && fdlist) {
				gint32 index = 0;
				g_variant_get_child(fds, 0, "h", &index);
				GError *err = nullptr;
				frame.fd = g_unix_fd_list_get(fdlist, index, &err);
				if (err) g_error_free(err);
				if (g_variant_n_children(offsets) > 0) frame.offset = g_variant_get_uint32(g_variant_get_child_value(offsets, 0));
				if (g_variant_n_children(strides) > 0) frame.stride = g_variant_get_uint32(g_variant_get_child_value(strides, 0));
			}
			g_variant_unref(fds);
			g_variant_unref(offsets);
			g_variant_unref(strides);
			{
				std::lock_guard<std::mutex> lock(d->frameMutex);
				if (d->pendingFrame.fd >= 0) close(d->pendingFrame.fd);
				d->pendingFrame = frame;
			}
				emit d->q->frameReady();
			g_dbus_method_invocation_return_value(inv, nullptr);
			return;
		}
		if (g_str_equal(iface, "org.qemu.Display1.Listener.Unix.Map") && g_str_equal(method, "ScanoutMap")) {
			gint32 handle = 0;
			guint32 offset, w, h, stride, format;
			g_variant_get(params, "(huuuuu)", &handle, &offset, &w, &h, &stride, &format);
			GUnixFDList *fdlist = g_dbus_message_get_unix_fd_list(g_dbus_method_invocation_get_message(inv));
			Map map;
			map.offset = offset; map.w = w; map.h = h; map.stride = stride; map.format = format;
			if (fdlist) {
				GError *err = nullptr;
				map.fd = g_unix_fd_list_get(fdlist, handle, &err);
				if (err) g_error_free(err);
			}
			{
				std::lock_guard<std::mutex> lock(d->mapMutex);
				if (d->pendingMap.fd >= 0) close(d->pendingMap.fd);
				d->pendingMap = map;
			}
			emit d->q->mapReady();
			g_dbus_method_invocation_return_value(inv, nullptr);
			return;
		}
		if (g_str_equal(iface, "org.qemu.Display1.Listener") && g_str_equal(method, "Scanout")) {
			guint32 w, h, stride, format;
			GVariant *data = nullptr;
			g_variant_get(params, "(uuuu@ay)", &w, &h, &stride, &format, &data);
			Pixmap pixmap;
			pixmap.w = w; pixmap.h = h; pixmap.stride = stride; pixmap.format = format;
			pixmap.data = QByteArray(static_cast<const char *>(g_variant_get_data(data)), static_cast<int>(g_variant_get_size(data)));
			if (data) g_variant_unref(data);
			{
				std::lock_guard<std::mutex> lock(d->pixmapMutex);
				d->pendingPixmap = pixmap;
				d->hasPixmap = true;
			}
			emit d->q->pixmapReady();
			g_dbus_method_invocation_return_value(inv, nullptr);
			return;
		}
		if (g_str_equal(iface, "org.qemu.Display1.Listener") && g_str_equal(method, "Update")) {
			gint32 x, y, w, h;
			guint32 stride, format;
			GVariant *data = nullptr;
			g_variant_get(params, "(iiiiuu@ay)", &x, &y, &w, &h, &stride, &format, &data);
			Pixmap pixmap;
			pixmap.x = x; pixmap.y = y; pixmap.uw = w; pixmap.uh = h;
			pixmap.stride = stride; pixmap.format = format; pixmap.update = true;
			pixmap.data = QByteArray(static_cast<const char *>(g_variant_get_data(data)), static_cast<int>(g_variant_get_size(data)));
			if (data) g_variant_unref(data);
			{
				std::lock_guard<std::mutex> lock(d->pixmapMutex);
				d->pendingPixmap = pixmap;
				d->hasPixmap = true;
			}
			emit d->q->pixmapReady();
			g_dbus_method_invocation_return_value(inv, nullptr);
			return;
		}
		if (g_str_equal(iface, "org.qemu.Display1.Listener") && g_str_equal(method, "UpdateDMABUF")) {
			gint32 x, y, w, h;
			g_variant_get(params, "(iiii)", &x, &y, &w, &h);
			emit d->q->updated(x, y, w, h);
			g_dbus_method_invocation_return_value(inv, nullptr);
			return;
		}
		if (g_str_equal(method, "UpdateMap")) {
			gint32 x, y, w, h;
			g_variant_get(params, "(iiii)", &x, &y, &w, &h);
			emit d->q->updated(x, y, w, h);
			g_dbus_method_invocation_return_value(inv, nullptr);
			return;
		}
		if (g_str_equal(method, "MouseSet")) {
			gint32 x, y, on;
			g_variant_get(params, "(iii)", &x, &y, &on);
			emit d->q->mouseState(x, y, on != 0);
			g_dbus_method_invocation_return_value(inv, nullptr);
			return;
		}
		if (g_str_equal(method, "CursorDefine")) {
			gint32 cw, ch, hx, hy;
			GVariant *data = nullptr;
			g_variant_get(params, "(iiii@ay)", &cw, &ch, &hx, &hy, &data);
			if (cw > 0 && ch > 0 && g_variant_get_size(data) >= static_cast<gsize>(cw) * ch * 4) {
				QImage image(cw, ch, QImage::Format_ARGB32);
				std::memcpy(image.bits(), g_variant_get_data(data), static_cast<size_t>(cw) * ch * 4);
				emit d->q->cursorImage(image, hx, hy);
			}
			if (data) g_variant_unref(data);
			g_dbus_method_invocation_return_value(inv, nullptr);
			return;
		}
		if (g_str_equal(method, "Disable")) {
			std::lock_guard<std::mutex> lock(d->frameMutex);
			if (d->pendingFrame.fd >= 0) close(d->pendingFrame.fd);
			d->pendingFrame = Frame{};
			g_dbus_method_invocation_return_value(inv, nullptr);
			return;
		}
		g_dbus_method_invocation_return_value(inv, nullptr);
	}

	static GVariant *onProperty(GDBusConnection *, const gchar *, const gchar *, const gchar *, const gchar *property,
	                            GError **, gpointer) {
		if (g_str_equal(property, "Interfaces")) {
			const gchar *list[] = {"org.qemu.Display1.Listener", "org.qemu.Display1.Listener.Unix.Map",
			                       "org.qemu.Display1.Listener.Unix.ScanoutDMABUF2", nullptr};
			return g_variant_new_strv(list, -1);
		}
		return nullptr;
	}

	bool connectControl(int qmp) {
		int pair[2];
		if (socketpair(AF_UNIX, SOCK_STREAM, 0, pair) < 0) return false;
		if (!qmpSend(qmp, "{\"execute\":\"getfd\",\"arguments\":{\"fdname\":\"viewer\"}}", pair[1])) return false;
		if (!qmpWait(qmp, "\"return\"")) return false;
		close(pair[1]);
		if (!qmpSend(qmp, "{\"execute\":\"add_client\",\"arguments\":{\"protocol\":\"@dbus-display\",\"fdname\":\"viewer\"}}", -1)) return false;
		if (!qmpWait(qmp, "\"return\"")) return false;

		GError *err = nullptr;
		GSocket *socket = g_socket_new_from_fd(pair[0], &err);
		if (!socket) return false;
		GSocketConnection *conn = g_socket_connection_factory_create_connection(socket);
		control = g_dbus_connection_new_sync(G_IO_STREAM(conn), nullptr, G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT,
		                                     nullptr, nullptr, &err);
		if (!control) {
			if (err) g_error_free(err);
			return false;
		}
		return true;
	}

	bool connectListener() {
		int pair[2];
		if (socketpair(AF_UNIX, SOCK_STREAM, 0, pair) < 0) return false;

		listenerContext = g_main_context_new();
		listenerLoop = g_main_loop_new(listenerContext, FALSE);
		listenerThread = std::thread([this, fd = pair[0]]() {
			g_main_context_push_thread_default(listenerContext);
			GError *err = nullptr;
			GSocket *socket = g_socket_new_from_fd(fd, &err);
			GSocketConnection *conn = socket ? g_socket_connection_factory_create_connection(socket) : nullptr;
			if (conn) {
				listener = g_dbus_connection_new_sync(G_IO_STREAM(conn), nullptr,
					(GDBusConnectionFlags)(G_DBUS_CONNECTION_FLAGS_AUTHENTICATION_CLIENT | G_DBUS_CONNECTION_FLAGS_DELAY_MESSAGE_PROCESSING),
					nullptr, nullptr, &err);
			}
			if (err) g_error_free(err);
			if (listener) {
				GDBusNodeInfo *info = g_dbus_node_info_new_for_xml(kListenerXml, nullptr);
				static GDBusInterfaceVTable vtable = {onMethod, onProperty, nullptr, {nullptr}};
				for (int i = 0; info && info->interfaces[i]; i++) {
					g_dbus_connection_register_object(listener, "/org/qemu/Display1/Listener", info->interfaces[i],
					                                  &vtable, this, nullptr, nullptr);
				}
				g_dbus_connection_start_message_processing(listener);
				g_main_loop_run(listenerLoop);
			}
			g_main_context_pop_thread_default(listenerContext);
		});

		GError *err = nullptr;
		GUnixFDList *fdlist = g_unix_fd_list_new();
		g_unix_fd_list_append(fdlist, pair[1], &err);
		close(pair[1]);
		GVariant *reply = g_dbus_connection_call_with_unix_fd_list_sync(control, nullptr,
			"/org/qemu/Display1/Console_0", "org.qemu.Display1.Console", "RegisterListener",
			g_variant_new("(h)", 0), G_VARIANT_TYPE("()"), G_DBUS_CALL_FLAGS_NONE, 5000, fdlist, nullptr, nullptr, &err);
		g_object_unref(fdlist);
		if (err) g_error_free(err);
		if (reply) g_variant_unref(reply);
		return true;
	}

	void run() {
		g_main_context_push_thread_default(context);
		int qmp = qmpConnect(qmpPath.toUtf8().constData());
		if (qmp < 0) {
			emit q->failed("qmp connect");
			g_main_context_pop_thread_default(context);
			return;
		}
		qmpSend(qmp, "{\"execute\":\"qmp_capabilities\"}", -1);
		if (!connectControl(qmp)) {
			emit q->failed("dbus control");
			close(qmp);
			g_main_context_pop_thread_default(context);
			return;
		}
		close(qmp);
		if (width > 0 && height > 0) callSync("org.qemu.Display1.Console", "SetUIInfo", g_variant_new("(qqiiuu)", 600, 340, 0, 0, width, height));
		if (!connectListener()) {
			emit q->failed("dbus listener");
			g_main_context_pop_thread_default(context);
			return;
		}
		running = true;
		g_timeout_add(600, [](gpointer data) -> gboolean {
			auto *d = static_cast<Impl *>(data);
			const int nw = d->width > 1 ? d->width / 2 : 0;
			const int nh = d->height > 1 ? d->height / 2 : 0;
			if (nw > 0 && nh > 0) {
				d->callSync("org.qemu.Display1.Console", "SetUIInfo", g_variant_new("(qqiiuu)", 600, 340, 0, 0, nw, nh));
				g_timeout_add(700, [](gpointer data2) -> gboolean {
					auto *d2 = static_cast<Impl *>(data2);
					d2->callSync("org.qemu.Display1.Console", "SetUIInfo", g_variant_new("(qqiiuu)", 600, 340, 0, 0, d2->width, d2->height));
					return G_SOURCE_REMOVE;
				}, d);
			}
			return G_SOURCE_REMOVE;
		}, this);
		g_main_loop_run(loop);
		running = false;
		g_main_context_pop_thread_default(context);
	}

	void stop() {
		if (loop) g_main_loop_quit(loop);
		if (listenerLoop) g_main_loop_quit(listenerLoop);
		if (cancel) g_cancellable_cancel(cancel);
		if (thread.joinable()) thread.join();
		if (listenerThread.joinable()) listenerThread.join();
	}

	void reset() {
		stop();
		cleanup();
		context = nullptr;
		loop = nullptr;
		listenerContext = nullptr;
		listenerLoop = nullptr;
		control = nullptr;
		listener = nullptr;
		cancel = nullptr;
	}

	void cleanup() {
		{
			std::lock_guard<std::mutex> lock(frameMutex);
			if (pendingFrame.fd >= 0) close(pendingFrame.fd);
			pendingFrame = Frame{};
		}
		{
			std::lock_guard<std::mutex> lock(mapMutex);
			if (pendingMap.fd >= 0) close(pendingMap.fd);
			pendingMap = Map{};
		}
		if (listener) g_object_unref(listener);
		if (control) g_object_unref(control);
		if (listenerLoop) g_main_loop_unref(listenerLoop);
		if (listenerContext) g_main_context_unref(listenerContext);
		if (loop) g_main_loop_unref(loop);
		if (cancel) g_object_unref(cancel);
		if (context) g_main_context_unref(context);
	}
};

QmpDisplay::QmpDisplay(QObject *parent) : QObject(parent), d(new Impl) {
	d->q = this;
}

QmpDisplay::~QmpDisplay() {
	d->reset();
}

void QmpDisplay::start(const QString &qmpPath, int width, int height) {
	d->reset();
	d->qmpPath = qmpPath;
	d->width = width;
	d->height = height;
	d->context = g_main_context_new();
	d->loop = g_main_loop_new(d->context, FALSE);
	d->cancel = g_cancellable_new();
	d->thread = std::thread([this]() { d->run(); });
}

void QmpDisplay::stop() {
	d->stop();
}

void QmpDisplay::setUiInfo(int width, int height) {
	d->width = width;
	d->height = height;
	d->post([this, width, height]() {
		d->callSync("org.qemu.Display1.Console", "SetUIInfo", g_variant_new("(qqiiuu)", 600, 340, 0, 0, width, height));
	});
}

void QmpDisplay::key(int qnum, bool down) {
	d->post([this, qnum, down]() {
		d->call("org.qemu.Display1.Keyboard", down ? "Press" : "Release", g_variant_new("(u)", static_cast<guint32>(qnum)));
	});
}

void QmpDisplay::mouseAbs(int x, int y) {
	d->post([this, x, y]() {
		d->call("org.qemu.Display1.Mouse", "SetAbsPosition", g_variant_new("(uu)", static_cast<guint32>(x), static_cast<guint32>(y)));
	});
}

void QmpDisplay::mouseButton(int button, bool down) {
	d->post([this, button, down]() {
		d->call("org.qemu.Display1.Mouse", down ? "Press" : "Release", g_variant_new("(u)", static_cast<guint32>(button)));
	});
}

void QmpDisplay::wheel(bool up) {
	d->post([this, up]() {
		guint32 button = up ? 3 : 4;
		d->call("org.qemu.Display1.Mouse", "Press", g_variant_new("(u)", button));
		d->call("org.qemu.Display1.Mouse", "Release", g_variant_new("(u)", button));
	});
}

bool QmpDisplay::hasFrame() const {
	std::lock_guard<std::mutex> lock(const_cast<Impl *>(d.get())->frameMutex);
	return d->pendingFrame.fd >= 0;
}

QmpDisplay::Frame QmpDisplay::takeFrame() {
	std::lock_guard<std::mutex> lock(d->frameMutex);
	Frame frame = d->pendingFrame;
	d->pendingFrame = Frame{};
	return frame;
}

QmpDisplay::Map QmpDisplay::takeMap() {
	std::lock_guard<std::mutex> lock(d->mapMutex);
	Map map = d->pendingMap;
	d->pendingMap = Map{};
	return map;
}

QmpDisplay::Pixmap QmpDisplay::takePixmap() {
	std::lock_guard<std::mutex> lock(d->pixmapMutex);
	if (!d->hasPixmap) return Pixmap{};
	Pixmap pixmap = d->pendingPixmap;
	d->pendingPixmap = Pixmap{};
	d->hasPixmap = false;
	return pixmap;
}
