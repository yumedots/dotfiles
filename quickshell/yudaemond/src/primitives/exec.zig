const std = @import("std");

pub const Io = std.Io;
pub const Allocator = std.mem.Allocator;

pub const Result = struct {
	code: u8,
	out: []u8,

	pub fn deinit(self: Result, allocator: Allocator) void {
		allocator.free(self.out);
	}
};

pub fn run(io: Io, allocator: Allocator, argv: []const []const u8) !Result {
	var child = try std.process.spawn(io, .{
		.argv = argv,
		.stdin = .ignore,
		.stdout = .pipe,
		.stderr = .ignore,
	});

	var buffer: [8192]u8 = undefined;
	var reader = child.stdout.?.reader(io, &buffer);

	var out: std.ArrayList(u8) = .empty;
	errdefer out.deinit(allocator);

	var chunk: [8192]u8 = undefined;
	while (true) {
		const count = try reader.interface.readSliceShort(&chunk);
		if (count == 0) break;
		if (out.items.len + count > 4 * 1024 * 1024) break;
		try out.appendSlice(allocator, chunk[0..count]);
	}

	const term = child.wait(io) catch {
		return .{ .code = 1, .out = try out.toOwnedSlice(allocator) };
	};

	const code: u8 = switch (term) {
		.exited => |status| status,
		else => 1,
	};

	return .{ .code = code, .out = try out.toOwnedSlice(allocator) };
}

pub fn selfPath(io: Io, allocator: Allocator) ![]u8 {
	const proc = @import("proc.zig");
	const raw = try proc.readFile(io, allocator, "/proc/self/exe");

	return raw;
}
