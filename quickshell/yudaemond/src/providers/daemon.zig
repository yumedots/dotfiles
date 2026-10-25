const std = @import("std");
const hubmod = @import("../hub.zig");
const proc = @import("../primitives/proc.zig");
const fmt = @import("../primitives/fmt.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;

const Out = struct {
	pid: i32,
	bootMs: i64,
	listenMs: i64,
	rssKb: i64,
	threads: i64,
};

pub const Daemon = struct {
	allocator: Allocator,
	io: Io,
	hub: *hubmod.Hub,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	started: i64,
	listening: i64 = 0,
	last_rss: i64 = 0,
	last_threads: i64 = 0,

	pub fn create(allocator: Allocator, io: Io, hub: *hubmod.Hub) !*Daemon {
		const self = try allocator.create(Daemon);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.scratch = std.heap.ArenaAllocator.init(allocator),
			.started = fmt.nowMs(io),
		};

		return self;
	}

	pub fn provider(self: *Daemon) hubmod.Provider {
		return .{ .key = "daemon", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Daemon = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn markListening(self: *Daemon) void {
		self.listening = fmt.nowMs(self.io);
		self.sample();
	}

	fn sample(self: *Daemon) void {
		const pid: i32 = @intCast(std.os.linux.getpid());

		self.mutex.lockUncancelable(self.io);
		self.last_rss = proc.rssKb(self.io, self.allocator, pid);
		self.last_threads = readThreads(self.io, self.allocator, pid);
		self.mutex.unlock(self.io);
	}

	fn render(self: *Daemon, writer: *Writer) !void {
		self.sample();

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);

		const out = Out{
			.pid = @intCast(std.os.linux.getpid()),
			.bootMs = self.started,
			.listenMs = self.listening - self.started,
			.rssKb = self.last_rss,
			.threads = self.last_threads,
		};

		try writer.print("{f}", .{std.json.fmt(out, .{})});
	}
};

fn readThreads(io: Io, allocator: Allocator, pid: i32) i64 {
	const path = std.fmt.allocPrint(allocator, "/proc/{d}/status", .{pid}) catch return 0;
	defer allocator.free(path);

	const body = proc.readFile(io, allocator, path) catch return 0;
	defer allocator.free(body);

	var lines = std.mem.splitScalar(u8, body, '\n');
	while (lines.next()) |line| {
		if (!std.mem.startsWith(u8, line, "Threads:")) continue;
		const value = std.mem.trim(u8, line["Threads:".len..], " \t");
		return std.fmt.parseInt(i64, value, 10) catch 0;
	}

	return 0;
}
