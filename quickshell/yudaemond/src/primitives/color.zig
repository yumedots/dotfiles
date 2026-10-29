const std = @import("std");

pub const Rgb = [3]u8;

pub fn parse(text: []const u8) ?Rgb {
	var value = std.mem.trim(u8, text, " \t\"';");

	if (value.len > 0 and value[0] == '#') value = value[1..];
	if (value.len != 6) return null;

	return .{
		std.fmt.parseInt(u8, value[0..2], 16) catch return null,
		std.fmt.parseInt(u8, value[2..4], 16) catch return null,
		std.fmt.parseInt(u8, value[4..6], 16) catch return null,
	};
}

pub fn mix(a: Rgb, b: Rgb, t: f64) Rgb {
	const k = std.math.clamp(t, 0, 1);

	return .{ step(a[0], b[0], k), step(a[1], b[1], k), step(a[2], b[2], k) };
}

pub fn danger(base: Rgb, warn: Rgb, alert: Rgb, warn_at: f64, danger_at: f64, pct: f64) Rgb {
	if (pct <= warn_at) return mix(base, warn, if (warn_at > 0) pct / warn_at else 1);
	if (pct >= danger_at) return alert;

	return mix(warn, alert, if (danger_at > warn_at) (pct - warn_at) / (danger_at - warn_at) else 1);
}

pub fn hex(buffer: *[7]u8, rgb: Rgb) []const u8 {
	return std.fmt.bufPrint(buffer, "#{x:0>2}{x:0>2}{x:0>2}", .{ rgb[0], rgb[1], rgb[2] }) catch "#000000";
}

fn step(from: u8, to: u8, t: f64) u8 {
	const a: f64 = @floatFromInt(from);
	const b: f64 = @floatFromInt(to);

	return @intFromFloat(@round(a + (b - a) * t));
}

test "mix matches the shell's byte arithmetic" {
	try std.testing.expectEqual(Rgb{ 176, 130, 225 }, mix(parse("#a78bfa").?, parse("#e05252").?, 0.15));
	try std.testing.expectEqual(Rgb{ 221, 85, 90 }, mix(parse("#a78bfa").?, parse("#e05252").?, 0.95));
	try std.testing.expectEqual(Rgb{ 170, 196, 109 }, danger(parse("#7bd88f").?, parse("#d8b04a").?, parse("#e05252").?, 60, 85, 30));
	try std.testing.expectEqual(Rgb{ 224, 82, 82 }, danger(parse("#7bd88f").?, parse("#d8b04a").?, parse("#e05252").?, 60, 85, 95));
}

test "danger saturates past its thresholds" {
	const base = parse("#7bd88f").?;
	const warn = parse("#d8b04a").?;
	const alert = parse("#e05252").?;

	try std.testing.expectEqual(warn, danger(base, warn, alert, 0, 0, 0));
	try std.testing.expectEqual(base, danger(base, warn, alert, 80, 90, 0));
	try std.testing.expectEqual(alert, danger(base, warn, alert, 60, 85, 120));
	try std.testing.expectEqual(Rgb{ 201, 183, 86 }, danger(base, warn, alert, 30, 15, 25));
}

test "hex text round trips" {
	var buffer: [7]u8 = undefined;

	try std.testing.expectEqualStrings("#a78bfa", hex(&buffer, parse("#a78bfa").?));
	try std.testing.expectEqualStrings("#ffffff", hex(&buffer, parse("\"#ffffff\"").?));
	try std.testing.expectEqual(@as(?Rgb, null), parse("#12345"));
}

test "the bar colours match the shell at three loads" {
	const cpu_base = parse("#a78bfa").?;
	const red = parse("#e05252").?;
	const memory_base = parse("#7bd88f").?;
	const warn = parse("#d8b04a").?;
	const empty = parse("#1f1f1f").?;

	try std.testing.expectEqual(Rgb{ 176, 130, 225 }, mix(cpu_base, red, 0.15));
	try std.testing.expectEqual(Rgb{ 198, 108, 158 }, mix(cpu_base, red, 0.55));
	try std.testing.expectEqual(Rgb{ 221, 85, 90 }, mix(cpu_base, red, 0.95));

	try std.testing.expectEqual(Rgb{ 170, 196, 109 }, danger(memory_base, warn, red, 60, 85, 30));
	try std.testing.expectEqual(Rgb{ 219, 138, 77 }, danger(memory_base, warn, red, 60, 85, 70));
	try std.testing.expectEqual(Rgb{ 224, 82, 82 }, danger(memory_base, warn, red, 60, 85, 95));

	try std.testing.expectEqual(Rgb{ 224, 82, 82 }, danger(memory_base, warn, red, 30, 15, 80));
	try std.testing.expectEqual(Rgb{ 201, 183, 86 }, danger(memory_base, warn, red, 30, 15, 25));
	try std.testing.expectEqual(Rgb{ 154, 203, 120 }, danger(memory_base, warn, red, 30, 15, 10));

	try std.testing.expectEqual(Rgb{ 54, 77, 59 }, mix(empty, memory_base, 0.25));
	try std.testing.expectEqual(Rgb{ 77, 124, 87 }, mix(empty, memory_base, 0.5));
	try std.testing.expectEqual(Rgb{ 100, 170, 115 }, mix(empty, memory_base, 0.75));
}
