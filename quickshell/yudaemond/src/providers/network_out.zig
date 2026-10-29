const std = @import("std");

const Allocator = std.mem.Allocator;

const quiet_rate: f64 = 16 * 1024;
const braille_base: u21 = 0x2800;

pub const HistOut = struct {
	down: f64,
	up: f64,
};

pub const WifiOut = struct {
	ssid: []const u8,
	security: []const u8,
	locked: bool,
	signal: i64,
	signalText: []const u8,
	bars: i64,
	channel: i64,
	frequency: i64,
	inUse: bool,
};

pub const DetailOut = struct {
	label: []const u8,
	text: []const u8,
	ink: []const u8,
};

pub const GraphOut = struct {
	up: []const u8,
	down: []const u8,
};

pub const SpeedOut = struct {
	stage: []const u8,
	live: f64,
	best: f64,
	down: f64,
	up: f64,
	text: []const u8,
	downText: []const u8,
	upText: []const u8,
	ceiling: f64,
};

pub const Out = struct {
	iface: []const u8,
	kind: []const u8,
	connected: bool,
	ssid: []const u8,
	signal: i64,
	signalText: []const u8,
	bars: i64,
	down: f64,
	up: f64,
	downText: []const u8,
	upText: []const u8,
	linkSpeed: i64,
	peak: f64,
	history: []HistOut,
	graph: GraphOut,
	details: []DetailOut,
	ip: []const u8,
	gateway: []const u8,
	dns: []const u8,
	dnsPending: bool,
	dnsError: []const u8,
	wifi: []WifiOut,
	speed: SpeedOut,
};

pub fn graph(arena: Allocator, history: []const HistOut, scale: f64, cells: usize) !GraphOut {
	return .{
		.up = try line(arena, history, scale, cells, true),
		.down = try line(arena, history, scale, cells, false),
	};
}

pub fn line(arena: Allocator, history: []const HistOut, scale: f64, cells: usize, up: bool) ![]const u8 {
	var out: std.ArrayListUnmanaged(u8) = .empty;
	const top = if (scale > 0) scale else 1;
	var index: i64 = @as(i64, @intCast(history.len)) - @as(i64, @intCast(cells * 2));

	for (0..cells) |_| {
		var mask: u8 = 0;

		for (0..2) |column| {
			var value: f64 = 0;

			if (index >= 0 and index < history.len) {
				const entry = history[@intCast(index)];
				value = if (up) entry.up else entry.down;
			}

			index += 1;

			if (value < quiet_rate) continue;

			const lit: u8 = @intFromFloat(@min(4, @floor(@max(0, value) / top * 4 + 0.5)));
			const dots: u8 = (@as(u8, 1) << @intCast(lit)) - 1;
			const bits: u8 = if (up) dots << @intCast(column * 4) else dots << @intCast(4 - lit) << @intCast(column * 4);

			mask |= bits;
		}

		const point: u21 = brailleChar(mask);
		var buffer: [4]u8 = undefined;
		const size = std.unicode.utf8Encode(point, &buffer) catch continue;

		try out.appendSlice(arena, buffer[0..size]);
	}

	return out.items;
}

pub fn brailleChar(mask: u8) u21 {
	const lower_left: u21 = mask & 0x7;
	const lower_right: u21 = (mask >> 4) & 0x7;
	const tail: u21 = ((mask >> 3) & 0x1) << 6 | ((mask >> 7) & 0x1) << 7;

	return braille_base + lower_left + (lower_right << 3) + tail;
}

pub fn locked(security: []const u8) bool {
	return security.len > 0 and !std.mem.eql(u8, security, "--");
}

pub fn rateText(allocator: Allocator, rate: f64) ![]const u8 {
	const value = @max(0, rate);

	if (value >= 1024 * 1024) return std.fmt.allocPrint(allocator, "{d:.1} MB/s", .{value / (1024 * 1024)});
	if (value >= 1024) return std.fmt.allocPrint(allocator, "{d:.0} KB/s", .{value / 1024});

	return std.fmt.allocPrint(allocator, "{d:.0} B/s", .{value});
}

fn megaBits(rate: f64) f64 {
	return @max(0, rate) * 8 / 1000000;
}

pub fn speedText(allocator: Allocator, rate: f64) ![]const u8 {
	return std.fmt.allocPrint(allocator, "{d:.0}", .{megaBits(rate)});
}

pub fn speedCeiling(rate: f64) f64 {
	const ladder = [_]f64{ 5, 10, 25, 50, 100, 250, 500, 1000 };
	const mbps = megaBits(rate) * 1.5;

	for (ladder) |step| {
		if (mbps < step) return step * 125000;
	}

	return ladder[ladder.len - 1] * 125000;
}

pub fn signalBars(pct: i64) i64 {
	const value = std.math.clamp(pct, 0, 100);

	if (value > 80) return 4;
	if (value > 55) return 3;
	if (value > 30) return 2;

	return if (value > 5) 1 else 0;
}

pub fn signalText(allocator: Allocator, pct: i64) ![]const u8 {
	if (pct < 0) return "-";

	return std.fmt.allocPrint(allocator, "{d}%", .{pct});
}

test "rates format" {
	const allocator = std.testing.allocator;

	const idle = try rateText(allocator, 0);
	defer allocator.free(idle);
	try std.testing.expectEqualStrings("0 B/s", idle);

	const bytes = try rateText(allocator, 512);
	defer allocator.free(bytes);
	try std.testing.expectEqualStrings("512 B/s", bytes);

	const kb = try rateText(allocator, 1600);
	defer allocator.free(kb);
	try std.testing.expectEqualStrings("2 KB/s", kb);

	const mb = try rateText(allocator, 1.2 * 1024 * 1024);
	defer allocator.free(mb);
	try std.testing.expectEqualStrings("1.2 MB/s", mb);
}

test "speed text is whole megabits" {
	const allocator = std.testing.allocator;

	const zero = try speedText(allocator, 0);
	defer allocator.free(zero);
	try std.testing.expectEqualStrings("0", zero);

	const one = try speedText(allocator, 125000);
	defer allocator.free(one);
	try std.testing.expectEqualStrings("1", one);

	const twenty = try speedText(allocator, 2_500_000);
	defer allocator.free(twenty);
	try std.testing.expectEqualStrings("20", twenty);
}

test "speed ceiling climbs the ladder" {
	try std.testing.expectEqual(@as(f64, 625000), speedCeiling(0));
	try std.testing.expectEqual(@as(f64, 3125000), speedCeiling(1_000_000));
	try std.testing.expectEqual(@as(f64, 125000000), speedCeiling(100_000_000));
}

test "signal percent maps to bars" {
	try std.testing.expectEqual(@as(i64, 4), signalBars(100));
	try std.testing.expectEqual(@as(i64, 4), signalBars(81));
	try std.testing.expectEqual(@as(i64, 3), signalBars(80));
	try std.testing.expectEqual(@as(i64, 3), signalBars(56));
	try std.testing.expectEqual(@as(i64, 2), signalBars(55));
	try std.testing.expectEqual(@as(i64, 2), signalBars(31));
	try std.testing.expectEqual(@as(i64, 1), signalBars(30));
	try std.testing.expectEqual(@as(i64, 1), signalBars(6));
	try std.testing.expectEqual(@as(i64, 0), signalBars(5));
	try std.testing.expectEqual(@as(i64, 0), signalBars(-20));
	try std.testing.expectEqual(@as(i64, 4), signalBars(200));
}

test "signal text is a percent or a dash" {
	const allocator = std.testing.allocator;

	const some = try signalText(allocator, 83);
	defer allocator.free(some);
	try std.testing.expectEqualStrings("83%", some);

	const none = try signalText(allocator, -1);
	try std.testing.expectEqualStrings("-", none);
}

test "braille cells take the 2x4 dot grid the graph paints" {
	try std.testing.expectEqual(@as(u21, 0x2800), brailleChar(0));
	try std.testing.expectEqual(@as(u21, 0x2801), brailleChar(0x01));
	try std.testing.expectEqual(@as(u21, 0x2840), brailleChar(0x08));
	try std.testing.expectEqual(@as(u21, 0x28B8), brailleChar(0xF0));
	try std.testing.expectEqual(@as(u21, 0x2847), brailleChar(0x0F));
	try std.testing.expectEqual(@as(u21, 0x28FF), brailleChar(0xFF));
}

test "a full sample column fills its half of the cell" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();
	const history = [_]HistOut{ .{ .down = 0, .up = 0 }, .{ .down = 0, .up = 1_000_000 } };

	try std.testing.expectEqualStrings("\u{28B8}", try line(allocator, &history, 1_000_000, 1, true));
	try std.testing.expectEqualStrings("\u{2800}", try line(allocator, &history, 1_000_000, 1, false));
}

test "quiet traffic lights no dots" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();
	const history = [_]HistOut{ .{ .down = 1024, .up = 2048 }, .{ .down = 4096, .up = 8192 } };

	try std.testing.expectEqualStrings("\u{2800}\u{2800}", try line(allocator, &history, 8192, 2, false));
}

test "the graph keeps the newest samples when the history runs long" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();
	var history: [60]HistOut = @splat(.{ .down = 0, .up = 0 });

	for (&history, 0..) |*entry, index| entry.* = .{ .down = if (index == 59) 1_000_000 else 0, .up = 0 };

	const text = try line(allocator, &history, 1_000_000, 2, false);

	try std.testing.expectEqual(@as(usize, 2 * 3), text.len);
	try std.testing.expect(std.mem.endsWith(u8, text, "\u{28B8}"));
}

test "wifi security decides whether a network is locked" {
	try std.testing.expect(locked("WPA2"));
	try std.testing.expect(locked("WPA1 WPA2 802.1X"));
	try std.testing.expect(!locked(""));
	try std.testing.expect(!locked("--"));
}
