const std = @import("std");
const hubmod = @import("../hub.zig");
const config = @import("../primitives/config.zig");
const exec = @import("../primitives/exec.zig");
const fmt = @import("../primitives/fmt.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const month_names = [_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };
const day_names = [_][]const u8{ "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
const offset_refresh_ms: i64 = 600_000;

const Cell = struct {
	key: []const u8,
	day: i64,
	outside: bool,
	today: bool,
	cursor: bool,
};

const Meter = struct {
	icon: []const u8,
	label: []const u8,
	pct: i64,
};

const Out = struct {
	month: []const u8,
	year: []const u8,
	weekdays: []const []const u8,
	rows: [][]const Cell,
	meters: []const Meter,
};

const Stamp = struct {
	year: i64,
	month: i64,
	day: i64,
	seconds: i64,
	epoch: i64,
};

pub const Calendar = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	cursor: i64 = 0,
	week_start: i64 = 1,
	rows: i64 = 6,
	birth_year: i64 = 0,
	expectancy: i64 = 90,
	icons: [4][]const u8 = .{ "", "", "", "" },
	offset_ms: i64 = 0,
	offset_at: i64 = 0,

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Calendar {
		const self = try allocator.create(Calendar);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.scratch = std.heap.ArenaAllocator.init(allocator),
		};

		self.loadConfig();
		self.refreshOffset();
		self.cursor = today(self.io, self.offset_ms).epoch;

		return self;
	}

	pub fn provider(self: *Calendar) hubmod.Provider {
		return .{ .key = "calendar", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Calendar = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	fn loadConfig(self: *Calendar) void {
		const cfg = config.Config.load(self.io, self.allocator) catch return;
		defer cfg.deinit();

		self.week_start = fmt.clampi(cfg.integer("calendarWeekStart", 1), 0, 6);
		self.rows = @max(1, cfg.integer("calendarRows", 6));
		self.birth_year = cfg.integer("calendarBirthYear", 0);
		self.expectancy = cfg.integer("calendarLifeExpectancy", 90);

		const keys = [_][]const u8{ "calendarIconDay", "calendarIconMonth", "calendarIconYear", "calendarIconLife" };

		for (keys, 0..) |key, index| {
			const raw = cfg.string(key, self.allocator) orelse continue;
			self.icons[index] = config.unescape(self.allocator, raw) catch "";
		}
	}

	fn refreshOffset(self: *Calendar) void {
		self.offset_at = fmt.nowMs(self.io);

		const result = exec.run(self.io, self.allocator, &.{ "date", "+%z" }) catch return;
		defer result.deinit(self.allocator);

		const text = std.mem.trim(u8, result.out, " \t\r\n");
		if (text.len < 5) return;

		const sign: i64 = if (text[0] == '-') -1 else 1;
		const hours = std.fmt.parseInt(i64, text[1..3], 10) catch return;
		const minutes = std.fmt.parseInt(i64, text[3..5], 10) catch return;

		self.offset_ms = sign * (hours * 3_600_000 + minutes * 60_000);
	}

	pub fn shiftDays(self: *Calendar, days: i64) void {
		self.mutex.lockUncancelable(self.io);
		self.cursor += days;
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	pub fn shiftMonths(self: *Calendar, months: i64) void {
		self.mutex.lockUncancelable(self.io);
		const date = fmt.dateFromDay(self.cursor);
		const moved = shift(date.year, date.month, 0, months);
		self.cursor = fmt.daysFromCivil(moved.year, moved.month, @min(date.day, fmt.daysInMonth(moved.year, moved.month)));
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	pub fn shiftYears(self: *Calendar, years: i64) void {
		self.mutex.lockUncancelable(self.io);
		const date = fmt.dateFromDay(self.cursor);
		const moved = shift(date.year, date.month, years, 0);
		self.cursor = fmt.daysFromCivil(moved.year, moved.month, @min(date.day, fmt.daysInMonth(moved.year, moved.month)));
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	pub fn reset(self: *Calendar) void {
		const now = today(self.io, self.offset_ms);

		self.mutex.lockUncancelable(self.io);
		self.cursor = now.epoch;
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	pub fn setWeekStart(self: *Calendar, at: i64) void {
		self.mutex.lockUncancelable(self.io);
		self.week_start = fmt.clampi(at, 0, 6);
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn render(self: *Calendar, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		if (fmt.nowMs(self.io) - self.offset_at > offset_refresh_ms) self.refreshOffset();

		_ = self.scratch.reset(.retain_capacity);
		const arena = self.scratch.allocator();

		const now = today(self.io, self.offset_ms);
		const cursor = fmt.dateFromDay(self.cursor);

		const out = Out{
			.month = month_names[@intCast(fmt.clampi(cursor.month - 1, 0, 11))],
			.year = try std.fmt.allocPrint(arena, "{d}", .{cursor.year}),
			.weekdays = try weekdays(arena, self.week_start),
			.rows = try monthRows(arena, self.cursor, self.week_start, self.rows, now.epoch),
			.meters = try meterRows(arena, now, self.birth_year, self.expectancy, self.icons),
		};

		try writer.print("{f}", .{std.json.fmt(out, .{})});
	}
};

fn today(io: Io, offset_ms: i64) Stamp {
	const ms = fmt.nowMs(io) + offset_ms;
	const secs: u64 = @intCast(@divFloor(ms, 1000));
	const epoch = std.time.epoch.EpochSeconds{ .secs = secs };
	const day = epoch.getEpochDay();
	const year_day = day.calculateYearDay();
	const month_day = year_day.calculateMonthDay();

	return .{
		.year = year_day.year,
		.month = month_day.month.numeric(),
		.day = month_day.day_index + 1,
		.seconds = epoch.getDaySeconds().secs,
		.epoch = day.day,
	};
}

fn shift(year: i64, month: i64, years: i64, months: i64) fmt.Date {
	var moved = fmt.Date{ .year = year + years, .month = month + months, .day = 1 };

	while (moved.month > 12) {
		moved.month -= 12;
		moved.year += 1;
	}

	while (moved.month < 1) {
		moved.month += 12;
		moved.year -= 1;
	}

	return moved;
}

fn weekdays(arena: Allocator, week_start: i64) ![]const []const u8 {
	const out = try arena.alloc([]const u8, 7);

	for (out, 0..) |*name, index| {
		name.* = day_names[@intCast(@mod(week_start + @as(i64, @intCast(index)), 7))];
	}

	return out;
}

pub fn monthRows(arena: Allocator, cursor: i64, week_start: i64, rows: i64, today_epoch: i64) ![][]const Cell {
	const date = fmt.dateFromDay(cursor);
	const first = fmt.daysFromCivil(date.year, date.month, 1);
	const lead: i64 = @mod(@mod(first + 4, 7) - week_start + 7, 7);
	const start = first - lead;
	const height: usize = @intCast(@max(1, rows));

	const grid = try arena.alloc([]const Cell, height);

	for (grid, 0..) |*row, index| {
		const cells = try arena.alloc(Cell, 7);

		for (cells, 0..) |*cell, column| {
			const day = start + @as(i64, @intCast(index * 7 + column));
			const cell_date = fmt.dateFromDay(day);

			cell.* = .{
				.key = try std.fmt.allocPrint(arena, "{d:0>4}-{d:0>2}-{d:0>2}", .{
					@as(u16, @intCast(cell_date.year)),
					@as(u8, @intCast(cell_date.month)),
					@as(u8, @intCast(cell_date.day)),
				}),
				.day = cell_date.day,
				.outside = cell_date.year != date.year or cell_date.month != date.month,
				.today = day == today_epoch,
				.cursor = day == cursor,
			};
		}

		row.* = cells;
	}

	return grid;
}

fn meterRows(arena: Allocator, now: Stamp, birth_year: i64, expectancy: i64, icons: [4][]const u8) ![]const Meter {
	const fraction = @as(f64, @floatFromInt(now.seconds)) / 86400.0;
	const month_span = @as(f64, @floatFromInt(fmt.daysInMonth(now.year, now.month)));
	const day_of_year = now.epoch - fmt.daysFromCivil(now.year, 1, 1);
	const year_span: f64 = if (fmt.daysInMonth(now.year, 2) == 29) 366 else 365;

	const out = try arena.alloc(Meter, if (birth_year > 0) 4 else 3);

	out[0] = .{ .icon = icons[0], .label = "DAY", .pct = percent(fraction) };
	out[1] = .{ .icon = icons[1], .label = "MONTH", .pct = percent((@as(f64, @floatFromInt(now.day - 1)) + fraction) / month_span) };
	out[2] = .{ .icon = icons[2], .label = "YEAR", .pct = percent((@as(f64, @floatFromInt(day_of_year)) + fraction) / year_span) };

	if (birth_year > 0) {
		const span = @as(f64, @floatFromInt(@max(@as(i64, 1), expectancy)));
		const lived = (@as(f64, @floatFromInt(now.year)) - @as(f64, @floatFromInt(birth_year))) / span;

		out[3] = .{ .icon = icons[3], .label = "LIFE", .pct = percent(lived) };
	}

	return out;
}

fn percent(value: f64) i64 {
	return @intFromFloat(@round(@min(@max(value, 0), 1) * 100));
}

test "the month grid starts on the week day" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const cursor = fmt.daysFromCivil(2026, 10, 1);
	const grid = try monthRows(arena.allocator(), cursor, 1, 6, fmt.daysFromCivil(2026, 10, 28));

	try std.testing.expectEqual(@as(usize, 6), grid.len);
	try std.testing.expectEqual(@as(usize, 7), grid[0].len);
	try std.testing.expectEqualStrings("2026-09-28", grid[0][0].key);
	try std.testing.expectEqualStrings("2026-10-01", grid[0][3].key);
	try std.testing.expectEqual(@as(i64, 1), grid[0][3].day);
	try std.testing.expect(grid[0][0].outside);
	try std.testing.expect(!grid[0][3].outside);
	try std.testing.expect(grid[4][2].today);
	try std.testing.expectEqual(@as(i64, 28), grid[4][2].day);
	try std.testing.expect(!grid[4][2].cursor);

	const sunday = try monthRows(arena.allocator(), cursor, 0, 6, 0);
	try std.testing.expectEqualStrings("2026-09-27", sunday[0][0].key);
}

test "month and year steps clamp the day" {
	var month = shift(2026, 1, 0, 1);
	try std.testing.expectEqual(@as(i64, 2), month.month);
	try std.testing.expectEqual(@as(i64, 28), @min(@as(i64, 31), fmt.daysInMonth(month.year, month.month)));

	month = shift(2026, 12, 0, 1);
	try std.testing.expectEqual(@as(i64, 2027), month.year);
	try std.testing.expectEqual(@as(i64, 1), month.month);

	const back = shift(2026, 1, 0, -1);
	try std.testing.expectEqual(@as(i64, 2025), back.year);
	try std.testing.expectEqual(@as(i64, 12), back.month);

	const leap = shift(2028, 2, 1, 0);
	try std.testing.expectEqual(@as(i64, 2029), leap.year);
	try std.testing.expectEqual(@as(i64, 28), @min(@as(i64, 29), fmt.daysInMonth(leap.year, leap.month)));
}

test "meters follow the clock" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const icons = [4][]const u8{ "d", "m", "y", "l" };
	const stamp = Stamp{
		.year = 2026,
		.month = 10,
		.day = 28,
		.seconds = 15 * 3600 + 30 * 60,
		.epoch = fmt.daysFromCivil(2026, 10, 28),
	};

	const rows = try meterRows(arena.allocator(), stamp, 0, 90, icons);

	try std.testing.expectEqual(@as(usize, 3), rows.len);
	try std.testing.expectEqualStrings("DAY", rows[0].label);
	try std.testing.expectEqual(@as(i64, 65), rows[0].pct);
	try std.testing.expectEqual(@as(i64, 89), rows[1].pct);
	try std.testing.expectEqual(@as(i64, 82), rows[2].pct);

	const with_life = try meterRows(arena.allocator(), stamp, 1990, 90, icons);
	try std.testing.expectEqual(@as(usize, 4), with_life.len);
	try std.testing.expectEqual(@as(i64, 40), with_life[3].pct);
}
