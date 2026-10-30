const std = @import("std");

pub const Allocator = std.mem.Allocator;
pub const Io = std.Io;

pub const max_file = 4 * 1024 * 1024;

pub fn readFile(io: Io, allocator: Allocator, path: []const u8) ![]u8 {
	var file = try std.Io.Dir.cwd().openFile(io, path, .{});
	defer file.close(io);

	var buffer: [8192]u8 = undefined;
	var reader = file.reader(io, &buffer);

	var list: std.ArrayList(u8) = .empty;
	errdefer list.deinit(allocator);

	var chunk: [8192]u8 = undefined;
	while (true) {
		const count = try reader.interface.readSliceShort(&chunk);

		if (count == 0) break;
		if (list.items.len + count > max_file) return error.StreamTooLong;

		try list.appendSlice(allocator, chunk[0..count]);
	}

	return list.toOwnedSlice(allocator);
}

pub fn readFileOr(io: Io, allocator: Allocator, path: []const u8) []u8 {
	return readFile(io, allocator, path) catch "";
}

pub fn exists(io: Io, path: []const u8) bool {
	_ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
	return true;
}

pub fn envFrom(block: []const u8, key: []const u8) ?[]const u8 {
	var it = std.mem.splitScalar(u8, block, 0);

	while (it.next()) |entry| {
		if (entry.len <= key.len) continue;
		if (!std.mem.startsWith(u8, entry, key)) continue;
		if (entry[key.len] != '=') continue;

		return entry[key.len + 1 ..];
	}

	return null;
}

var environ_block: ?[]const u8 = null;
var environ_lock: std.Io.Mutex = .init;

pub fn environ(io: Io, allocator: Allocator) ?[]const u8 {
	environ_lock.lockUncancelable(io);
	defer environ_lock.unlock(io);

	if (environ_block == null) environ_block = readFile(io, allocator, "/proc/self/environ") catch null;

	return environ_block;
}

pub fn env(io: Io, allocator: Allocator, key: []const u8) ?[]const u8 {
	const block = environ(io, allocator) orelse return null;
	return envFrom(block, key);
}

pub fn envOr(io: Io, allocator: Allocator, key: []const u8, fallback: []const u8) []const u8 {
	return env(io, allocator, key) orelse fallback;
}

pub fn args(io: Io, allocator: Allocator) ![][]const u8 {
	const block = try readFile(io, allocator, "/proc/self/cmdline");
	var out: std.ArrayList([]const u8) = .empty;
	var it = std.mem.splitScalar(u8, block, 0);

	while (it.next()) |entry| {
		if (entry.len == 0) break;
		try out.append(allocator, entry);
	}

	return out.toOwnedSlice(allocator);
}

pub fn home(io: Io, allocator: Allocator) []const u8 {
	return envOr(io, allocator, "HOME", "/home");
}

pub fn runtimeDir(io: Io, allocator: Allocator) []const u8 {
	return env(io, allocator, "XDG_RUNTIME_DIR") orelse "/tmp";
}

pub fn socketPath(io: Io, allocator: Allocator) ![]u8 {
	return std.fmt.allocPrint(allocator, "{s}/yudaemond.sock", .{runtimeDir(io, allocator)});
}

pub fn stateHome(io: Io, allocator: Allocator) []const u8 {
	if (env(io, allocator, "XDG_STATE_HOME")) |dir| return dir;
	return std.fmt.allocPrint(allocator, "{s}/.local/state", .{home(io, allocator)}) catch "/tmp";
}

pub fn writeFile(io: Io, path: []const u8, body: []const u8) !void {
	try std.Io.Dir.cwd().createDirPath(io, std.fs.path.dirname(path) orelse ".");

	var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
	file.writeStreamingAll(io, body) catch {};
	file.close(io);
}

pub fn writeFileAtomic(io: Io, allocator: Allocator, path: []const u8, body: []const u8) !void {
	const temp = try std.fmt.allocPrint(allocator, "{s}.tmp", .{path});

	var file = try std.Io.Dir.cwd().createFile(io, temp, .{ .truncate = true });
	var buffer: [4096]u8 = undefined;
	var writer = file.writer(io, &buffer);
	try writer.interface.writeAll(body);
	try writer.interface.flush();
	file.close(io);

	try std.Io.Dir.cwd().rename(temp, std.Io.Dir.cwd(), path, io);
}

test "a file write makes the folders it needs" {
	const io = std.testing.io;

	var tmp = std.testing.tmpDir(.{});
	defer tmp.cleanup();

	const path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/a/b/name.txt", .{tmp.sub_path});
	defer std.testing.allocator.free(path);

	try writeFile(io, path, "hello\n");

	const body = try readFile(io, std.testing.allocator, path);
	defer std.testing.allocator.free(body);

	try std.testing.expectEqualStrings("hello\n", body);
}

test "env reads a known variable" {
	const block = "HOME=/home/a\x00PATH=/usr/bin\x00EMPTY=\x00";

	try std.testing.expectEqualStrings("/home/a", envFrom(block, "HOME").?);
	try std.testing.expectEqualStrings("/usr/bin", envFrom(block, "PATH").?);
	try std.testing.expectEqualStrings("", envFrom(block, "EMPTY").?);
	try std.testing.expect(envFrom(block, "HOM") == null);
	try std.testing.expect(envFrom(block, "HOMEX") == null);
}

pub const ProcessInfo = struct {
	pid: i32,
	comm: [16]u8 = undefined,
	comm_len: usize = 0,
	rss_kb: i64,
	ticks: i64,

	pub fn name(self: *const ProcessInfo) []const u8 {
		return self.comm[0..self.comm_len];
	}
};

pub fn readProcess(io: Io, allocator: Allocator, pid: i32) ?ProcessInfo {
	const stat_path = std.fmt.allocPrint(allocator, "/proc/{d}/stat", .{pid}) catch return null;
	defer allocator.free(stat_path);

	const stat = readFile(io, allocator, stat_path) catch return null;
	defer allocator.free(stat);

	const close = std.mem.lastIndexOfScalar(u8, stat, ')') orelse return null;
	const name_start = std.mem.indexOfScalar(u8, stat, '(') orelse return null;
	const comm = stat[name_start + 1 .. close];

	var name_out: [16]u8 = @splat(0);
	const name_len = @min(comm.len, name_out.len);

	for (0..name_len) |i| name_out[i] = comm[i];

	const ticks = parseTicks(stat);

	const statm_path = std.fmt.allocPrint(allocator, "/proc/{d}/statm", .{pid}) catch return null;
	defer allocator.free(statm_path);

	const statm = readFile(io, allocator, statm_path) catch return null;
	defer allocator.free(statm);

	var sizes = std.mem.tokenizeAny(u8, statm, " \n");
	_ = sizes.next();
	const resident = std.fmt.parseInt(i64, sizes.next() orelse "0", 10) catch 0;

	return .{
		.pid = pid,
		.comm = name_out,
		.comm_len = name_len,
		.rss_kb = resident * 4,
		.ticks = ticks,
	};
}

pub fn listProcesses(io: Io, allocator: Allocator) ![]ProcessInfo {
	var dir = std.Io.Dir.cwd().openDir(io, "/proc", .{ .iterate = true }) catch return &.{};
	defer dir.close(io);

	var out: std.ArrayList(ProcessInfo) = .empty;
	var it = dir.iterate();

	while (try it.next(io)) |entry| {
		const pid = std.fmt.parseInt(i32, entry.name, 10) catch continue;
		if (readProcess(io, allocator, pid)) |info| try out.append(allocator, info);
	}

	return out.toOwnedSlice(allocator);
}

pub fn threadTicks(io: Io, allocator: Allocator, pid: i32) i64 {
	const path = std.fmt.allocPrint(allocator, "/proc/{d}/task", .{pid}) catch return 0;
	defer allocator.free(path);

	var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return 0;
	defer dir.close(io);

	var total: i64 = 0;
	var it = dir.iterate();

	while (it.next(io) catch null) |entry| {
		_ = std.fmt.parseInt(i32, entry.name, 10) catch continue;

		const stat_path = std.fmt.allocPrint(allocator, "/proc/{d}/task/{s}/stat", .{ pid, entry.name }) catch continue;
		defer allocator.free(stat_path);

		const stat = readFile(io, allocator, stat_path) catch continue;
		defer allocator.free(stat);

		total += parseTicks(stat);
	}

	return total;
}

pub fn parseTicks(stat: []const u8) i64 {
	const close = std.mem.lastIndexOfScalar(u8, stat, ')') orelse return 0;

	var fields = std.mem.tokenizeAny(u8, stat[close + 1 ..], " ");
	var index: usize = 0;
	var ticks: i64 = 0;

	while (fields.next()) |field| : (index += 1) {
		if (index == 11 or index == 12) ticks += std.fmt.parseInt(i64, field, 10) catch 0;
	}

	return ticks;
}

pub fn running(io: Io, allocator: Allocator, pid: i32) bool {
	if (pid <= 0) return false;
	const path = std.fmt.allocPrint(allocator, "/proc/{d}/stat", .{pid}) catch return false;
	defer allocator.free(path);

	return exists(io, path);
}

pub fn rssKb(io: Io, allocator: Allocator, pid: i32) i64 {
	const info = readProcess(io, allocator, pid) orelse return 0;
	return info.rss_kb;
}

test "process info reads this process" {
	var threaded: std.Io.Threaded = .init(std.testing.allocator, .{});
	const io = threaded.io();

	var info = (readProcess(io, std.testing.allocator, @intCast(std.os.linux.getpid())) orelse return error.NoProcess);
	try std.testing.expect(info.rss_kb > 0);
	try std.testing.expect(info.name().len > 0);
}
