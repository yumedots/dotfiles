const std = @import("std");
const exec = @import("exec.zig");
const fmt = @import("fmt.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const refresh_ms: i64 = 600_000;

pub fn offsetMs(io: Io, allocator: Allocator) ?i64 {
	const result = exec.run(io, allocator, &.{ "date", "+%z" }) catch return null;
	defer result.deinit(allocator);

	return parseZone(std.mem.trim(u8, result.out, " \t\r\n"));
}

pub fn parseZone(text: []const u8) ?i64 {
	if (text.len < 5) return null;

	const sign: i64 = if (text[0] == '-') -1 else 1;
	const hours = std.fmt.parseInt(i64, text[1..3], 10) catch return null;
	const minutes = std.fmt.parseInt(i64, text[3..5], 10) catch return null;

	return sign * (hours * 3_600_000 + minutes * 60_000);
}

pub fn epochDay(io: Io, offset: i64) i64 {
	return @divFloor(fmt.nowMs(io) + offset, 86_400_000);
}

test "zone offsets parse with their sign" {
	try std.testing.expectEqual(@as(?i64, -3 * 3_600_000), parseZone("-0300"));
	try std.testing.expectEqual(@as(?i64, 5_400_000), parseZone("+0130"));
	try std.testing.expectEqual(@as(?i64, null), parseZone("UTC"));
}
