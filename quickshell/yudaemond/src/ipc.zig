const std = @import("std");
const sock = @import("primitives/sock.zig");
const json = @import("primitives/json.zig");

pub const Io = std.Io;
pub const Allocator = std.mem.Allocator;

pub const Hooks = struct {
	ctx: *anyopaque,
	snapshot: *const fn (ctx: *anyopaque, allocator: Allocator) anyerror![]u8,
	sync: ?*const fn (ctx: *anyopaque, allocator: Allocator) anyerror![]u8 = null,
	dismiss: ?*const fn (ctx: *anyopaque, id: []const u8) void = null,
	refresh: ?*const fn (ctx: *anyopaque) void = null,
	command: ?*const fn (ctx: *anyopaque, value: json.Value) void = null,
};

pub const Client = struct {
	fd: i32,
	connection: *sock.Connection,
	write_mutex: std.Io.Mutex = .init,
	alive: bool = true,
	gaze: bool = false,
	rev: u64 = 0,
};

pub const Ipc = struct {
	allocator: Allocator,
	io: Io,
	server: sock.Server,
	hooks: Hooks,
	mutex: std.Io.Mutex = .init,
	clients: std.ArrayList(*Client) = .empty,
	gaze_count: std.atomic.Value(usize) = .init(0),

	pub fn init(allocator: Allocator, io: Io, path: []const u8, hooks: Hooks) !*Ipc {
		const self = try allocator.create(Ipc);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.server = try sock.Server.init(path),
			.hooks = hooks,
		};

		return self;
	}

	pub fn start(self: *Ipc) !void {
		const thread = try std.Thread.spawn(.{}, acceptLoop, .{self});
		thread.detach();
	}

	fn acceptLoop(self: *Ipc) void {
		while (true) {
			const fd = self.server.accept() catch continue;

			const connection = self.allocator.create(sock.Connection) catch {
				_ = std.os.linux.close(fd);
				continue;
			};

			const buffer = self.allocator.alloc(u8, 4096) catch {
				_ = std.os.linux.close(fd);
				continue;
			};
			connection.* = .{ .fd = fd, .buffer = buffer };

			const client = self.allocator.create(Client) catch {
				_ = std.os.linux.close(fd);
				continue;
			};
			client.* = .{ .fd = fd, .connection = connection };

			self.mutex.lockUncancelable(self.io);
			self.clients.append(self.allocator, client) catch {
				self.mutex.unlock(self.io);
				_ = std.os.linux.close(fd);
				continue;
			};
			self.mutex.unlock(self.io);

			const thread = std.Thread.spawn(.{}, readLoop, .{ self, client }) catch continue;
			thread.detach();
		}
	}

	fn readLoop(self: *Ipc, client: *Client) void {
		while (true) {
			const maybe = client.connection.readLine() catch break;
			if (maybe == null) break;

			const message = maybe.?;
			if (message.len == 0) continue;

			self.handle(client, message);
		}

		self.markDead(client);
	}

	fn handle(self: *Ipc, client: *Client, message: []const u8) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const parsed = json.parse(arena.allocator(), message) catch return;
		const root = parsed.value;

		if (json.field(root, "gaze")) |value| {
			const wanted = switch (value) {
				.bool => |flag| flag,
				.integer => |n| n != 0,
				else => false,
			};

			if (wanted != client.gaze) {
				client.gaze = wanted;
				if (wanted) {
					_ = self.gaze_count.fetchAdd(1, .monotonic);
				} else {
					_ = self.gaze_count.fetchSub(1, .monotonic);
				}
			}
		}

		const dismiss = json.textAt(root, "dismiss");
		if (dismiss.len > 0) {
			if (self.hooks.dismiss) |hook| hook(self.hooks.ctx, dismiss);
		}

		if (json.flag(root, "refresh")) {
			if (self.hooks.refresh) |hook| hook(self.hooks.ctx);
		}

		if (json.field(root, "cmd")) |value| {
			if (self.hooks.command) |hook| hook(self.hooks.ctx, value);
		}

		if (json.flag(root, "sync")) {
			const hook = self.hooks.sync orelse self.hooks.snapshot;
			const body = hook(self.hooks.ctx, self.allocator) catch return;
			defer self.allocator.free(body);

			sendLine(self.io, client, body);
		}
	}

	fn markDead(self: *Ipc, client: *Client) void {
		self.mutex.lockUncancelable(self.io);

		client.alive = false;

		var index: usize = 0;
		while (index < self.clients.items.len) : (index += 1) {
			if (self.clients.items[index] != client) continue;

			_ = self.clients.swapRemove(index);
			break;
		}

		self.mutex.unlock(self.io);

		_ = std.os.linux.close(client.fd);
		retire(self.allocator, client, &self.gaze_count);
	}

	pub fn gazeSubscribers(self: *Ipc) usize {
		return self.gaze_count.load(.monotonic);
	}

	pub fn broadcast(self: *Ipc, line: []const u8) void {
		self.sendAll(line, false);
	}

	pub fn broadcastGaze(self: *Ipc, x: f64, y: f64) void {
		var buffer: [128]u8 = undefined;
		const line = std.fmt.bufPrint(&buffer, "{{\"t\":\"gaze\",\"x\":{d:.4},\"y\":{d:.4}}}", .{ x, y }) catch return;

		self.sendAll(line, true);
	}

	fn sendAll(self: *Ipc, line: []const u8, gaze_only: bool) void {
		var targets: [64]*Client = undefined;
		var count: usize = 0;

		self.mutex.lockUncancelable(self.io);

		for (self.clients.items) |client| {
			if (count == targets.len) break;
			if (!client.alive) continue;
			if (gaze_only and !client.gaze) continue;

			targets[count] = client;
			count += 1;
		}

		self.mutex.unlock(self.io);

		for (targets[0..count]) |client| {
			if (!client.alive) continue;

			sendLine(self.io, client, line);
		}
	}
};

fn sendLine(io: Io, client: *Client, line: []const u8) void {
	client.write_mutex.lockUncancelable(io);
	defer client.write_mutex.unlock(io);

	if (bodyRev(line)) |rev| {
		if (rev < client.rev) return;
		client.rev = rev;
	}

	sock.writeAll(client.fd, line) catch {
		drop(client);
		return;
	};

	sock.writeAll(client.fd, "\n") catch drop(client);
}

fn bodyRev(line: []const u8) ?u64 {
	const head = "{\"rev\":";
	if (!std.mem.startsWith(u8, line, head)) return null;

	const rest = line[head.len..];
	const end = std.mem.indexOfScalar(u8, rest, ',') orelse return null;

	return std.fmt.parseInt(u64, rest[0..end], 10) catch null;
}

fn drop(client: *Client) void {
	client.alive = false;
	_ = std.os.linux.shutdown(client.fd, std.os.linux.SHUT.RDWR);
}

fn retire(allocator: Allocator, client: *Client, gaze: *std.atomic.Value(usize)) void {
	if (client.gaze) {
		_ = gaze.fetchSub(1, .monotonic);
		client.gaze = false;
	}

	allocator.free(client.connection.buffer);
	allocator.destroy(client.connection);
	allocator.destroy(client);
}

test "gaze lines stay valid json" {
	var buffer: [128]u8 = undefined;
	const line = try std.fmt.bufPrint(&buffer, "{{\"t\":\"gaze\",\"x\":{d:.4},\"y\":{d:.4}}}", .{ 0.5, -0.25 });

	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const parsed = try json.parse(arena.allocator(), line);
	try std.testing.expectEqualStrings("gaze", json.textAt(parsed.value, "t"));
}

var probe_count: i64 = 0;

fn probeSnapshot(ctx: *anyopaque, allocator: Allocator) anyerror![]u8 {
	_ = ctx;
	return std.fmt.allocPrint(allocator, "{{\"rev\":1,\"bumped\":{d}}}", .{probe_count});
}

fn probeCommand(ctx: *anyopaque, value: json.Value) void {
	_ = ctx;
	probe_count = json.integer(json.field(value, "bump"));
}

test "a fresh connection is answered after the commands it sent" {
	const io = std.testing.io;
	const allocator = std.heap.smp_allocator;

	probe_count = 0;

	const path = try std.fmt.allocPrint(allocator, "/tmp/yudae-ipc-{d}.sock", .{std.os.linux.getpid()});
	defer allocator.free(path);

	const server = try Ipc.init(allocator, io, path, .{
		.ctx = @ptrFromInt(1),
		.snapshot = probeSnapshot,
		.command = probeCommand,
	});
	try server.start();

	var buffer: [4096]u8 = undefined;
	var connection = try sock.Connection.connect(path, &buffer);
	defer connection.close();

	try connection.writeLine("{\"cmd\":{\"bump\":7}}");
	try connection.writeLine(sock.sync);

	const line = (try connection.readLine()) orelse return error.NoReply;
	try std.testing.expectEqualStrings("{\"rev\":1,\"bumped\":7}", line);
}
