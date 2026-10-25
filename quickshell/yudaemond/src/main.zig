const std = @import("std");
const hubmod = @import("hub.zig");
const ipc = @import("ipc.zig");
const proc = @import("primitives/proc.zig");
const sock = @import("primitives/sock.zig");
const http = @import("primitives/http.zig");
const opencode = @import("providers/opencode.zig");
const codex = @import("providers/codex.zig");
const cursor = @import("providers/cursor.zig");
const daemon = @import("providers/daemon.zig");
const github = @import("providers/github.zig");
const cli = @import("cli.zig");
const sleep = @import("primitives/sleep.zig");
const environ = @import("primitives/environ.zig");

pub const allocator = std.heap.smp_allocator;

pub const Context = struct {
	allocator: std.mem.Allocator,
	io: std.Io,
	hub: *hubmod.Hub,
	client: *http.Client,
	opencode: *opencode.Opencode,
	codex: *codex.Codex,
	cursor: *cursor.Cursor,
	daemon: *daemon.Daemon,
	github: *github.Github,
	socket_path: []const u8,
};

pub fn socketPath(io: std.Io, allocator_: std.mem.Allocator) ![]u8 {
	return proc.socketPath(io, allocator_);
}

fn dismissThunk(ctx: *anyopaque, id: []const u8) void {
	const context: *Context = @ptrCast(@alignCast(ctx));
	context.opencode.dismiss(id);
}

fn snapshotThunk(ctx: *anyopaque, allocator_: std.mem.Allocator) anyerror![]u8 {
	const context: *Context = @ptrCast(@alignCast(ctx));
	return context.hub.snapshot(allocator_);
}

fn refreshThunk(ctx: *anyopaque) void {
	const context: *Context = @ptrCast(@alignCast(ctx));
	context.opencode.refreshAll();
	context.codex.refresh();
	context.github.refresh();
}

pub fn main() !void {
	const env = try environ.current(std.Io.Threaded.global_single_threaded.io(), allocator);
	var threaded: std.Io.Threaded = .init(allocator, .{ .environ = env, .async_limit = .nothing, .concurrent_limit = .nothing, .stack_size = 512 * 1024 });
	const io = threaded.io();

	const args = try proc.args(io, allocator);

	const command = if (args.len > 1) args[1] else "run";

	if (std.mem.eql(u8, command, "state") or std.mem.eql(u8, command, "--json")) {
		return cli.state(io, args);
	}

	if (std.mem.eql(u8, command, "doctor")) return cli.doctor(io, args);
	if (std.mem.eql(u8, command, "bench")) return cli.bench(io, args);
	if (std.mem.eql(u8, command, "parity")) return cli.parity(io, args);
	if (std.mem.eql(u8, command, "mcp")) return cli.mcp(io, args);

	if (!std.mem.eql(u8, command, "run")) {
		std.debug.print("usage: yudaemond [run|state|doctor|bench|parity|mcp]\n", .{});
		return;
	}

	try run(io);
}

fn run(io: std.Io) !void {
	const hub = try allocator.create(hubmod.Hub);
	hub.* = .{ .allocator = allocator, .io = io };

	const client = try allocator.create(http.Client);
	client.* = http.Client.init(allocator, io);

	const opencode_provider = try opencode.Opencode.create(allocator, io, hub, client);
	try hub.add(opencode_provider.provider());

	const codex_provider = try codex.Codex.create(allocator, io, hub, client);
	try hub.add(codex_provider.provider());

	const cursor_provider = try cursor.Cursor.create(allocator, io, hub);
	try hub.add(cursor_provider.provider());

	const daemon_provider = try daemon.Daemon.create(allocator, io, hub);
	try hub.add(daemon_provider.provider());

	const github_provider = try github.Github.create(allocator, io, hub, client);
	try hub.add(github_provider.provider());

	const context = try allocator.create(Context);
	context.* = .{
		.allocator = allocator,
		.io = io,
		.hub = hub,
		.client = client,
		.opencode = opencode_provider,
		.codex = codex_provider,
		.cursor = cursor_provider,
		.daemon = daemon_provider,
		.github = github_provider,
		.socket_path = try socketPath(io, allocator),
	};

	std.debug.print("yudaemond listening on {s}\n", .{context.socket_path});

	hub.ipc = try ipc.Ipc.init(allocator, io, context.socket_path, .{
		.ctx = context,
		.snapshot = snapshotThunk,
		.dismiss = dismissThunk,
		.refresh = refreshThunk,
	});

	try hub.ipc.?.start();
	daemon_provider.markListening();
	try opencode_provider.start();
	try codex_provider.start();
	try cursor_provider.start();
	try github_provider.start();

	hub.publish();

	sleep.forever();
}
