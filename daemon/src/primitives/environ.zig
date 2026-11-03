const std = @import("std");
const proc = @import("proc.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn current(io: Io, allocator: Allocator) !std.process.Environ {
	return ofPid(io, allocator, null);
}

pub fn ofPid(io: Io, allocator: Allocator, pid: ?i32) !std.process.Environ {
	const path = if (pid) |value|
		try std.fmt.allocPrint(allocator, "/proc/{d}/environ", .{value})
	else
		"/proc/self/environ";

	defer if (pid != null) allocator.free(path);

	const body = try proc.readFile(io, allocator, path);

	var entries: std.ArrayList(?[*:0]const u8) = .empty;
	errdefer entries.deinit(allocator);

	var it = std.mem.splitScalar(u8, body, 0);

	while (it.next()) |entry| {
		if (entry.len == 0) break;

		const terminated = try allocator.allocSentinel(u8, entry.len, 0);
		@memcpy(terminated, entry);
		try entries.append(allocator, terminated.ptr);
	}

	try entries.append(allocator, null);

	const items = entries.items;
	const pointer: [*]const ?[*:0]const u8 = items.ptr;

	return .{ .block = .{ .slice = pointer[0 .. items.len - 1 :null] } };
}
