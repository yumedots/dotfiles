const std = @import("std");
const linux = std.os.linux;
const proc = @import("../../primitives/proc.zig");

pub const Allocator = std.mem.Allocator;
pub const Io = std.Io;

pub const protected_paths = [_][]const u8{
	"/proc",     "/sys",              "/dev",              "/run",
	"/usr",      "/etc",              "/boot",             "/efi",
	"/bin",      "/sbin",             "/lib",              "/lib32",
	"/lib64",    "/var/lib/pacman",   "/var/lib/systemd",
};

pub const resolve_no_symlinks: u64 = 0x04;
pub const resolve_no_xdev: u64 = 0x08;

pub const OpenHow = extern struct {
	flags: u64,
	mode: u64,
	resolve: u64,
};

pub fn openat2(dirfd: i32, path: []const u8, flags: u32, mode: u32, resolve: u64) !i32 {
	const z = try std.heap.smp_allocator.allocSentinel(u8, path.len, 0);
	defer std.heap.smp_allocator.free(z);
	@memcpy(z, path);

	var how: OpenHow = .{ .flags = flags, .mode = mode, .resolve = resolve };
	const result = linux.syscall4(.openat2, @as(u32, @bitCast(dirfd)), @intFromPtr(z.ptr), @intFromPtr(&how), @sizeOf(OpenHow));

	if (linux.errno(result) != .SUCCESS) return error.OpenDenied;
	return @intCast(result);
}

pub fn clean(path: []const u8, buffer: []u8) ![]const u8 {
	if (path.len == 0 or path[0] != '/') return error.NotAbsolute;

	var out: usize = 0;
	var parts = std.mem.tokenizeScalar(u8, path, '/');

	while (parts.next()) |part| {
		if (std.mem.eql(u8, part, ".")) continue;
		if (std.mem.eql(u8, part, "..")) return error.Escape;

		if (out + part.len + 1 > buffer.len) return error.NameTooLong;
		buffer[out] = '/';
		out += 1;
		@memcpy(buffer[out .. out + part.len], part);
		out += part.len;
	}

	if (out == 0) return "/";
	return buffer[0..out];
}

pub fn hasPrefix(path: []const u8, prefix: []const u8) bool {
	if (std.mem.eql(u8, path, prefix)) return true;
	if (path.len <= prefix.len) return false;
	if (!std.mem.startsWith(u8, path, prefix)) return false;
	return path[prefix.len] == '/';
}

pub const Guard = struct {
	mounts: [][]u8 = &.{},
	extra: []const []const u8 = &.{},

	pub fn init(allocator: Allocator, io: Io, extra: []const []const u8) !Guard {
		return .{ .mounts = try mountPoints(allocator, io), .extra = extra };
	}

	pub fn deinit(self: *Guard, allocator: Allocator) void {
		for (self.mounts) |mount| allocator.free(mount);
		allocator.free(self.mounts);
	}

	pub fn isProtected(self: *const Guard, path: []const u8, root: []const u8) bool {
		for (protected_paths) |entry| if (hasPrefix(path, entry)) return true;
		for (self.extra) |entry| if (hasPrefix(path, entry)) return true;

		for (self.mounts) |mount| {
			if (std.mem.eql(u8, mount, root)) continue;
			if (!std.mem.eql(u8, root, "/") and !hasPrefix(mount, root)) continue;
			if (hasPrefix(path, mount)) return true;
		}

		return false;
	}

	pub fn isMount(self: *const Guard, path: []const u8, root: []const u8) bool {
		for (self.mounts) |mount| {
			if (std.mem.eql(u8, mount, root)) continue;
			if (std.mem.eql(u8, mount, path)) return true;
		}

		return false;
	}

	pub fn isRemoveProtected(self: *const Guard, path: []const u8) bool {
		for (protected_paths) |entry| if (hasPrefix(path, entry)) return true;
		for (self.extra) |entry| if (hasPrefix(path, entry)) return true;
		return false;
	}

	pub fn mountRoot(self: *const Guard, path: []const u8) []const u8 {
		var best: []const u8 = "/";
		for (self.mounts) |mount| {
			if (!hasPrefix(path, mount)) continue;
			if (mount.len > best.len) best = mount;
		}
		return best;
	}
};

pub fn mountPoints(allocator: Allocator, io: Io) ![][]u8 {
	const body = try proc.readFile(io, allocator, "/proc/self/mountinfo");
	defer allocator.free(body);

	var out: std.ArrayList([]u8) = .empty;
	errdefer {
		for (out.items) |entry| allocator.free(entry);
		out.deinit(allocator);
	}

	var lines = std.mem.splitScalar(u8, body, '\n');

	while (lines.next()) |line| {
		if (line.len == 0) continue;

		var fields = std.mem.tokenizeAny(u8, line, " \t");
		var index: usize = 0;
		var raw: []const u8 = "";

		while (fields.next()) |field| : (index += 1) {
			if (index == 4) {
				raw = field;
				break;
			}
		}

		if (raw.len == 0) continue;
		try out.append(allocator, try unescape(allocator, raw));
	}

	return out.toOwnedSlice(allocator);
}

fn unescape(allocator: Allocator, raw: []const u8) ![]u8 {
	var out: std.ArrayList(u8) = .empty;
	errdefer out.deinit(allocator);

	var index: usize = 0;
	while (index < raw.len) {
		if (raw[index] == '\\' and index + 3 < raw.len) {
			const value = std.fmt.parseInt(u8, raw[index + 1 .. index + 4], 8) catch {
				try out.append(allocator, raw[index]);
				index += 1;
				continue;
			};
			try out.append(allocator, value);
			index += 4;
			continue;
		}

		try out.append(allocator, raw[index]);
		index += 1;
	}

	return out.toOwnedSlice(allocator);
}

pub fn fsdSocket() []const u8 {
	if (std.c.getenv("YUDAE_FSD_SOCKET")) |value| {
		const text = std.mem.span(value);
		if (text.len > 0) return text;
	}
	return "/run/yudae/fsd.sock";
}

pub fn openRoot(path: []const u8) !i32 {
	const flags: u32 = @bitCast(std.posix.O{ .ACCMODE = .RDONLY, .DIRECTORY = true, .CLOEXEC = true });
	return openat2(linux.AT.FDCWD, path, flags, 0, resolve_no_symlinks);
}

pub fn openChild(dirfd: i32, name: []const u8, directory: bool) !i32 {
	var flags: std.posix.O = .{ .ACCMODE = .RDONLY, .CLOEXEC = true, .NOFOLLOW = true };
	if (directory) flags.DIRECTORY = true;

	return openat2(dirfd, name, @bitCast(flags), 0, resolve_no_symlinks | resolve_no_xdev);
}

pub fn removeTree(path: []const u8, guard: *const Guard, root: []const u8) !void {
	_ = root;
	var clean_buffer: [4096]u8 = undefined;
	const target = try clean(path, &clean_buffer);
	if (std.mem.eql(u8, target, "/")) return error.Protected;
	if (guard.isRemoveProtected(target)) return error.Protected;
	if (guard.isMount(target, "/")) return error.Protected;

	const parent_path = std.fs.path.dirname(target) orelse "/";
	const name = std.fs.path.basename(target);
	if (name.len == 0) return error.Protected;

	const parent_fd = openRoot(parent_path) catch return error.Denied;
	defer _ = linux.close(parent_fd);

	return removeEntry(parent_fd, name);
}

fn removeEntry(parent_fd: i32, name: []const u8) !void {
	const z = try std.heap.smp_allocator.allocSentinel(u8, name.len, 0);
	defer std.heap.smp_allocator.free(z);
	@memcpy(z, name);

	var st: linux.Statx = undefined;
	const checked = linux.statx(parent_fd, z.ptr, linux.AT.SYMLINK_NOFOLLOW, linux.STATX.BASIC_STATS, &st);
	if (linux.errno(checked) != .SUCCESS) return error.Denied;

	if (std.posix.S.ISDIR(st.mode)) {
		const fd = openChild(parent_fd, name, true) catch return error.Denied;
		defer _ = linux.close(fd);

		// ponytail: this walks the directory after unlinking its children; a
		// rename-based swap is foiled by the fd, a concurrent writer is not.
		var buffer: [8192]u8 = undefined;
		while (true) {
			const count = linux.getdents64(fd, &buffer, buffer.len);
			if (linux.errno(count) != .SUCCESS) return error.ReadFailed;
			if (count == 0) break;

			var offset: usize = 0;
			while (offset < count) {
				const entry: *align(1) linux.dirent64 = @ptrCast(&buffer[offset]);
				if (entry.reclen == 0) break;

				const child = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&entry.name)), 0);
				if (!std.mem.eql(u8, child, ".") and !std.mem.eql(u8, child, "..")) {
					try removeEntry(fd, child);
				}

				offset += entry.reclen;
			}
		}

		const removed = linux.unlinkat(parent_fd, z.ptr, linux.AT.REMOVEDIR);
		if (linux.errno(removed) != .SUCCESS) return error.RemoveFailed;
		return;
	}

	const result = linux.unlinkat(parent_fd, z.ptr, 0);
	if (linux.errno(result) != .SUCCESS) return error.RemoveFailed;
}

test "clean refuses escapes and keeps a canonical path" {
	var buffer: [128]u8 = undefined;

	try std.testing.expectEqualStrings("/home/a", try clean("/home//a/", &buffer));
	try std.testing.expectEqualStrings("/", try clean("///", &buffer));
	try std.testing.expectError(error.Escape, clean("/home/../etc", &buffer));
	try std.testing.expectError(error.NotAbsolute, clean("home/a", &buffer));
}

test "protected prefixes respect path boundaries" {
	try std.testing.expect(hasPrefix("/usr/bin", "/usr"));
	try std.testing.expect(hasPrefix("/usr", "/usr"));
	try std.testing.expect(!hasPrefix("/usage", "/usr"));
	try std.testing.expect(!hasPrefix("/home/usr", "/usr"));
}

test "mountinfo escapes decode" {
	const path = try unescape(std.testing.allocator, "/run/media/a\\040b");
	defer std.testing.allocator.free(path);
	try std.testing.expectEqualStrings("/run/media/a b", path);
}

test "mount root chooses the deepest mount" {
	var guard = try Guard.init(std.testing.allocator, std.testing.io, &.{});
	defer guard.deinit(std.testing.allocator);

	try std.testing.expect(guard.mounts.len > 0);
	try std.testing.expect(guard.isProtected("/usr/bin", "/"));
	try std.testing.expect(guard.isProtected("/etc/passwd", "/"));
	try std.testing.expect(guard.isMount("/home", "/"));
	try std.testing.expect(!guard.isMount("/home/gabriel", "/"));
	try std.testing.expect(!guard.isProtected("/home/gabriel", "/home/gabriel/x"));
	try std.testing.expectEqualStrings("/home", guard.mountRoot("/home/gabriel/x"));
	try std.testing.expectEqualStrings("/", guard.mountRoot("/usr/bin"));
}

test "protected paths and symlink escapes refuse removal" {
	const io = std.testing.io;
	var tmp = std.testing.tmpDir(.{});
	defer tmp.cleanup();

	const relative = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
	defer std.testing.allocator.free(relative);
	const base = try std.Io.Dir.cwd().realPathFileAlloc(io, relative, std.testing.allocator);
	defer std.testing.allocator.free(base);

	const root = try std.fmt.allocPrint(std.testing.allocator, "{s}/root", .{base});
	defer std.testing.allocator.free(root);
	const secret = try std.fmt.allocPrint(std.testing.allocator, "{s}/secret", .{root});
	defer std.testing.allocator.free(secret);
	const secret_file = try std.fmt.allocPrint(std.testing.allocator, "{s}/keep.txt", .{secret});
	defer std.testing.allocator.free(secret_file);
	const outside = try std.fmt.allocPrint(std.testing.allocator, "{s}/outside", .{base});
	defer std.testing.allocator.free(outside);
	const outside_file = try std.fmt.allocPrint(std.testing.allocator, "{s}/keep.txt", .{outside});
	defer std.testing.allocator.free(outside_file);

	try std.Io.Dir.cwd().createDirPath(io, secret);
	try std.Io.Dir.cwd().createDirPath(io, outside);
	for ([_][]const u8{ secret_file, outside_file }) |path| {
		var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
		file.writeStreamingAll(io, "keep\n") catch {};
		file.close(io);
	}

	const link = try std.fmt.allocPrint(std.testing.allocator, "{s}/link", .{root});
	defer std.testing.allocator.free(link);
	const escape = try std.fmt.allocPrint(std.testing.allocator, "{s}/keep.txt", .{link});
	defer std.testing.allocator.free(escape);
	try std.Io.Dir.cwd().symLink(io, outside, link, .{});

	var extra = [_][]const u8{secret};
	var guard = try Guard.init(std.testing.allocator, io, &extra);
	defer guard.deinit(std.testing.allocator);

	try std.testing.expectError(error.Protected, removeTree(secret, &guard, root));
	try std.testing.expectError(error.Denied, removeTree(escape, &guard, root));
	try std.testing.expect(testExists(io, secret_file));
	try std.testing.expect(testExists(io, outside_file));

	try removeTree(link, &guard, root);
	try std.testing.expect(testExists(io, outside_file));
}

fn testExists(io: Io, path: []const u8) bool {
	_ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
	return true;
}
