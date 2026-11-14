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

pub const Date = struct {
	year: i64,
	month: i64,
	day: i64,
};

pub fn daysFromCivil(year: i64, month: i64, day: i64) i64 {
	const y = if (month <= 2) year - 1 else year;
	const era = @divFloor(y, 400);
	const yoe = y - era * 400;
	const mp = @mod(month + 9, 12);
	const doy = @divFloor(153 * mp + 2, 5) + day - 1;
	const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;

	return era * 146097 + doe - 719468;
}

pub fn dateFromDay(day: i64) Date {
	const year_day = (std.time.epoch.EpochDay{ .day = @intCast(day) }).calculateYearDay();
	const month_day = year_day.calculateMonthDay();

	return .{ .year = year_day.year, .month = month_day.month.numeric(), .day = month_day.day_index + 1 };
}

pub fn weekdayIndex(year: i64, month: i64, day: i64) usize {
	return @intCast(@mod(daysFromCivil(year, month, day) + 4, 7));
}

pub fn daysInMonth(year: i64, month: i64) i64 {
	if (month >= 12) return daysFromCivil(year + 1, 1, 1) - daysFromCivil(year, 12, 1);

	return daysFromCivil(year, month + 1, 1) - daysFromCivil(year, month, 1);
}

test "iso converts a known timestamp" {
	const allocator = std.testing.allocator;

	const out = try isoFromMs(allocator, 1792884000000);
	defer allocator.free(out);

	try std.testing.expectEqualStrings("2026-10-24T23:20:00Z", out);
}

test "civil dates round trip" {
	try std.testing.expectEqual(@as(i64, 0), daysFromCivil(1970, 1, 1));
	try std.testing.expectEqual(@as(i64, 20754), daysFromCivil(2026, 10, 28));
	try std.testing.expectEqual(3, weekdayIndex(2026, 10, 28));
	try std.testing.expectEqual(4, weekdayIndex(2026, 10, 1));
	try std.testing.expectEqual(1, weekdayIndex(2026, 9, 28));

	const date = dateFromDay(20754);
	try std.testing.expectEqual(@as(i64, 2026), date.year);
	try std.testing.expectEqual(@as(i64, 10), date.month);
	try std.testing.expectEqual(@as(i64, 28), date.day);

	try std.testing.expectEqual(@as(i64, 31), daysInMonth(2026, 10));
	try std.testing.expectEqual(@as(i64, 28), daysInMonth(2026, 2));
	try std.testing.expectEqual(@as(i64, 29), daysInMonth(2028, 2));
	try std.testing.expectEqual(@as(i64, 31), daysInMonth(2026, 12));
}

test "round2 keeps two decimals" {
	try std.testing.expectEqual(@as(f64, 1.23), round2(1.2349));
}
