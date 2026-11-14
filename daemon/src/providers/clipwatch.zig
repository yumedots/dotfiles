const std = @import("std");
const proc = @import("../primitives/proc.zig");
const hypr = @import("../primitives/hypr.zig");
const json = @import("../primitives/json.zig");
const exec = @import("../primitives/exec.zig");
const sleep = @import("../primitives/sleep.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const keep_lines = 400;
const self_window_s = 5;

pub const Watch = struct {
	allocator: Allocator,
	io: Io,
	ctx: *anyopaque,
	changed: *const fn (*anyopaque) void,
	self_at: std.atomic.Value(i64) = .init(0),

	pub fn create(allocator: Allocator, io: Io, ctx: *anyopaque, changed: *const fn (*anyopaque) void) !*Watch {
		const self = try allocator.create(Watch);
		self.* = .{ .allocator = allocator, .io = io, .ctx = ctx, .changed = changed };
		return self;
	}

	pub fn start(self: *Watch) !void {
		const thread = try std.Thread.spawn(.{}, run, .{self});
		thread.detach();
	}

	pub fn markSelf(self: *Watch) void {
		self.self_at.store(self.now(), .monotonic);
	}

	fn now(self: *Watch) i64 {
		return @divFloor(std.Io.Clock.real.now(self.io).toMilliseconds(), 1000);
	}

	fn run(self: *Watch) void {
		while (true) {
			self.follow();
			sleep.ms(5000);
		}
	}

	fn pidPath(self: *Watch, allocator: Allocator) ![]u8 {
		return std.fmt.allocPrint(allocator, "{s}/yudaemond-clipwatch.pid", .{proc.runtimeDir(self.io, self.allocator)});
	}

	fn reap(self: *Watch) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();
		const path = self.pidPath(allocator) catch return;
		const pid = std.fmt.parseInt(std.posix.pid_t, std.mem.trim(u8, proc.readFileOr(self.io, allocator, path), " \n"), 10) catch return;

		const comm_path = std.fmt.allocPrint(allocator, "/proc/{d}/comm", .{pid}) catch return;
		const comm = std.mem.trim(u8, proc.readFileOr(self.io, allocator, comm_path), " \n");

		if (std.mem.eql(u8, comm, "wl-paste")) _ = std.posix.kill(pid, std.posix.SIG.KILL) catch {};
	}

	fn follow(self: *Watch) void {
		self.reap();

		const child = exec.spawn(self.io, .{
			.argv = &.{ "wl-paste", "--watch", "sh", "-c", "cliphist store && echo" },
			.stdin = .ignore,
			.stdout = .pipe,
			.stderr = .ignore,
		}) catch return;

		defer if (child.id) |id| {
			_ = std.posix.kill(id, std.posix.SIG.KILL) catch {};
		};

		if (child.id) |id| {
			var arena = std.heap.ArenaAllocator.init(self.allocator);
			defer arena.deinit();

			const path = self.pidPath(arena.allocator()) catch "";
			const text = std.fmt.allocPrint(arena.allocator(), "{d}\n", .{id}) catch "";
			if (path.len > 0) proc.writeFileAtomic(self.io, arena.allocator(), path, text) catch {};
		}

		const fd = child.stdout.?.handle;
		var chunk: [256]u8 = undefined;
		var replay = true;

		while (true) {
			const count = std.posix.read(fd, &chunk) catch break;
			if (count == 0) break;

			for (chunk[0..count]) |byte| {
				if (byte != '\n') continue;

				self.record(replay);
				replay = false;
			}
		}
	}

	fn statePath(self: *Watch, allocator: Allocator, name: []const u8) ![]u8 {
		return std.fmt.allocPrint(allocator, "{s}/dotfiles/shell/cache/launcher/{s}", .{ proc.home(self.io, self.allocator), name });
	}

	fn record(self: *Watch, replay: bool) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();

		const top = exec.run(self.io, allocator, &.{ "sh", "-c", "cliphist list 2>/dev/null | head -n 1" }) catch return;
		const at = std.mem.indexOfScalar(u8, top.out, '\t') orelse return;
		const id = std.mem.trim(u8, top.out[0..at], " \t\r");
		if (id.len == 0) return;

		const times_path = self.statePath(allocator, "clip-times.txt") catch return;
		const times = proc.readFileOr(self.io, allocator, times_path);

		if (replay and valueOf(times, id).len > 0) return;

		const stamp = self.now();
		const stamp_text = std.fmt.allocPrint(allocator, "{d}", .{stamp}) catch return;

		self.store(allocator, times_path, times, id, stamp_text);

		if (stamp - self.self_at.load(.monotonic) >= self_window_s) {
			const class = self.activeClass(allocator);

			if (class.len > 0) {
				const apps_path = self.statePath(allocator, "clip-apps.txt") catch return;
				self.store(allocator, apps_path, proc.readFileOr(self.io, allocator, apps_path), id, class);
			}
		}

		self.changed(self.ctx);
	}

	fn store(self: *Watch, allocator: Allocator, path: []const u8, body: []const u8, id: []const u8, value: []const u8) void {
		const next = merge(allocator, body, id, value) catch return;
		proc.writeFileAtomic(self.io, allocator, path, next) catch {};
	}

	fn activeClass(self: *Watch, allocator: Allocator) []const u8 {
		const body = hypr.request(self.io, allocator, "j/activewindow") catch return "";
		const parsed = json.parse(allocator, body) catch return "";

		return json.textAt(parsed.value, "class");
	}
};

pub fn valueOf(body: []const u8, id: []const u8) []const u8 {
	var lines = std.mem.splitScalar(u8, body, '\n');

	while (lines.next()) |line| {
		const at = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
		if (!std.mem.eql(u8, line[0..at], id)) continue;

		return std.mem.trim(u8, line[at + 1 ..], " \t\r");
	}

	return "";
}

pub fn merge(allocator: Allocator, body: []const u8, id: []const u8, value: []const u8) ![]u8 {
	var kept: std.ArrayListUnmanaged([]const u8) = .empty;
	defer kept.deinit(allocator);

	var lines = std.mem.splitScalar(u8, body, '\n');

	while (lines.next()) |line| {
		const at = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
		if (std.mem.eql(u8, line[0..at], id)) continue;

		try kept.append(allocator, line);
	}

	const from = if (kept.items.len + 1 > keep_lines) kept.items.len + 1 - keep_lines else 0;

	var out: std.ArrayListUnmanaged(u8) = .empty;
	errdefer out.deinit(allocator);

	for (kept.items[from..]) |line| {
		try out.appendSlice(allocator, line);
		try out.append(allocator, '\n');
	}

	try out.print(allocator, "{s} {s}\n", .{ id, value });

	return out.toOwnedSlice(allocator);
}

test "merge moves an id to the end and caps the file" {
	const allocator = std.testing.allocator;

	const first = try merge(allocator, "1 a\n2 b\n", "1", "z");
	defer allocator.free(first);
	try std.testing.expectEqualStrings("2 b\n1 z\n", first);
	try std.testing.expectEqualStrings("z", valueOf(first, "1"));
	try std.testing.expectEqualStrings("", valueOf(first, "3"));

	var body: []u8 = try allocator.dupe(u8, "");
	for (0..keep_lines + 5) |index| {
		const id = try std.fmt.allocPrint(allocator, "{d}", .{index});
		defer allocator.free(id);

		const next = try merge(allocator, body, id, "x");
		allocator.free(body);
		body = next;
	}
	defer allocator.free(body);

	try std.testing.expectEqual(@as(usize, keep_lines), std.mem.count(u8, body, "\n"));
	try std.testing.expectEqualStrings("", valueOf(body, "0"));
	try std.testing.expectEqualStrings("x", valueOf(body, "404"));
}
