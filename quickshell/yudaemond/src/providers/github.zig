const std = @import("std");
const hubmod = @import("../hub.zig");
const http = @import("../primitives/http.zig");
const exec = @import("../primitives/exec.zig");
const color = @import("../primitives/color.zig");
const config = @import("../primitives/config.zig");
const json = @import("../primitives/json.zig");
const proc = @import("../primitives/proc.zig");
const sleep = @import("../primitives/sleep.zig");
const fmt = @import("../primitives/fmt.zig");
const localtime = @import("../primitives/localtime.zig");
const setStr = @import("opencode.zig").setStr;

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const Day = struct {
	date: []u8,
	level: i64,
	count: i64,
};

const DayOut = struct {
	date: []const u8,
	level: i64,
	count: i64,
};

const Out = struct {
	levelInk: [][]const u8,
	login: []const u8,
	total: i64,
	fetched: i64,
	status: []const u8,
	days: []DayOut,
	grid: []const ?DayOut,
	todayCount: i64,
	todayLevel: i64,
};

pub const Github = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	http: *http.Client,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	login: []u8 = &.{},
	status: []u8 = &.{},
	days: std.ArrayListUnmanaged(Day) = .empty,
	total: i64 = 0,
	empty_ink: color.Rgb = .{ 0x1f, 0x1f, 0x1f },
	base_ink: color.Rgb = .{ 0x7b, 0xd8, 0x8f },

	fetched: i64 = 0,
	weeks: usize = 19,
	offset_ms: i64 = 0,
	offset_at: i64 = 0,

	pub fn create(allocator: Allocator, io: Io, hub: *Hub, client: *http.Client) !*Github {
		const self = try allocator.create(Github);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.http = client,
			.scratch = std.heap.ArenaAllocator.init(allocator),
		};

		return self;
	}

	pub fn provider(self: *Github) hubmod.Provider {
		return .{ .key = "github", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Github = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn start(self: *Github) !void {
		self.loadPalette();

		const thread = try std.Thread.spawn(.{}, loop, .{self});
		thread.detach();
	}

	fn loadPalette(self: *Github) void {
		const cfg = config.Config.load(self.io, self.allocator) catch return;
		defer cfg.deinit();

		const mono = cfg.boolean("mono", true);

		self.weeks = @intCast(@max(1, cfg.integer("contribWeeks", 19)));

		self.empty_ink = color.parse(cfg.color("contribEmpty") orelse "") orelse self.empty_ink;
		self.base_ink = color.parse(cfg.color(if (mono) "contribBase" else "contribBaseMono") orelse "") orelse self.base_ink;
	}

	pub fn refresh(self: *Github) void {
		self.loadCache();
		self.fetch();
	}

	fn loop(self: *Github) void {
		self.refresh();

		while (true) {
			sleep.ms(1_800_000);
			self.fetch();
		}
	}

	fn cachePath(self: *Github, allocator: Allocator) []const u8 {
		return std.fmt.allocPrint(allocator, "{s}/.config/quickshell/cache/github/contrib.json", .{proc.home(self.io, allocator)}) catch "/nonexistent";
	}

	fn loadCache(self: *Github) void {
		const path = self.cachePath(self.allocator);
		defer self.allocator.free(path);

		const body = proc.readFile(self.io, self.allocator, path) catch "";
		defer if (body.len > 0) self.allocator.free(body);

		if (body.len == 0) return;

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const parsed = json.parse(arena.allocator(), body) catch return;
		self.adopt(parsed.value);
	}

	fn adopt(self: *Github, root: json.Value) void {
		const login = json.textAt(root, "login");
		const days = json.listAt(root, "days");

		if (login.len == 0 or days.len == 0) return;

		self.mutex.lockUncancelable(self.io);
		setStr(self.allocator, &self.login, login) catch {};
		self.total = json.integer(json.field(root, "total"));

		for (self.days.items) |day| {
			self.allocator.free(day.date);
		}
		self.days.clearRetainingCapacity();

		for (days) |entry| {
			self.days.append(self.allocator, .{
				.date = self.allocator.dupe(u8, json.textAt(entry, "date")) catch continue,
				.level = json.integer(json.field(entry, "level")),
				.count = json.integer(json.field(entry, "count")),
			}) catch continue;
		}
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn fetch(self: *Github) void {
		const candidates = self.identity();
		defer {
			for (candidates) |candidate| self.allocator.free(candidate);
			self.allocator.free(candidates);
		}

		if (candidates.len == 0) {
			self.setStatus("no GitHub user");
			return;
		}

		var login: []const u8 = "";
		var parsed: Contributions = undefined;

		for (candidates) |candidate| {
			const url = std.fmt.allocPrint(self.allocator, "https://github.com/users/{s}/contributions", .{candidate}) catch continue;
			defer self.allocator.free(url);

			const reply = self.http.get(self.allocator, url, null, &.{}) catch continue;
			defer reply.deinit(self.allocator);

			if (!reply.ok()) continue;

			parsed = parseContributions(self.allocator, reply.body) catch continue;
			if (parsed.days.items.len == 0) {
				parsed.days.deinit(self.allocator);
				continue;
			}

			login = candidate;
			break;
		}

		if (login.len == 0) {
			self.setStatus("no response");
			return;
		}

		self.mutex.lockUncancelable(self.io);
		setStr(self.allocator, &self.login, login) catch {};
		self.mutex.unlock(self.io);

		self.mutex.lockUncancelable(self.io);
		for (self.days.items) |day| self.allocator.free(day.date);
		self.days.deinit(self.allocator);
		self.days = parsed.days;
		self.total = parsed.total;
		self.fetched = fmt.nowMs(self.io);
		setStr(self.allocator, &self.status, "") catch {};
		self.mutex.unlock(self.io);

		self.save(login);
		self.hub.publish();
	}

	fn setStatus(self: *Github, message: []const u8) void {
		self.mutex.lockUncancelable(self.io);
		setStr(self.allocator, &self.status, message) catch {};
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn identity(self: *Github) [][]u8 {
		const config_dir = std.fmt.allocPrint(self.allocator, "{s}/.config", .{proc.home(self.io, self.allocator)}) catch "";
		defer if (config_dir.len > 0) self.allocator.free(config_dir);

		const email = if (config_dir.len > 0) self.git(&.{ "-C", config_dir, "config", "--get", "user.email" }) else "";
		defer if (email.len > 0) self.allocator.free(email);

		const name = self.git(&.{"config", "--global", "user.name"});
		defer if (name.len > 0) self.allocator.free(name);

		const remote = if (config_dir.len > 0) self.git(&.{ "-C", config_dir, "remote", "get-url", "origin" }) else "";
		defer if (remote.len > 0) self.allocator.free(remote);

		return loginCandidates(self.allocator, email, name, remote) catch &.{};
	}

	fn git(self: *Github, args: []const []const u8) []const u8 {
		var argv: std.ArrayList([]const u8) = .empty;
		defer argv.deinit(self.allocator);

		argv.append(self.allocator, "git") catch return "";
		for (args) |arg| argv.append(self.allocator, arg) catch return "";

		const result = exec.run(self.io, self.allocator, argv.items) catch return "";

		if (result.code != 0) {
			result.deinit(self.allocator);
			return "";
		}

		const trimmed = std.mem.trim(u8, result.out, " \n\r");
		const copy = self.allocator.dupe(u8, trimmed) catch "";
		result.deinit(self.allocator);

		return copy;
	}

	fn save(self: *Github, login: []const u8) void {
		const path = self.cachePath(self.allocator);
		defer self.allocator.free(path);

		std.Io.Dir.cwd().createDirPath(self.io, std.fs.path.dirname(path) orelse ".") catch {};

		var out: std.Io.Writer.Allocating = .init(self.allocator);
		defer out.deinit();

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);
		const arena = self.scratch.allocator();

		var days: std.ArrayListUnmanaged(DayOut) = .empty;
		for (self.days.items) |day| {
			days.append(arena, .{ .date = day.date, .level = day.level, .count = day.count }) catch {};
		}

		out.writer.print("{{\"login\":\"{s}\",\"total\":{d},\"fetched\":{d},\"days\":{f}}}", .{
			login,
			self.total,
			self.fetched,
			std.json.fmt(days.items, .{}),
		}) catch return;

		proc.writeFileAtomic(self.io, self.allocator, path, out.written()) catch {};
	}

	fn render(self: *Github, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);
		const arena = self.scratch.allocator();

		var days: std.ArrayListUnmanaged(DayOut) = .empty;
		for (self.days.items) |day| {
			try days.append(arena, .{ .date = day.date, .level = day.level, .count = day.count });
		}

		var level_ink: std.ArrayListUnmanaged([]const u8) = .empty;
		for (0..5) |level| {
			var buffer: [7]u8 = undefined;

			try level_ink.append(arena, try arena.dupe(u8, color.hex(&buffer, color.mix(self.empty_ink, self.base_ink, @as(f64, @floatFromInt(level)) / 4))));
		}

		if (fmt.nowMs(self.io) - self.offset_at > localtime.refresh_ms) {
			self.offset_at = fmt.nowMs(self.io);
			self.offset_ms = localtime.offsetMs(self.io, self.allocator) orelse self.offset_ms;
		}

		const today = localtime.epochDay(self.io, self.offset_ms);
		const grid = try contribGrid(arena, days.items, self.weeks, today);
		const here = dayOn(days.items, today);

		const out = Out{
			.levelInk = level_ink.items,
			.login = self.login,
			.total = self.total,
			.fetched = self.fetched,
			.status = self.status,
			.days = days.items,
			.grid = grid,
			.todayCount = if (here) |day| day.count else 0,
			.todayLevel = if (here) |day| day.level else 0,
		};

		try writer.print("{f}", .{std.json.fmt(out, .{})});
	}
};

fn dayNumber(date: []const u8) ?i64 {
	if (date.len != 10 or date[4] != '-' or date[7] != '-') return null;

	const year = std.fmt.parseInt(i64, date[0..4], 10) catch return null;
	const month = std.fmt.parseInt(i64, date[5..7], 10) catch return null;
	const day = std.fmt.parseInt(i64, date[8..10], 10) catch return null;

	return fmt.daysFromCivil(year, month, day);
}

fn weekIndex(day: i64) i64 {
	return @divFloor(day - 3, 7);
}

fn dayOn(days: []const DayOut, today: i64) ?DayOut {
	for (days) |day| {
		if ((dayNumber(day.date) orelse continue) == today) return day;
	}

	return null;
}

fn contribGrid(arena: Allocator, days: []const DayOut, weeks: usize, today: i64) ![]const ?DayOut {
	const cells = try arena.alloc(?DayOut, weeks * 7);
	@memset(cells, null);

	const last_week = weekIndex(today);

	for (days) |day| {
		const number = dayNumber(day.date) orelse continue;
		if (number > today) continue;

		const back = last_week - weekIndex(number);
		if (back >= weeks) continue;

		const col = weeks - 1 - @as(usize, @intCast(back));
		const row: usize = @intCast(@mod(number + 4, 7));

		cells[row * weeks + col] = day;
	}

	return cells;
}

test "the grid puts today in the last column on its weekday row" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const days = [_]DayOut{
		.{ .date = "2026-10-28", .level = 2, .count = 5 },
		.{ .date = "2026-10-29", .level = 4, .count = 9 },
		.{ .date = "2026-10-30", .level = 1, .count = 1 },
		.{ .date = "2026-10-20", .level = 3, .count = 3 },
	};
	const today = fmt.daysFromCivil(2026, 10, 29);
	const grid = try contribGrid(arena.allocator(), &days, 3, today);

	try std.testing.expectEqual(@as(usize, 21), grid.len);
	try std.testing.expectEqual(@as(i64, 9), grid[4 * 3 + 2].?.count);
	try std.testing.expectEqual(@as(i64, 5), grid[3 * 3 + 2].?.count);
	try std.testing.expectEqual(@as(i64, 3), grid[2 * 3 + 1].?.count);
	try std.testing.expect(grid[5 * 3 + 2] == null);
	try std.testing.expectEqual(@as(i64, 9), dayOn(&days, today).?.count);
}

const Contributions = struct {
	days: std.ArrayListUnmanaged(Day),
	total: i64,
};

fn parseContributions(allocator: Allocator, html: []const u8) !Contributions {
	var days: std.ArrayListUnmanaged(Day) = .empty;
	errdefer days.deinit(allocator);

	var rest = html;
	while (std.mem.indexOf(u8, rest, "data-date=\"")) |at| {
		rest = rest[at + "data-date=\"".len ..];
		const end = std.mem.indexOfScalar(u8, rest, '"') orelse break;
		const date = rest[0..end];
		if (date.len != 10) continue;

		const chunk_end = std.mem.indexOf(u8, rest, "</td>") orelse rest.len;
		const chunk = rest[0..chunk_end];

		var level: i64 = 0;
		if (std.mem.indexOf(u8, chunk, "data-level=\"")) |level_at| {
			const level_text = chunk[level_at + "data-level=\"".len ..];
			const level_end = std.mem.indexOfScalar(u8, level_text, '"') orelse 0;
			level = std.fmt.parseInt(i64, level_text[0..level_end], 10) catch 0;
		}

		var count: i64 = 0;
		if (std.mem.indexOf(u8, chunk, "<tool-tip")) |tip_at| {
			const tip = chunk[tip_at..];
			if (std.mem.indexOfScalar(u8, tip, '>')) |tip_body_at| {
				const body = tip[tip_body_at + 1 ..];
				const stop = std.mem.indexOf(u8, body, "</tool-tip>") orelse body.len;
				count = firstNumber(body[0..stop]) orelse 0;
			}
		}

		days.append(allocator, .{
			.date = try allocator.dupe(u8, date),
			.level = level,
			.count = count,
		}) catch continue;

		rest = rest[chunk_end..];
	}

	var total: i64 = 0;
	if (std.mem.indexOf(u8, html, "in the last year")) |year_at| {
		const at = std.mem.lastIndexOf(u8, html[0..year_at], "contribution") orelse year_at;
		var end = at;
		while (end > 0 and std.ascii.isWhitespace(html[end - 1])) end -= 1;

		var start = end;
		while (start > 0) : (start -= 1) {
			const byte = html[start - 1];
			if (!std.ascii.isDigit(byte) and byte != ',') break;
		}

		var digits: [24]u8 = undefined;
		var used: usize = 0;
		for (html[start..end]) |byte| {
			if (byte == ',') continue;
			if (used == digits.len) break;
			digits[used] = byte;
			used += 1;
		}

		total = std.fmt.parseInt(i64, digits[0..used], 10) catch 0;
	}

	return .{ .days = days, .total = total };
}

fn firstNumber(text: []const u8) ?i64 {
	var index: usize = 0;
	while (index < text.len and !std.ascii.isDigit(text[index])) : (index += 1) {}
	const start = index;
	while (index < text.len and (std.ascii.isDigit(text[index]) or text[index] == ',')) : (index += 1) {}
	if (start == index) return null;

	var digits: [24]u8 = undefined;
	var used: usize = 0;
	for (text[start..index]) |byte| {
		if (byte == ',') continue;
		digits[used] = byte;
		used += 1;
	}

	return std.fmt.parseInt(i64, digits[0..used], 10) catch null;
}

fn loginCandidates(allocator: Allocator, email: []const u8, name: []const u8, remote: []const u8) ![][]u8 {
	var out: std.ArrayList([]u8) = .empty;
	const suffix = "@users.noreply.github.com";

	const add = struct {
		fn one(list: *std.ArrayList([]u8), allocator_: Allocator, value: []const u8) void {
			if (!usable(value)) return;

			for (list.items) |existing| {
				if (std.mem.eql(u8, existing, value)) return;
			}

			const copy = allocator_.dupe(u8, value) catch return;
			list.append(allocator_, copy) catch allocator_.free(copy);
		}
	}.one;

	if (std.mem.endsWith(u8, email, suffix)) {
		const before = email[0 .. email.len - suffix.len];
		const login = if (std.mem.lastIndexOfScalar(u8, before, '+')) |plus| before[plus + 1 ..] else before;
		add(&out, allocator, login);
	}

	if (remote.len > 0) {
		var trimmed = std.mem.trimEnd(u8, remote, "/");
		if (std.mem.endsWith(u8, trimmed, ".git")) trimmed = trimmed[0 .. trimmed.len - 4];

		if (std.mem.lastIndexOfScalar(u8, trimmed, '/')) |repo| {
			const head = trimmed[0..repo];
			const owner_at = std.mem.lastIndexOfScalar(u8, head, '/') orelse std.mem.lastIndexOfScalar(u8, head, ':') orelse head.len;
			const owner = head[owner_at + 1 ..];
			if (!std.mem.eql(u8, owner, "users")) add(&out, allocator, owner);
		}
	}

	add(&out, allocator, name);

	var lowered: [64]u8 = undefined;
	var used: usize = 0;
	for (name) |byte| {
		if (byte == ' ') continue;
		if (used == lowered.len) break;
		lowered[used] = std.ascii.toLower(byte);
		used += 1;
	}
	add(&out, allocator, lowered[0..used]);

	return out.toOwnedSlice(allocator);
}

fn usable(login: []const u8) bool {
	if (login.len == 0 or login.len > 39) return false;
	if (!std.ascii.isAlphanumeric(login[0])) return false;

	for (login) |byte| {
		if (!std.ascii.isAlphanumeric(byte) and byte != '-') return false;
	}

	return true;
}

test "contributions parse days and total" {
	const html = "<td data-date=\"2026-01-02\" data-level=\"2\"><tool-tip>3 contributions on Jan 2</tool-tip></td>" ++
		"<td data-date=\"2026-01-03\" data-level=\"0\"><tool-tip>No contributions</tool-tip></td>" ++
		"<div>1,234 contributions in the last year</div>";

	var parsed = try parseContributions(std.testing.allocator, html);
	defer {
		for (parsed.days.items) |day| std.testing.allocator.free(day.date);
		parsed.days.deinit(std.testing.allocator);
	}

	try std.testing.expectEqual(@as(usize, 2), parsed.days.items.len);
	try std.testing.expectEqualStrings("2026-01-02", parsed.days.items[0].date);
	try std.testing.expectEqual(@as(i64, 2), parsed.days.items[0].level);
	try std.testing.expectEqual(@as(i64, 3), parsed.days.items[0].count);
	try std.testing.expectEqual(@as(i64, 1234), parsed.total);
}

test "login candidates come from email, remote and name" {
	const allocator = std.testing.allocator;

	const list = try loginCandidates(allocator, "eivordoudo2021@gmail.com", "yyyumeniku", "https://github.com/yumedots/dotfiles.git");
	defer {
		for (list) |item| allocator.free(item);
		allocator.free(list);
	}

	try std.testing.expectEqual(@as(usize, 2), list.len);
	try std.testing.expectEqualStrings("yumedots", list[0]);
	try std.testing.expectEqualStrings("yyyumeniku", list[1]);
}
