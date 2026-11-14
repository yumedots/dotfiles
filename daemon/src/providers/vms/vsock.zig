const std = @import("std");
const sock = @import("../../primitives/sock.zig");
const json = @import("../../primitives/json.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const port: u32 = 1024;

pub const Result = struct {
	code: u8 = 0,
	out: []u8,
	err: []u8,

	pub fn deinit(self: Result, allocator: Allocator) void {
		allocator.free(self.out);
		allocator.free(self.err);
	}
};

pub fn state(io: Io, allocator: Allocator, cid: u32) ![]u8 {
	_ = io;
	const buffer = try allocator.alloc(u8, 4 * 1024 * 1024);
	defer allocator.free(buffer);

	var connection = try sock.connectVsock(cid, port, buffer);
	defer connection.close();

	try connection.writeLine(sock.sync);

	var attempts: usize = 0;
	while (attempts < 20) : (attempts += 1) {
		const line = try connection.readLine() orelse return error.NoReply;
		if (std.mem.indexOf(u8, line, "\"rev\"") != null) return allocator.dupe(u8, line);
	}

	return error.NoReply;
}

pub fn exec(io: Io, allocator: Allocator, cid: u32, argv: []const []const u8) !Result {
	_ = io;
	const buffer = try allocator.alloc(u8, 4 * 1024 * 1024);
	defer allocator.free(buffer);

	var connection = try sock.connectVsock(cid, port, buffer);
	defer connection.close();

	var out: std.Io.Writer.Allocating = .init(allocator);
	defer out.deinit();
	const writer = &out.writer;

	try writer.writeAll("{\"exec\":{\"argv\":[");

	for (argv, 0..) |arg, index| {
		if (index > 0) try writer.writeAll(",");
		try std.json.Stringify.encodeJsonString(arg, .{}, writer);
	}

	try writer.writeAll("]}}");
	try connection.writeLine(out.written());

	var attempts: usize = 0;
	while (attempts < 20) : (attempts += 1) {
		const line = try connection.readLine() orelse return error.NoReply;

		var arena = std.heap.ArenaAllocator.init(allocator);
		defer arena.deinit();

		const parsed = try json.parse(arena.allocator(), line);

		if (json.field(parsed.value, "ok") == null) continue;

		return .{
			.code = @intCast(@max(json.integer(json.field(parsed.value, "code")), 0)),
			.out = try allocator.dupe(u8, json.textAt(parsed.value, "out")),
			.err = try allocator.dupe(u8, json.textAt(parsed.value, "err")),
		};
	}

	return error.NoReply;
}
