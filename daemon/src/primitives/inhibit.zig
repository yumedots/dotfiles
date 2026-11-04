const std = @import("std");

const Bus = opaque {};
const Message = opaque {};

const Error = extern struct {
	name: ?[*:0]const u8 = null,
	message: ?[*:0]const u8 = null,
	need_free: c_int = 0,
};

const destination: [*:0]const u8 = "org.freedesktop.login1";
const path: [*:0]const u8 = "/org/freedesktop/login1";
const interface: [*:0]const u8 = "org.freedesktop.login1.Manager";
const member: [*:0]const u8 = "Inhibit";
const signature: [*:0]const u8 = "ssss";
const what: [*:0]const u8 = "idle:sleep";
const who: [*:0]const u8 = "yudae";
const mode: [*:0]const u8 = "block";
const read_signature: [*:0]const u8 = "h";

extern fn sd_bus_open_system(bus: *?*Bus) c_int;
extern fn sd_bus_flush_close_unref(bus: *Bus) *Bus;
extern fn sd_bus_error_free(err: *Error) void;
extern fn sd_bus_message_unref(message: *Message) *Message;
extern fn sd_bus_call_method(bus: *Bus, dest: [*:0]const u8, path: [*:0]const u8, iface: [*:0]const u8, member: [*:0]const u8, err: *Error, reply: *?*Message, signature: [*:0]const u8, ...) c_int;
extern fn sd_bus_message_read(message: *Message, signature: [*:0]const u8, ...) c_int;
extern fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
extern fn close(fd: c_int) c_int;

pub fn hold(why: [*:0]const u8) c_int {
	var bus: ?*Bus = null;
	var reply: ?*Message = null;
	var err: Error = .{};

	defer sd_bus_error_free(&err);

	if (sd_bus_open_system(&bus) < 0) return -1;
	defer _ = sd_bus_flush_close_unref(bus.?);

	if (sd_bus_call_method(bus.?, destination, path, interface, member, &err, &reply, signature, what, who, why, mode) < 0) return -1;
	if (reply == null) return -1;
	defer _ = sd_bus_message_unref(reply.?);

	var fd: c_int = -1;
	if (sd_bus_message_read(reply.?, read_signature, &fd) < 0) return -1;

	return fcntl(fd, std.posix.F.DUPFD_CLOEXEC, @as(c_int, 3));
}

pub fn release(fd: c_int) void {
	if (fd >= 0) _ = close(fd);
}
