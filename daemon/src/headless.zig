const std = @import("std");
const hubmod = @import("hub.zig");
const ipc = @import("ipc.zig");
const proc = @import("primitives/proc.zig");
const sock = @import("primitives/sock.zig");
const json = @import("primitives/json.zig");
const sleep = @import("primitives/sleep.zig");
const daemon = @import("providers/daemon.zig");

const allocator = std.heap.smp_allocator;
const Io = std.Io;

const Minimal = struct {
	io: Io,
	hub: *hubmod.Hub,
	daemon: *daemon.Daemon,
	socket_path: []const u8,
};

fn snapshotThunk(ctx: *anyopaque, allocator_: std.mem.Allocator) anyerror![]u8 {
	const self: *Minimal = @ptrCast(@alignCast(ctx));
	return self.hub.snapshot(allocator_);
}

fn syncThunk(ctx: *anyopaque, allocator_: std.mem.Allocator) anyerror![]u8 {
	const self: *Minimal = @ptrCast(@alignCast(ctx));
	return self.hub.syncSnapshot(allocator_);
}

fn commandThunk(ctx: *anyopaque, value: json.Value) void {
	_ = ctx;
	_ = value;
}

fn callThunk(ctx: *anyopaque, target: []const u8, method: []const u8, args: json.Value, allocator_: std.mem.Allocator) anyerror![]u8 {
	const self: *Minimal = @ptrCast(@alignCast(ctx));
	_ = method;
	_ = args;

	if (std.mem.eql(u8, target, "state") or std.mem.eql(u8, target, "ui")) return self.hub.syncSnapshot(allocator_);

	return allocator_.dupe(u8, "{}");
}

pub fn main() !void {
	const env = try @import("primitives/environ.zig").current(std.Io.Threaded.global_single_threaded.io(), allocator);
	var threaded: std.Io.Threaded = .init(allocator, .{ .environ = env, .async_limit = .nothing, .concurrent_limit = .nothing, .stack_size = 256 * 1024 });
	const io = threaded.io();

	const args = try proc.args(io, allocator);
	const command = if (args.len > 1) args[1] else "run";

	if (!std.mem.eql(u8, command, "run")) {
		std.debug.print("usage: yudaemond-headless run\n", .{});
		return;
	}

	try run(io);
}

fn run(io: Io) !void {
	const socket_path = try proc.socketPath(io, allocator);
	const lock_path = try std.fmt.allocPrint(allocator, "{s}.lock", .{socket_path});

	var guard = (try sock.Lock.take(lock_path)) orelse {
		std.debug.print("yudaemond already serves {s}\n", .{socket_path});
		return;
	};
	defer guard.release();

	const hub = try allocator.create(hubmod.Hub);
	hub.* = .{ .allocator = allocator, .io = io };

	const daemon_provider = try daemon.Daemon.create(allocator, io, hub);
	try hub.add(daemon_provider.provider());

	const context = try allocator.create(Minimal);
	context.* = .{
		.io = io,
		.hub = hub,
		.daemon = daemon_provider,
		.socket_path = socket_path,
	};

	std.debug.print("yudaemond-headless listening on {s}\n", .{socket_path});

	hub.ipc = try ipc.Ipc.init(allocator, io, socket_path, .{
		.ctx = context,
		.snapshot = snapshotThunk,
		.sync = syncThunk,
		.command = commandThunk,
		.call = callThunk,
	});

	try hub.ipc.?.start();
	daemon_provider.markListening();
	hub.ipc.?.startVsock(1024) catch {};

	while (true) sleep.ms(1000);
}
