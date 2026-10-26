const std = @import("std");
const sock = @import("primitives/sock.zig");
const json = @import("primitives/json.zig");

pub const Io = std.Io;
pub const Allocator = std.mem.Allocator;

pub const Hooks = struct {
	ctx: *anyopaque,
	snapshot: *const fn (ctx: *anyopaque, allocator: Allocator) anyerror![]u8,
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

			const body = self.hooks.snapshot(self.hooks.ctx, self.allocator) catch "";
			defer if (body.len > 0) self.allocator.free(body);

			if (body.len > 0) sendLine(self.io, client, body);

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
			const body = self.hooks.snapshot(self.hooks.ctx, self.allocator) catch return;
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
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		for (self.clients.items) |client| {
			if (!client.alive) continue;
			if (gaze_only and !client.gaze) continue;

			sendLine(self.io, client, line);
		}
	}
};

fn sendLine(io: Io, client: *Client, line: []const u8) void {
	client.write_mutex.lockUncancelable(io);
	defer client.write_mutex.unlock(io);

	sock.writeAll(client.fd, line) catch {
		drop(client);
		return;
	};

	sock.writeAll(client.fd, "\n") catch drop(client);
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
