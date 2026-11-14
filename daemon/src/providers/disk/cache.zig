const std = @import("std");
const linux = std.os.linux;
const scanner = @import("scanner.zig");

pub const Allocator = std.mem.Allocator;
pub const Io = std.Io;

pub const magic = "YUDDISK\x00";
pub const version: u32 = 1;
pub const header_size: usize = 4096;

pub const Header = extern struct {
	magic: [8]u8 = magic.*,
	version: u32 = version,
	header_size: u32 = header_size,
	node_count: u64 = 0,
	name_bytes: u64 = 0,
	total: u64 = 0,
	scanned_ms: i64 = 0,
	entries: u64 = 0,
	directories: u64 = 0,
	files: u64 = 0,
};

comptime {
	if (@sizeOf(Header) > header_size) @compileError("cache header does not fit");
}

pub const Cache = struct {
	mapped: []align(std.heap.page_size_min) const u8,
	nodes: []const scanner.Node,
	names: []const u8,
	total: u64,
	scanned_ms: i64,
	entries: u64,
	directories: u64,
	files: u64,

	pub fn deinit(self: *Cache) void {
		std.posix.munmap(self.mapped);
	}

	pub fn nameOf(self: *const Cache, index: u32) []const u8 {
		const node = self.nodes[index];
		return self.names[node.name_off .. node.name_off + node.name_len];
	}

	pub fn root(self: *const Cache) []const u8 {
		if (self.nodes.len == 0) return "/";
		return self.nameOf(0);
	}

	pub fn find(self: *const Cache, path: []const u8) ?u32 {
		if (self.nodes.len == 0) return null;
		if (std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, self.nameOf(0))) return 0;

		var index: u32 = 0;
		var rest = path;
		const base = self.nameOf(0);
		if (std.mem.startsWith(u8, rest, base)) rest = rest[base.len..];

		var parts = std.mem.tokenizeScalar(u8, rest, '/');
		while (parts.next()) |part| {
			var child = self.nodes[index].first_child;
			while (child != scanner.none) : (child = self.nodes[child].next_sibling) {
				if (std.mem.eql(u8, self.nameOf(child), part)) break;
			}
			if (child == scanner.none) return null;
			index = child;
		}

		return index;
	}
};

pub fn write(io: Io, allocator: Allocator, path: []const u8, scan: *const scanner.Scan, scanned_ms: i64) !void {
	const temp = try std.fmt.allocPrint(allocator, "{s}.tmp.{d}", .{ path, linux.getpid() });
	defer allocator.free(temp);

	if (std.fs.path.dirname(path)) |dir| try std.Io.Dir.cwd().createDirPath(io, dir);

	var file = try std.Io.Dir.cwd().createFile(io, temp, .{ .truncate = true, .permissions = @enumFromInt(0o600) });
	errdefer {
		file.close(io);
		std.Io.Dir.cwd().deleteFile(io, temp) catch {};
	}

	var header: Header = .{
		.node_count = scan.nodes.items.len,
		.name_bytes = scan.names.items.len,
		.total = scan.total(),
		.scanned_ms = scanned_ms,
		.entries = scan.stats.entries,
		.directories = scan.stats.directories,
		.files = scan.stats.files,
	};

	var buffer: [64 * 1024]u8 = undefined;
	var writer = file.writer(io, &buffer);
	const w = &writer.interface;

	try w.writeAll(std.mem.asBytes(&header));
	if (header_size > @sizeOf(Header)) {
		const zeros: [header_size]u8 = @splat(0);
		try w.writeAll(zeros[0 .. header_size - @sizeOf(Header)]);
	}
	try w.writeAll(std.mem.sliceAsBytes(scan.nodes.items));
	try w.writeAll(scan.names.items);
	try w.flush();

	try file.sync(io);
	file.close(io);
	try std.Io.Dir.cwd().rename(temp, std.Io.Dir.cwd(), path, io);
}

pub fn load(io: Io, allocator: Allocator, path: []const u8) !Cache {
	_ = allocator;
	var file = try std.Io.Dir.cwd().openFile(io, path, .{});
	defer file.close(io);

	const stat = try file.stat(io);
	if (stat.size < header_size) return error.BadCache;

	const mapped = try std.posix.mmap(null, @intCast(stat.size), .{ .READ = true }, .{ .TYPE = .PRIVATE }, file.handle, 0);
	errdefer std.posix.munmap(mapped);

	const header: *const Header = @alignCast(@ptrCast(mapped.ptr));
	if (!std.mem.eql(u8, &header.magic, magic)) return error.BadCache;
	if (header.version != version or header.header_size != header_size) return error.BadCache;

	const nodes_start = header_size;
	const nodes_len = header.node_count * @sizeOf(scanner.Node);
	const names_start = nodes_start + nodes_len;

	if (names_start + header.name_bytes > mapped.len) return error.BadCache;

	const nodes = @as([*]const scanner.Node, @ptrCast(@alignCast(mapped.ptr + nodes_start)))[0..header.node_count];
	const names = mapped[names_start .. names_start + header.name_bytes];

	return .{
		.mapped = mapped,
		.nodes = nodes,
		.names = names,
		.total = header.total,
		.scanned_ms = header.scanned_ms,
		.entries = header.entries,
		.directories = header.directories,
		.files = header.files,
	};
}

pub fn cachePath(io: Io, allocator: Allocator, cache_home: []const u8) ![]u8 {
	_ = io;
	return std.fmt.allocPrint(allocator, "{s}/yudae/disk.bin", .{cache_home});
}

test "cache round trip keeps the totals and names" {
	const io = std.testing.io;
	var tmp = std.testing.tmpDir(.{});
	defer tmp.cleanup();

	const base = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
	defer std.testing.allocator.free(base);

	const dir = try std.fmt.allocPrint(std.testing.allocator, "{s}/tree", .{base});
	defer std.testing.allocator.free(dir);
	try std.Io.Dir.cwd().createDirPath(io, dir);

	const file_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/data.bin", .{dir});
	defer std.testing.allocator.free(file_path);
	var file = try std.Io.Dir.cwd().createFile(io, file_path, .{});
	try file.writeStreamingAll(io, "0123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789");
	file.close(io);

	var guard = try @import("guard.zig").Guard.init(std.testing.allocator, io, &.{});
	defer guard.deinit(std.testing.allocator);

	var scan = try scanner.Scan.init(std.testing.allocator, &guard, 1);
	defer scan.deinit();
	try scan.run(dir);

	const cache_file = try std.fmt.allocPrint(std.testing.allocator, "{s}/disk.bin", .{base});
	defer std.testing.allocator.free(cache_file);
	try write(io, std.testing.allocator, cache_file, &scan, 1234);

	var cache = try load(io, std.testing.allocator, cache_file);
	defer cache.deinit();

	try std.testing.expectEqual(scan.total(), cache.total);
	try std.testing.expectEqual(@as(i64, 1234), cache.scanned_ms);
	try std.testing.expectEqualStrings(dir, cache.root());
	try std.testing.expect(cache.find(dir) != null);
}
