const std = @import("std");

pub const Allocator = std.mem.Allocator;

pub fn nowMs(io: std.Io) i64 {
	return std.Io.Clock.real.now(io).toMilliseconds();
}

pub fn isoFromMs(allocator: Allocator, ms: i64) ![]u8 {
	const secs: u64 = if (ms <= 0) 0 else @intCast(@divTrunc(ms, 1000));
	const epoch = std.time.epoch.EpochSeconds{ .secs = secs };
	const day = epoch.getEpochDay();
	const year_day = day.calculateYearDay();
	const month_day = year_day.calculateMonthDay();
	const day_seconds = epoch.getDaySeconds();

	return std.fmt.allocPrint(allocator, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
		year_day.year,
		month_day.month.numeric(),
		month_day.day_index + 1,
		day_seconds.getHoursIntoDay(),
		day_seconds.getMinutesIntoHour(),
		day_seconds.getSecondsIntoMinute(),
	});
}

pub fn seconds(ms: i64) f64 {
	return @as(f64, @floatFromInt(ms)) / 1000.0;
}

pub fn round2(value: f64) f64 {
	return @round(value * 100.0) / 100.0;
}

pub fn clampi(value: i64, low: i64, high: i64) i64 {
	return @min(@max(value, low), high);
}

test "iso converts a known timestamp" {
	const allocator = std.testing.allocator;

	const out = try isoFromMs(allocator, 1792884000000);
	defer allocator.free(out);

	try std.testing.expectEqualStrings("2026-10-24T23:20:00Z", out);
}

test "round2 keeps two decimals" {
	try std.testing.expectEqual(@as(f64, 1.23), round2(1.2349));
}
