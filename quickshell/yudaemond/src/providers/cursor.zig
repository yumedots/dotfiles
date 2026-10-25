const std = @import("std");
const linux = std.os.linux;
const hubmod = @import("../hub.zig");
const proc = @import("../primitives/proc.zig");
const sock = @import("../primitives/sock.zig");
const sleep = @import("../primitives/sleep.zig");
const fmt = @import("../primitives/fmt.zig");
const json = @import("../primitives/json.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const Out = struct {
	valid: bool,
	x: f64,
	y: f64,
};

pub const Cursor = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	x: f64 = 0,
	y: f64 = 0,
	valid: bool = false,
	ready: bool = false,
	published: bool = false,

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Cursor {
		const self = try allocator.create(Cursor);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.scratch = std.heap.ArenaAllocator.init(allocator),
		};

		return self;
	}

	pub fn provider(self: *Cursor) hubmod.Provider {
		return .{ .key = "cursor", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Cursor = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn start(self: *Cursor) !void {
		const thread = try std.Thread.spawn(.{}, loop, .{self});
		thread.detach();
	}

	fn fifoPath(self: *Cursor) ![]u8 {
		const runtime = proc.runtimeDir(self.io, self.allocator);
		const hypr = try std.fmt.allocPrint(self.allocator, "{s}/hypr", .{runtime});
		defer self.allocator.free(hypr);

		var dir = std.Io.Dir.cwd().openDir(self.io, hypr, .{ .iterate = true }) catch {
			return std.fmt.allocPrint(self.allocator, "{s}/agent-cursor.fifo", .{runtime});
		};
		defer dir.close(self.io);

		var it = dir.iterate();
		var best: ?[]u8 = null;

		while (try it.next(self.io)) |entry| {
			if (entry.kind != .directory) continue;

			const candidate = try std.fmt.allocPrint(self.allocator, "{s}/{s}/agent-cursor.fifo", .{ hypr, entry.name });
			if (!proc.exists(self.io, candidate)) {
				self.allocator.free(candidate);
				continue;
			}

			if (best) |old| self.allocator.free(old);
			best = candidate;
		}

		if (best) |path| return path;

		return std.fmt.allocPrint(self.allocator, "{s}/agent-cursor.fifo", .{runtime});
	}

	fn loop(self: *Cursor) void {
		var last_sent: i64 = 0;

		while (true) {
			const path = self.fifoPath() catch {
				sleep.ms(1000);
				continue;
			};
			defer self.allocator.free(path);

			const terminated = self.allocator.allocSentinel(u8, path.len, 0) catch {
				sleep.ms(1000);
				continue;
			};
			defer self.allocator.free(terminated);
			@memcpy(terminated, path);

			const opened = linux.openat(linux.AT.FDCWD, terminated, .{ .ACCMODE = .RDONLY, .NONBLOCK = true, .CLOEXEC = true }, 0);
			if (sock.failed(opened)) {
				sleep.ms(1000);
				continue;
			}

			const fd: i32 = @intCast(opened);

			var buffer: [256]u8 = undefined;
			var pending: usize = 0;
			var reopen = false;

			while (!reopen) {
				var poll_fds = [_]linux.pollfd{.{ .fd = fd, .events = linux.POLL.IN, .revents = 0 }};
				const ready = linux.poll(&poll_fds, 1, 1000);

				if (sock.failed(ready)) break;
				if (ready == 0) continue;
				if (poll_fds[0].revents & (linux.POLL.HUP | linux.POLL.ERR) != 0) reopen = true;

				const count = linux.read(fd, buffer[pending..].ptr, buffer.len - pending);
				if (sock.failed(count)) {
					reopen = true;
					continue;
				}
				if (count == 0) {
					reopen = true;
					continue;
				}

				pending += count;

				while (std.mem.indexOfScalar(u8, buffer[0..pending], '\n')) |cut| {
					const line = buffer[0..cut];
					const rest = pending - cut - 1;
					std.mem.copyForwards(u8, buffer[0..rest], buffer[cut + 1 .. pending]);
					pending = rest;

					const next = self.parse(line) orelse continue;
					const now = fmt.nowMs(self.io);

					if (now - last_sent < 33) continue;
					if (!self.hub.gazeWanted()) continue;

					last_sent = now;
					self.hub.publishGaze(next[0], next[1]);
				}
			}

			_ = linux.close(fd);
		}
	}

	fn parse(self: *Cursor, line: []const u8) ?[2]f64 {
		var it = std.mem.tokenizeAny(u8, line, " \t\r");
		const first = it.next() orelse return null;
		const second = it.next() orelse return null;

		const x = std.fmt.parseFloat(f64, first) catch return null;
		const y = std.fmt.parseFloat(f64, second) catch return null;

		self.mutex.lockUncancelable(self.io);
		self.x = x;
		self.y = y;
		const changed = !self.valid;
		self.valid = true;
		self.mutex.unlock(self.io);

		if (changed) self.hub.publish();

		return .{ x, y };
	}

	fn render(self: *Cursor, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);

		const out = Out{ .valid = self.valid, .x = self.x, .y = self.y };
		try writer.print("{f}", .{std.json.fmt(out, .{})});
	}
};

test "cursor lines parse two numbers" {
	var cursor: Cursor = .{
		.allocator = std.testing.allocator,
		.io = std.Io.Threaded.global_single_threaded.io(),
		.hub = undefined,
		.valid = true,
		.scratch = std.heap.ArenaAllocator.init(std.testing.allocator),
	};

	const point = cursor.parse("12.5 -3.25");
	try std.testing.expectApproxEqAbs(@as(f64, 12.5), point.?[0], 0.001);
	try std.testing.expectApproxEqAbs(@as(f64, -3.25), point.?[1], 0.001);
	try std.testing.expect(cursor.parse("nonsense") == null);
}
