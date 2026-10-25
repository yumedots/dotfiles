const std = @import("std");
const linux = std.os.linux;

pub const Io = std.Io;
pub const Allocator = std.mem.Allocator;

pub const Event = struct {
	path: []const u8,
};

pub const Watcher = struct {
	fd: i32,
	buffer: [4096]u8 = undefined,

	pub fn init() !Watcher {
		const fd = linux.inotify_init1(linux.IN.CLOEXEC);
		if (@as(isize, @bitCast(fd)) < 0) return error.WatchInit;
		return .{ .fd = @intCast(fd) };
	}

	pub fn close(self: *Watcher) void {
		_ = linux.close(self.fd);
	}

	pub fn add(self: *Watcher, path: [:0]const u8) !void {
		const mask = linux.IN.CREATE | linux.IN.MODIFY | linux.IN.MOVED_TO | linux.IN.CLOSE_WRITE | linux.IN.DELETE_SELF | linux.IN.MOVE_SELF;
		const result = linux.inotify_add_watch(self.fd, path, mask);
		if (@as(isize, @bitCast(result)) < 0) return error.WatchAdd;
	}

	pub fn next(self: *Watcher) ![]const u8 {
		const count = linux.read(self.fd, &self.buffer, self.buffer.len);
		if (@as(isize, @bitCast(count)) < 0) return error.WatchRead;
		if (count < @sizeOf(linux.inotify_event)) return error.WatchShort;

		const event: *align(1) const linux.inotify_event = @ptrCast(&self.buffer[0]);
		const start = @sizeOf(linux.inotify_event);
		const end = @min(count, start + event.len);
		const name = std.mem.sliceTo(self.buffer[start..end], 0);

		return name;
	}
};

pub fn dirOf(path: []const u8) []const u8 {
	return std.fs.path.dirname(path) orelse ".";
}

pub fn baseOf(path: []const u8) []const u8 {
	return std.fs.path.basename(path);
}

pub fn watchFile(io: Io, allocator: Allocator, path: []const u8, ctx: *anyopaque, callback: *const fn (*anyopaque) void) !void {
	const wanted = try allocator.dupe(u8, baseOf(path));
	defer allocator.free(wanted);

	var watcher = try Watcher.init();
	defer watcher.close();

	const dir_path = dirOf(path);
	const dir = try allocator.allocSentinel(u8, dir_path.len, 0);
	@memcpy(dir, dir_path);
	defer allocator.free(dir);

	try watcher.add(dir);

	while (true) {
		const name = try watcher.next();

		if (name.len > 0 and !std.mem.eql(u8, name, wanted)) continue;

		try io.sleep(std.Io.Duration.fromMilliseconds(120), .awake);
		callback(ctx);
	}
}

test "watch helpers split a path" {
	try std.testing.expectEqualStrings("/a/b", dirOf("/a/b/c"));
	try std.testing.expectEqualStrings("c", baseOf("/a/b/c"));
}
