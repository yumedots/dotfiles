const std = @import("std");

const Allocator = std.mem.Allocator;

const quiet_rate: f64 = 16 * 1024;

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
	up: []const u32,
	down: []const u32,
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
		.up = try levels(arena, history, scale, cells, true),
		.down = try levels(arena, history, scale, cells, false),
	};
}

pub fn levels(arena: Allocator, history: []const HistOut, scale: f64, cells: usize, up: bool) ![]const u32 {
	const out = try arena.alloc(u32, cells * 2);
	const top = if (scale > 0) scale else 1;
	var index: i64 = @as(i64, @intCast(history.len)) - @as(i64, @intCast(cells * 2));

	for (out) |*level| {
		var value: f64 = 0;

		if (index >= 0 and index < history.len) {
			const entry = history[@intCast(index)];
			value = if (up) entry.up else entry.down;
		}

		index += 1;
		level.* = if (value < quiet_rate) 0 else @intFromFloat(@min(4, @floor(@max(0, value) / top * 4 + 0.5)));
	}

	return out;
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

test "a full sample column fills its half of the cell" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();
	const history = [_]HistOut{ .{ .down = 0, .up = 0 }, .{ .down = 0, .up = 1_000_000 } };

	try std.testing.expectEqualSlices(u32, &.{ 0, 4 }, try levels(allocator, &history, 1_000_000, 1, true));
	try std.testing.expectEqualSlices(u32, &.{ 0, 0 }, try levels(allocator, &history, 1_000_000, 1, false));
}

test "quiet traffic lights no dots" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();
	const history = [_]HistOut{ .{ .down = 1024, .up = 2048 }, .{ .down = 4096, .up = 8192 } };

	try std.testing.expectEqualSlices(u32, &.{ 0, 0, 0, 0 }, try levels(allocator, &history, 8192, 2, false));
}

test "the graph keeps the newest samples when the history runs long" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();
	var history: [60]HistOut = @splat(.{ .down = 0, .up = 0 });

	for (&history, 0..) |*entry, index| entry.* = .{ .down = if (index == 59) 1_000_000 else 0, .up = 0 };

	const out = try levels(allocator, &history, 1_000_000, 2, false);

	try std.testing.expectEqualSlices(u32, &.{ 0, 0, 0, 4 }, out);
}

test "per-column levels paint the shape the braille mask did" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();
	const cells: usize = 2;
	const scale: f64 = 1_000_000;
	const history = [_]HistOut{
		.{ .down = 1_000_000, .up = 0 },
		.{ .down = 500_000, .up = 1_000_000 },
		.{ .down = 0, .up = 250_000 },
		.{ .down = 800_000, .up = 0 },
	};

	const down = try levels(allocator, &history, scale, cells, false);
	const up = try levels(allocator, &history, scale, cells, true);

	try std.testing.expectEqualSlices(u32, &.{ 4, 2, 0, 3 }, down);
	try std.testing.expectEqualSlices(u32, &.{ 0, 4, 1, 0 }, up);

	const down_art = try art(allocator, try levelGrid(allocator, down, false), down.len);
	const up_art = try art(allocator, try levelGrid(allocator, up, true), up.len);

	try std.testing.expectEqualStrings("#...\n#..#\n##.#\n##.#\n", down_art);
	try std.testing.expectEqualStrings(".##.\n.#..\n.#..\n.#..\n", up_art);
	try std.testing.expectEqual(@as(usize, 9), std.mem.count(u8, down_art, "#"));
	try std.testing.expectEqual(@as(usize, 5), std.mem.count(u8, up_art, "#"));

	for ([_]bool{ true, false }) |low| {
		const mine = try levelGrid(allocator, try levels(allocator, &history, scale, cells, low), low);
		const theirs = try maskGrid(allocator, try refMask(allocator, &history, scale, cells, low), low);

		try std.testing.expectEqualSlices(bool, theirs, mine);
	}
}

test "levels match the braille mask on a full history" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();
	var history: [60]HistOut = @splat(.{ .down = 0, .up = 0 });

	for (&history, 0..) |*entry, index| {
		const wave = @as(f64, @floatFromInt(index % 7)) / 6;

		entry.* = .{ .down = wave * 900_000, .up = (1 - wave) * 700_000 };
	}

	const cells: usize = 26;
	var lit = [_]usize{ 0, 0 };

	for ([_]bool{ true, false }, 0..) |low, side| {
		const mine = try levelGrid(allocator, try levels(allocator, &history, 900_000, cells, low), low);
		const theirs = try maskGrid(allocator, try refMask(allocator, &history, 900_000, cells, low), low);

		try std.testing.expectEqual(@as(usize, cells * 2 * 4), mine.len);
		try std.testing.expectEqualSlices(bool, theirs, mine);

		for (mine) |dot| {
			if (dot) lit[side] += 1;
		}
	}

	const columns = try levels(allocator, &history, 900_000, cells, true);
	try std.testing.expectEqual(@as(usize, 52), columns.len);
	try std.testing.expectEqual(@as(usize, 91), lit[0]);
	try std.testing.expectEqual(@as(usize, 102), lit[1]);
}

fn refMask(allocator: Allocator, history: []const HistOut, scale: f64, cells: usize, up: bool) ![]const u8 {
	const out = try allocator.alloc(u8, cells);
	const top = if (scale > 0) scale else 1;
	var index: i64 = @as(i64, @intCast(history.len)) - @as(i64, @intCast(cells * 2));

	for (out) |*mask| {
		mask.* = 0;

		for (0..2) |column| {
			var value: f64 = 0;

			if (index >= 0 and index < history.len) {
				const entry = history[@intCast(index)];
				value = if (up) entry.up else entry.down;
			}

			index += 1;

			if (value < quiet_rate) continue;

			const count: u8 = @intFromFloat(@min(4, @floor(@max(0, value) / top * 4 + 0.5)));
			const dots: u8 = (@as(u8, 1) << @intCast(count)) - 1;
			const bits: u8 = if (up) dots << @intCast(column * 4) else dots << @intCast(4 - count) << @intCast(column * 4);

			mask.* |= bits;
		}
	}

	return out;
}

fn maskGrid(allocator: Allocator, mask: []const u8, up: bool) ![]bool {
	_ = up;

	const out = try allocator.alloc(bool, mask.len * 8);
	@memset(out, false);

	for (mask, 0..) |cell, cell_index| {
		for (0..8) |bit| {
			if (cell >> @intCast(bit) & 1 == 0) continue;

			out[(bit % 4) * mask.len * 2 + cell_index * 2 + bit / 4] = true;
		}
	}

	return out;
}

fn levelGrid(allocator: Allocator, levels_out: []const u32, up: bool) ![]bool {
	const out = try allocator.alloc(bool, levels_out.len * 4);
	@memset(out, false);

	for (levels_out, 0..) |level, column| {
		for (0..level) |step| {
			const row = if (up) step else 3 - step;

			out[row * levels_out.len + column] = true;
		}
	}

	return out;
}

fn art(allocator: Allocator, grid: []const bool, columns: usize) ![]const u8 {
	var out: std.ArrayListUnmanaged(u8) = .empty;

	for (0..4) |row| {
		for (0..columns) |column| try out.append(allocator, if (grid[row * columns + column]) '#' else '.');
		try out.append(allocator, '\n');
	}

	return out.items;
}

test "wifi security decides whether a network is locked" {
	try std.testing.expect(locked("WPA2"));
	try std.testing.expect(locked("WPA1 WPA2 802.1X"));
	try std.testing.expect(!locked(""));
	try std.testing.expect(!locked("--"));
}
