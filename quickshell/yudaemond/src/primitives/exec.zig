const std = @import("std");

pub const Io = std.Io;
pub const Allocator = std.mem.Allocator;

pub const Result = struct {
	code: u8,
	out: []u8,
	err: []u8,

	pub fn deinit(self: Result, allocator: Allocator) void {
		allocator.free(self.out);
		allocator.free(self.err);
	}
};

pub fn run(io: Io, allocator: Allocator, argv: []const []const u8) !Result {
	return runEnv(io, allocator, argv, null);
}

pub fn runEnv(io: Io, allocator: Allocator, argv: []const []const u8, environ_map: ?*const std.process.Environ.Map) !Result {
	var child = try std.process.spawn(io, .{
		.argv = argv,
		.stdin = .ignore,
		.stdout = .pipe,
		.stderr = .pipe,
		.environ_map = environ_map,
	});

	var multi_buffer: Io.File.MultiReader.Buffer(2) = undefined;
	var multi: Io.File.MultiReader = undefined;
	multi.init(allocator, io, multi_buffer.toStreams(), &.{ child.stdout.?, child.stderr.? });
	defer multi.deinit();

	while (multi.fill(64, .none)) |_| {
		if (multi.reader(0).buffered().len > 4 * 1024 * 1024) break;
		if (multi.reader(1).buffered().len > 64 * 1024) break;
	} else |err| switch (err) {
		error.EndOfStream => {},
		else => |e| return e,
	}

	try multi.checkAnyError();

	const term = child.wait(io) catch {
		return .{ .code = 1, .out = try multi.toOwnedSlice(0), .err = try multi.toOwnedSlice(1) };
	};

	const code: u8 = switch (term) {
		.exited => |status| status,
		else => 1,
	};

	return .{ .code = code, .out = try multi.toOwnedSlice(0), .err = try multi.toOwnedSlice(1) };
}

pub fn selfPath(io: Io, allocator: Allocator) ![]u8 {
	const proc = @import("proc.zig");
	const raw = try proc.readFile(io, allocator, "/proc/self/exe");

	return raw;
}
