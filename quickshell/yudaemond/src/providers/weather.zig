const std = @import("std");
const hubmod = @import("../hub.zig");
const http = @import("../primitives/http.zig");
const json = @import("../primitives/json.zig");
const proc = @import("../primitives/proc.zig");
const sleep = @import("../primitives/sleep.zig");
const config = @import("../primitives/config.zig");
const setStr = @import("opencode.zig").setStr;

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const max_places = 4;
const max_stations = 3;

const Day = struct {
	date: []u8,
	day: []u8,
	code: i64,
	temp_max: []u8,
	temp_min: []u8,
	feels: []u8,
	wind: []u8,
	humidity: []u8,
};

const DayOut = struct {
	date: []const u8,
	day: []const u8,
	code: i64,
	tempMax: []const u8,
	tempMin: []const u8,
	feels: []const u8,
	wind: []const u8,
	humidity: []const u8,
};

const Slot = struct {
	place: []u8 = &.{},
	lat: f64 = 0,
	lon: f64 = 0,
	temp: []u8 = &.{},
	feels: []u8 = &.{},
	wind: []u8 = &.{},
	humidity: []u8 = &.{},
	days: std.ArrayListUnmanaged(Day) = .empty,
	model_code: i64 = -1,
	station_code: i64 = -1,
	failed: bool = false,

	fn code(self: Slot) i64 {
		return if (self.station_code >= 0) self.station_code else self.model_code;
	}
};

const SlotOut = struct {
	place: []const u8,
	temp: []const u8,
	feels: []const u8,
	wind: []const u8,
	humidity: []const u8,
	code: i64,
	stationCode: i64,
	failed: bool,
	days: []DayOut,
};

const Suggest = struct {
	label: []u8,
	lat: f64,
	lon: f64,
};

const SuggestOut = struct {
	label: []const u8,
	lat: f64,
	lon: f64,
};

const Out = struct {
	places: [][]const u8,
	index: usize,
	slots: []SlotOut,
	suggestions: []SuggestOut,
	status: []const u8,
	fetched: i64,
	unit: []const u8,
};

pub const Weather = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	http: *http.Client,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	places: [max_places][]u8 = .{ &.{}, &.{}, &.{}, &.{} },
	slots: [max_places]Slot = .{ .{}, .{}, .{}, .{} },
	index: usize = 0,
	suggestions: std.ArrayListUnmanaged(Suggest) = .empty,
	status: []u8 = &.{},
	fetched: i64 = 0,
	temp_unit: []u8 = &.{},
	wind_unit: []u8 = &.{},
	days_wanted: i64 = 7,
	station_count: i64 = 0,
	refresh_ms: u64 = 120_000,
	default_location: []u8 = &.{},
	stale_after: i64 = 120_000,

	pub fn create(allocator: Allocator, io: Io, hub: *Hub, client: *http.Client) !*Weather {
		const self = try allocator.create(Weather);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.http = client,
			.scratch = std.heap.ArenaAllocator.init(allocator),
		};

		self.loadConfig();

		return self;
	}

	pub fn provider(self: *Weather) hubmod.Provider {
		return .{ .key = "weather", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Weather = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn start(self: *Weather) !void {
		const thread = try std.Thread.spawn(.{}, loop, .{self});
		thread.detach();
	}

	fn loadConfig(self: *Weather) void {
		const cfg = config.Config.load(self.io, self.allocator) catch {
			self.temp_unit = self.allocator.dupe(u8, "celsius") catch &.{};
			return;
		};
		defer cfg.deinit();

		const unit = cfg.string("weatherTempUnit", self.allocator) orelse self.allocator.dupe(u8, "celsius") catch &.{};
		self.temp_unit = @constCast(unit);
		self.wind_unit = if (std.mem.eql(u8, unit, "celsius"))
			self.allocator.dupe(u8, "kmh") catch &.{}
		else
			self.allocator.dupe(u8, "mph") catch &.{};

		self.days_wanted = cfg.integer("weatherDays", 7);
		self.station_count = cfg.integer("weatherStationCount", 0);
		self.refresh_ms = @intFromFloat(cfg.number("weatherRefreshMs", 120_000));
		self.stale_after = @intFromFloat(cfg.number("weatherCacheMs", 120_000));
		self.default_location = cfg.string("weatherLocation", self.allocator) orelse &.{};
	}

	fn placePath(self: *Weather, allocator: Allocator) []const u8 {
		return std.fmt.allocPrint(allocator, "{s}/.config/quickshell/cache/weather/place", .{proc.home(self.io, allocator)}) catch "/nonexistent";
	}

	fn cachePath(self: *Weather, allocator: Allocator) []const u8 {
		return std.fmt.allocPrint(allocator, "{s}/.config/quickshell/cache/weather/current.json", .{proc.home(self.io, allocator)}) catch "/nonexistent";
	}

	fn loop(self: *Weather) void {
		self.loadPlaces();
		self.loadCache();

		self.mutex.lockUncancelable(self.io);
		const focused = self.index;
		self.mutex.unlock(self.io);

		self.refreshAll(focused);

		while (true) {
			sleep.ms(self.refresh_ms);

			self.mutex.lockUncancelable(self.io);
			const current = self.index;
			self.mutex.unlock(self.io);

			self.refreshAll(current);
		}
	}

	fn loadPlaces(self: *Weather) void {
		const path = self.placePath(self.allocator);
		defer self.allocator.free(path);

		const body = proc.readFile(self.io, self.allocator, path) catch "";
		defer if (body.len > 0) self.allocator.free(body);

		var defaults: [max_places][]u8 = .{ &.{}, &.{}, &.{}, &.{} };
		const cfg = config.Config.load(self.io, self.allocator) catch null;

		if (cfg) |loaded| {
			defer loaded.deinit();

			const list = loaded.strings("weatherPlaceDefaults", self.allocator) catch &.{};
			for (list, 0..) |item, i| {
				if (i + 1 >= max_places) break;
				defaults[i + 1] = item;
			}
		}

		var rows: [max_places][]u8 = .{ &.{}, &.{}, &.{}, &.{} };
		var line: usize = 0;
		var it = std.mem.splitScalar(u8, body, '\n');

		while (line < max_places) : (line += 1) {
			const raw = it.next() orelse "";
			const trimmed = std.mem.trim(u8, raw, " \r\t");

			rows[line] = self.allocator.dupe(u8, trimmed) catch &.{};

			if (line > 0 and rows[line].len == 0) {
				rows[line] = defaults[line];
				defaults[line] = &.{};
			}
		}

		for (defaults) |item| if (item.len > 0) self.allocator.free(item);

		self.mutex.lockUncancelable(self.io);
		for (self.places, 0..) |place, i| {
			if (place.len > 0) self.allocator.free(place);
			self.places[i] = rows[i];
		}
		self.index = self.firstFilledLocked();
		self.mutex.unlock(self.io);
	}

	fn firstFilledLocked(self: *Weather) usize {
		for (self.places, 0..) |place, i| {
			if (place.len > 0) return i;
		}

		return 0;
	}

	fn loadCache(self: *Weather) void {
		const path = self.cachePath(self.allocator);
		defer self.allocator.free(path);

		const body = proc.readFile(self.io, self.allocator, path) catch "";
		defer if (body.len > 0) self.allocator.free(body);

		if (body.len == 0) return;

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const parsed = json.parse(arena.allocator(), body) catch return;
		const root = parsed.value;

		if (!std.mem.eql(u8, json.textAt(root, "unit"), self.temp_unit)) return;

		const saved = json.listAt(root, "slots");
		if (saved.len == 0) return;

		self.mutex.lockUncancelable(self.io);

		for (saved, 0..) |entry, i| {
			if (i >= max_places) break;

			const place = json.textAt(entry, "place");
			if (place.len == 0) continue;

			self.slots[i].lat = json.numberAt(entry, "lat");
			self.slots[i].lon = json.numberAt(entry, "lon");
			setStr(self.allocator, &self.slots[i].temp, json.textAt(entry, "temp")) catch {};
			setStr(self.allocator, &self.slots[i].feels, json.textAt(entry, "feels")) catch {};
			setStr(self.allocator, &self.slots[i].wind, json.textAt(entry, "wind")) catch {};
			setStr(self.allocator, &self.slots[i].humidity, json.textAt(entry, "humidity")) catch {};
			self.slots[i].model_code = json.integer(json.field(entry, "modelCode"));
			self.slots[i].station_code = json.integer(json.field(entry, "stationCode"));

			for (self.slots[i].days.items) |day| self.freeDay(day);
			self.slots[i].days.clearRetainingCapacity();

			for (json.listAt(entry, "days")) |row| {
				self.slots[i].days.append(self.allocator, .{
					.date = self.allocator.dupe(u8, json.textAt(row, "date")) catch continue,
					.day = self.allocator.dupe(u8, json.textAt(row, "day")) catch continue,
					.code = json.integer(json.field(row, "code")),
					.temp_max = self.allocator.dupe(u8, json.textAt(row, "tempMax")) catch continue,
					.temp_min = self.allocator.dupe(u8, json.textAt(row, "tempMin")) catch continue,
					.feels = self.allocator.dupe(u8, json.textAt(row, "feels")) catch continue,
					.wind = self.allocator.dupe(u8, json.textAt(row, "wind")) catch continue,
					.humidity = self.allocator.dupe(u8, json.textAt(row, "humidity")) catch continue,
				}) catch continue;
			}
		}

		self.fetched = json.integer(json.field(root, "fetched"));
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn freeDay(self: *Weather, day: Day) void {
		self.allocator.free(day.date);
		self.allocator.free(day.day);
		self.allocator.free(day.temp_max);
		self.allocator.free(day.temp_min);
		self.allocator.free(day.feels);
		self.allocator.free(day.wind);
		self.allocator.free(day.humidity);
	}

	fn refreshAll(self: *Weather, focused: usize) void {
		const total = self.placesLen();

		for (0..total) |i| {
			self.refreshSlot(i);
		}

		if (self.station_count > 0) self.observe(focused);

		self.mutex.lockUncancelable(self.io);
		self.fetched = std.Io.Clock.real.now(self.io).toMilliseconds();
		self.mutex.unlock(self.io);

		self.save();
		self.hub.publish();
	}

	fn placesLen(self: *Weather) usize {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		return max_places;
	}

	fn refreshSlot(self: *Weather, at: usize) void {
		self.mutex.lockUncancelable(self.io);
		const place = self.allocator.dupe(u8, self.places[at]) catch {
			self.mutex.unlock(self.io);
			return;
		};
		const lat = self.slots[at].lat;
		const lon = self.slots[at].lon;
		self.mutex.unlock(self.io);
		defer self.allocator.free(place);

		if (place.len == 0) return;

		var coord = [2]f64{ lat, lon };

		if (coord[0] == 0 and coord[1] == 0) {
			coord = self.geocode(place) orelse {
				self.mutex.lockUncancelable(self.io);
				self.slots[at].failed = true;
				self.mutex.unlock(self.io);
				return;
			};
		}

		const data = self.forecast(coord[0], coord[1]) orelse {
			self.mutex.lockUncancelable(self.io);
			self.slots[at].failed = true;
			self.mutex.unlock(self.io);
			return;
		};

		self.mutex.lockUncancelable(self.io);
		setStr(self.allocator, &self.slots[at].place, place) catch {};
		self.slots[at].lat = coord[0];
		self.slots[at].lon = coord[1];
		self.slots[at].model_code = data.code;
		self.slots[at].failed = false;

		setStr(self.allocator, &self.slots[at].temp, data.temp) catch {};
		setStr(self.allocator, &self.slots[at].feels, data.feels) catch {};
		setStr(self.allocator, &self.slots[at].wind, data.wind) catch {};
		setStr(self.allocator, &self.slots[at].humidity, data.humidity) catch {};

		for (self.slots[at].days.items) |day| self.freeDay(day);
		self.slots[at].days.clearRetainingCapacity();
		for (data.days) |day| self.slots[at].days.append(self.allocator, day) catch {};
		self.mutex.unlock(self.io);
	}

	const Forecast = struct {
		code: i64,
		temp: []u8,
		feels: []u8,
		wind: []u8,
		humidity: []u8,
		days: []Day,
	};

	fn forecast(self: *Weather, lat: f64, lon: f64) ?Forecast {
		const url = std.fmt.allocPrint(self.allocator, "https://api.open-meteo.com/v1/forecast?latitude={d}&longitude={d}" ++
			"&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,weather_code,precipitation" ++
			"&daily=weather_code,temperature_2m_max,temperature_2m_min,apparent_temperature_max,wind_speed_10m_max,relative_humidity_2m_mean" ++
			"&temperature_unit={s}&wind_speed_unit={s}&forecast_days={d}&timezone=auto", .{ lat, lon, self.temp_unit, self.wind_unit, self.days_wanted }) catch return null;
		defer self.allocator.free(url);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const parsed = self.http.getJson(arena.allocator(), url, null, &.{}) catch return null;
		const root = parsed.value;
		const current = json.field(root, "current") orelse return null;

		const units = json.field(root, "current_units") orelse json.Value{ .null = {} };
		var temp_label = json.textAt(units, "temperature_2m");
		if (temp_label.len == 0) temp_label = if (std.mem.eql(u8, self.temp_unit, "celsius")) "\u{00b0}c" else "\u{00b0}F";

		var wind_label = json.textAt(units, "wind_speed_10m");
		if (wind_label.len == 0) wind_label = "km/h";

		const code = @as(i64, @intFromFloat(@round(json.numberAt(current, "weather_code"))));
		const precip = json.numberAt(current, "precipitation");

		var days: std.ArrayList(Day) = .empty;
		const daily = json.field(root, "daily") orelse json.Value{ .null = {} };

		for (json.listAt(daily, "time"), 0..) |entry, i| {
			const stamp = json.text(entry);
			const row_code = value_at(daily, "weather_code", i);
			const apparent = value_at(daily, "apparent_temperature_max", i);
			const wind_max = value_at(daily, "wind_speed_10m_max", i);
			const humidity_mean = value_at(daily, "relative_humidity_2m_mean", i);

			days.append(self.allocator, .{
				.date = self.allocator.dupe(u8, stamp) catch continue,
				.day = self.allocator.dupe(u8, dayLabel(stamp)) catch continue,
				.code = @as(i64, @intFromFloat(@round(row_code))),
				.temp_max = self.tempText(value_at(daily, "temperature_2m_max", i), temp_label) catch continue,
				.temp_min = self.tempText(value_at(daily, "temperature_2m_min", i), temp_label) catch continue,
				.feels = self.tempText(apparent, temp_label) catch continue,
				.wind = std.fmt.allocPrint(self.allocator, "{d} {s}", .{ @as(i64, @intFromFloat(@round(wind_max))), wind_label }) catch continue,
				.humidity = std.fmt.allocPrint(self.allocator, "{d}%", .{@as(i64, @intFromFloat(@round(humidity_mean)))}) catch continue,
			}) catch continue;
		}

		return .{
			.code = if (precip > 0 and code <= 48) 61 else code,
			.temp = self.tempText(json.numberAt(current, "temperature_2m"), temp_label) catch return null,
			.feels = self.tempText(json.numberAt(current, "apparent_temperature"), temp_label) catch return null,
			.wind = std.fmt.allocPrint(self.allocator, "{d} {s}", .{ @as(i64, @intFromFloat(@round(json.numberAt(current, "wind_speed_10m")))), wind_label }) catch return null,
			.humidity = std.fmt.allocPrint(self.allocator, "{d}%", .{@as(i64, @intFromFloat(@round(json.numberAt(current, "relative_humidity_2m"))))}) catch return null,
			.days = days.items,
		};
	}

	fn tempText(self: *Weather, value: f64, label: []const u8) ![]u8 {
		return std.fmt.allocPrint(self.allocator, "{d}{s}", .{ @as(i64, @intFromFloat(@round(value))), label });
	}

	fn geocode(self: *Weather, place: []const u8) ?[2]f64 {
		const city = std.mem.trim(u8, place[0 .. (std.mem.indexOfScalar(u8, place, ',') orelse place.len)], " ");

		const escaped = http.encodeQuery(self.allocator, city) catch return null;
		defer self.allocator.free(escaped);

		const target = std.fmt.allocPrint(self.allocator, "https://geocoding-api.open-meteo.com/v1/search?name={s}&count=1&language=en&format=json", .{escaped}) catch return null;
		defer self.allocator.free(target);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const parsed = self.http.getJson(arena.allocator(), target, null, &.{}) catch return null;
		const rows = json.listAt(parsed.value, "results");
		if (rows.len == 0) return null;

		return .{ json.numberAt(rows[0], "latitude"), json.numberAt(rows[0], "longitude") };
	}

	pub fn search(self: *Weather, query: []const u8) void {
		const escaped = http.encodeQuery(self.allocator, std.mem.trim(u8, query, " ")) catch return;
		defer self.allocator.free(escaped);

		const target = std.fmt.allocPrint(self.allocator, "https://geocoding-api.open-meteo.com/v1/search?name={s}&count=20&language=en&format=json", .{escaped}) catch return;
		defer self.allocator.free(target);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const parsed = self.http.getJson(arena.allocator(), target, null, &.{}) catch return;

		var next: std.ArrayListUnmanaged(Suggest) = .empty;

		for (json.listAt(parsed.value, "results")) |entry| {
			const name = json.textAt(entry, "name");
			if (name.len == 0) continue;

			const region = json.textAt(entry, "admin1");
			const label = if (region.len > 0)
				std.fmt.allocPrint(self.allocator, "{s}, {s}", .{ name, region }) catch continue
			else
				self.allocator.dupe(u8, name) catch continue;

			next.append(self.allocator, .{
				.label = label,
				.lat = json.numberAt(entry, "latitude"),
				.lon = json.numberAt(entry, "longitude"),
			}) catch continue;
		}

		self.mutex.lockUncancelable(self.io);
		for (self.suggestions.items) |item| self.allocator.free(item.label);
		self.suggestions.deinit(self.allocator);
		self.suggestions = next;
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	pub fn shift(self: *Weather, step: i64) void {
		self.mutex.lockUncancelable(self.io);

		const from = self.index;
		var next = from;

		for (1..max_places) |i| {
			const offset: i64 = if (step < 0) -@as(i64, @intCast(i)) else @as(i64, @intCast(i));
			const at: usize = @intCast(@mod(@as(i64, @intCast(from)) + offset, max_places));

			if (self.places[at].len > 0) {
				next = at;
				break;
			}
		}

		self.index = next;
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	pub fn focus(self: *Weather, at: usize) void {
		if (at >= max_places) return;

		self.mutex.lockUncancelable(self.io);
		self.index = at;
		self.mutex.unlock(self.io);

		self.refreshSlot(at);
		self.hub.publish();
	}

	pub fn choose(self: *Weather, label: []const u8, lat: f64, lon: f64) void {
		if (label.len == 0) return;

		self.mutex.lockUncancelable(self.io);
		const at = self.index;
		setStr(self.allocator, &self.places[at], label) catch {};
		self.slots[at].lat = lat;
		self.slots[at].lon = lon;
		self.slots[at].failed = false;
		self.mutex.unlock(self.io);

		for (self.suggestions.items) |item| self.allocator.free(item.label);
		self.suggestions.deinit(self.allocator);
		self.suggestions = .empty;

		self.storePlaces();
		self.refreshSlot(at);
		self.hub.publish();
	}

	pub fn add(self: *Weather, label: []const u8, lat: f64, lon: f64) void {
		if (label.len == 0) return;

		self.mutex.lockUncancelable(self.io);

		var at: usize = self.index;
		for (self.places, 0..) |place, i| {
			if (place.len == 0) {
				at = i;
				break;
			}
		}

		setStr(self.allocator, &self.places[at], label) catch {};
		self.slots[at].lat = lat;
		self.slots[at].lon = lon;
		self.index = at;
		self.mutex.unlock(self.io);

		self.storePlaces();
		self.refreshSlot(at);
		self.hub.publish();
	}

	pub fn dismissSuggestions(self: *Weather) void {
		self.mutex.lockUncancelable(self.io);
		for (self.suggestions.items) |item| self.allocator.free(item.label);
		self.suggestions.deinit(self.allocator);
		self.suggestions = .empty;
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn storePlaces(self: *Weather) void {
		const path = self.placePath(self.allocator);
		defer self.allocator.free(path);

		std.Io.Dir.cwd().createDirPath(self.io, std.fs.path.dirname(path) orelse ".") catch {};

		var out: std.Io.Writer.Allocating = .init(self.allocator);
		defer out.deinit();

		self.mutex.lockUncancelable(self.io);
		for (self.places) |place| out.writer.print("{s}\n", .{place}) catch {};
		self.mutex.unlock(self.io);

		proc.writeFileAtomic(self.io, self.allocator, path, out.written()) catch {};
	}

	fn save(self: *Weather) void {
		const path = self.cachePath(self.allocator);
		defer self.allocator.free(path);

		std.Io.Dir.cwd().createDirPath(self.io, std.fs.path.dirname(path) orelse ".") catch {};

		var out: std.Io.Writer.Allocating = .init(self.allocator);
		defer out.deinit();

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);
		const arena = self.scratch.allocator();

		var saved: std.ArrayListUnmanaged(SlotOut) = .empty;
		for (self.slots) |slot| {
			var days: std.ArrayListUnmanaged(DayOut) = .empty;
			for (slot.days.items) |day| {
				days.append(arena, .{
					.date = day.date,
					.day = day.day,
					.code = day.code,
					.tempMax = day.temp_max,
					.tempMin = day.temp_min,
					.feels = day.feels,
					.wind = day.wind,
					.humidity = day.humidity,
				}) catch {};
			}

			saved.append(arena, .{
				.place = slot.place,
				.temp = slot.temp,
				.feels = slot.feels,
				.wind = slot.wind,
				.humidity = slot.humidity,
				.code = slot.code(),
				.stationCode = slot.station_code,
				.failed = slot.failed,
				.days = days.items,
			}) catch {};
		}

		out.writer.print("{{\"unit\":\"{s}\",\"fetched\":{d},\"slots\":{f}}}", .{
			self.temp_unit,
			self.fetched,
			std.json.fmt(saved.items, .{}),
		}) catch return;

		proc.writeFileAtomic(self.io, self.allocator, path, out.written()) catch {};
	}

	fn observe(self: *Weather, at: usize) void {
		self.mutex.lockUncancelable(self.io);
		const lat = self.slots[at].lat;
		const lon = self.slots[at].lon;
		const place = self.allocator.dupe(u8, self.places[at]) catch {
			self.mutex.unlock(self.io);
			return;
		};
		self.mutex.unlock(self.io);
		defer self.allocator.free(place);

		if (place.len == 0 or lat == 0 or lon == 0) return;

		const code = self.observationCode(lat, lon) orelse return;

		self.mutex.lockUncancelable(self.io);
		self.slots[at].station_code = code;
		self.mutex.unlock(self.io);
	}

	fn observationCode(self: *Weather, lat: f64, lon: f64) ?i64 {
		const user_agent = [_]std.http.Header{.{ .name = "User-Agent", .value = "quickshell-weather (weather@example.com)" }};

		const points_url = std.fmt.allocPrint(self.allocator, "https://api.weather.gov/points/{d},{d}", .{ lat, lon }) catch return null;
		defer self.allocator.free(points_url);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const points = self.http.getJson(arena.allocator(), points_url, null, &user_agent) catch return null;
		const stations_url = json.textDeep(points.value, &.{ "properties", "observationStations" });
		if (stations_url.len == 0) return null;

		const stations = self.http.getJson(arena.allocator(), stations_url, null, &user_agent) catch return null;

		const ids = nearestStations(arena.allocator(), stations.value, lat, lon, self.station_count) catch return null;

		for (ids) |id| {
			const url = std.fmt.allocPrint(arena.allocator(), "https://api.weather.gov/stations/{s}/observations/latest", .{id}) catch continue;
			const observation = self.http.getJson(arena.allocator(), url, null, &user_agent) catch continue;

			const text = json.textDeep(observation.value, &.{ "properties", "textDescription" });
			const code = codeFromText(text);
			if (code >= 0) return code;
		}

		return null;
	}

	fn render(self: *Weather, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);
		const arena = self.scratch.allocator();

		var places: std.ArrayListUnmanaged([]const u8) = .empty;
		for (self.places) |place| try places.append(arena, place);

		var slots: std.ArrayListUnmanaged(SlotOut) = .empty;
		for (self.slots) |slot| {
			var days: std.ArrayListUnmanaged(DayOut) = .empty;
			for (slot.days.items) |day| {
				try days.append(arena, .{
					.date = day.date,
					.day = day.day,
					.code = day.code,
					.tempMax = day.temp_max,
					.tempMin = day.temp_min,
					.feels = day.feels,
					.wind = day.wind,
					.humidity = day.humidity,
				});
			}

			try slots.append(arena, .{
				.place = slot.place,
				.temp = slot.temp,
				.feels = slot.feels,
				.wind = slot.wind,
				.humidity = slot.humidity,
				.code = slot.code(),
				.stationCode = slot.station_code,
				.failed = slot.failed,
				.days = days.items,
			});
		}

		var suggestions: std.ArrayListUnmanaged(SuggestOut) = .empty;
		for (self.suggestions.items) |item| {
			try suggestions.append(arena, .{ .label = item.label, .lat = item.lat, .lon = item.lon });
		}

		const out = Out{
			.places = places.items,
			.index = self.index,
			.slots = slots.items,
			.suggestions = suggestions.items,
			.status = self.status,
			.fetched = self.fetched,
			.unit = self.temp_unit,
		};

		try writer.print("{f}", .{std.json.fmt(out, .{})});
	}
};

fn value_at(value: json.Value, key: []const u8, index: usize) f64 {
	const rows = json.listAt(value, key);
	if (index >= rows.len) return 0;

	return json.number(rows[index]);
}

fn dayLabel(date: []const u8) []const u8 {
	if (date.len < 10) return "";

	const year = std.fmt.parseInt(i64, date[0..4], 10) catch return "";
	const month = std.fmt.parseInt(i64, date[5..7], 10) catch return "";
	const day = std.fmt.parseInt(i64, date[8..10], 10) catch return "";

	if (month < 1 or month > 12 or day < 1 or day > 31) return "";

	const days = daysFromCivil(year, month, day);
	const weekday: usize = @intCast(@mod(days + 4, 7));

	const names = [_][]const u8{ "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" };

	return names[weekday];
}

fn daysFromCivil(year: i64, month: i64, day: i64) i64 {
	const y = if (month <= 2) year - 1 else year;
	const era = @divFloor(y, 400);
	const yoe = y - era * 400;
	const mp = @mod(month + 9, 12);
	const doy = @divFloor(153 * mp + 2, 5) + day - 1;
	const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;

	return era * 146097 + doe - 719468;
}

fn nearestStations(allocator: Allocator, stations: json.Value, lat: f64, lon: f64, count: i64) ![][]const u8 {
	const Row = struct { id: []const u8, distance: f64 };
	var rows: std.ArrayList(Row) = .empty;

	for (json.listAt(stations, "features")) |feature| {
		const id = json.textDeep(feature, &.{ "properties", "stationIdentifier" });
		if (id.len == 0) continue;

		const coords = json.list(json.deep(feature, &.{ "geometry", "coordinates" }));
		if (coords.len < 2) continue;

		const station_lon = json.number(coords[0]);
		const station_lat = json.number(coords[1]);
		const dx = (station_lon - lon) * 0.9;
		const dy = station_lat - lat;

		try rows.append(allocator, .{ .id = id, .distance = dx * dx + dy * dy });
	}

	std.mem.sort(Row, rows.items, {}, struct {
		fn less(_: void, a: Row, b: Row) bool {
			return a.distance < b.distance;
		}
	}.less);

	var out: std.ArrayList([]const u8) = .empty;
	const wanted: usize = @intCast(@max(0, @min(count, 10)));

	for (rows.items[0..@min(wanted, rows.items.len)]) |row| try out.append(allocator, row.id);

	return out.toOwnedSlice(allocator);
}

fn codeFromText(text: []const u8) i64 {
	var lower: [128]u8 = undefined;
	const length = @min(text.len, lower.len);

	for (text[0..length], 0..) |byte, i| lower[i] = std.ascii.toLower(byte);
	const line = lower[0..length];

	if (line.len == 0) return -1;
	if (std.mem.indexOf(u8, line, "thunder") != null) return 95;
	if (std.mem.indexOf(u8, line, "hail") != null) return 96;
	if (std.mem.indexOf(u8, line, "freezing") != null or std.mem.indexOf(u8, line, "sleet") != null) return 66;
	if (std.mem.indexOf(u8, line, "heavy rain") != null) return 65;
	if (std.mem.indexOf(u8, line, "rain") != null or std.mem.indexOf(u8, line, "drizzle") != null) return 61;
	if (std.mem.indexOf(u8, line, "heavy snow") != null or std.mem.indexOf(u8, line, "blizzard") != null) return 75;
	if (std.mem.indexOf(u8, line, "snow") != null) return 71;
	if (std.mem.indexOf(u8, line, "fog") != null or std.mem.indexOf(u8, line, "mist") != null) return 45;
	if (std.mem.indexOf(u8, line, "partly") != null or std.mem.indexOf(u8, line, "mostly sunny") != null) return 2;
	if (std.mem.indexOf(u8, line, "overcast") != null or std.mem.indexOf(u8, line, "cloudy") != null) return 3;
	if (std.mem.indexOf(u8, line, "clear") != null or std.mem.indexOf(u8, line, "sunny") != null) return 0;

	return -1;
}

test "day labels follow the date" {
	try std.testing.expectEqualStrings("SAT", dayLabel("2026-10-24"));
	try std.testing.expectEqualStrings("SUN", dayLabel("2026-10-25"));
	try std.testing.expectEqualStrings("", dayLabel("x"));
}

test "weather text maps to codes" {
	try std.testing.expectEqual(@as(i64, 61), codeFromText("Light Rain"));
	try std.testing.expectEqual(@as(i64, 0), codeFromText("Clear"));
	try std.testing.expectEqual(@as(i64, -1), codeFromText(""));
}
