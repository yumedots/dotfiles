const std = @import("std");
const hubmod = @import("../hub.zig");
const http = @import("../primitives/http.zig");
const json = @import("../primitives/json.zig");
const proc = @import("../primitives/proc.zig");
const sleep = @import("../primitives/sleep.zig");
const config = @import("../primitives/config.zig");
const setStr = @import("opencode.zig").setStr;
const fmt = @import("../primitives/fmt.zig");

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
	text: []const u8,
	glyph: []const u8,
	temps: []const u8,
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
	text: []const u8,
	glyph: []const u8,
	tempValue: []const u8,
	tempUnit: []const u8,
	stationCode: i64,
	failed: bool,
	days: []DayOut,
};

const Suggest = struct {
	label: []u8,
	name: []u8,
	lat: f64,
	lon: f64,
	population: i64 = 0,
};

const SuggestOut = struct {
	label: []const u8,
	name: []const u8,
	region: []const u8,
	lat: f64,
	lon: f64,
};

const Out = struct {
	places: [][]const u8,
	index: usize,
	slots: []SlotOut,
	suggestions: []SuggestOut,
	rows: []SuggestOut,
	ghost: []const u8,
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
	query: []u8 = &.{},
	search_gen: std.atomic.Value(u64) = .init(0),
	debounce_ms: u64 = 60,
	status: []u8 = &.{},
	fetched: i64 = 0,
	temp_unit: []u8 = &.{},
	wind_unit: []u8 = &.{},
	days_wanted: i64 = 7,
	station_count: i64 = 0,
	refresh_ms: u64 = 120_000,
	default_location: []u8 = &.{},
	stale_after: i64 = 120_000,
	codes: []const config.CodeRow = &.{},

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
		self.debounce_ms = @intCast(@max(0, cfg.integer("weatherCardSearchDebounce", 60)));
		self.stale_after = @intFromFloat(cfg.number("weatherCacheMs", 120_000));
		self.default_location = cfg.string("weatherLocation", self.allocator) orelse &.{};
		self.codes = cfg.codeTable("weatherCodes", self.allocator) catch &.{};
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
		const region = regionOf(place, city);

		const escaped = http.encodeQuery(self.allocator, city) catch return null;
		defer self.allocator.free(escaped);

		const target = std.fmt.allocPrint(self.allocator, "https://geocoding-api.open-meteo.com/v1/search?name={s}&count=10&language=en&format=json", .{escaped}) catch return null;
		defer self.allocator.free(target);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const parsed = self.http.getJson(arena.allocator(), target, null, &.{}) catch return null;
		const row = pickRegion(json.listAt(parsed.value, "results"), region) orelse return null;

		return .{ json.numberAt(row, "latitude"), json.numberAt(row, "longitude") };
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
				.name = self.allocator.dupe(u8, name) catch continue,
				.lat = json.numberAt(entry, "latitude"),
				.lon = json.numberAt(entry, "longitude"),
				.population = json.integer(json.field(entry, "population")),
			}) catch continue;
		}

		std.mem.sort(Suggest, next.items, {}, struct {
			fn bigger(_: void, a: Suggest, b: Suggest) bool {
				return a.population > b.population;
			}
		}.bigger);

		self.mutex.lockUncancelable(self.io);
		for (self.suggestions.items) |item| {
			self.allocator.free(item.label);
			self.allocator.free(item.name);
		}
		self.suggestions.deinit(self.allocator);
		self.suggestions = next;
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	pub fn setQuery(self: *Weather, query: []const u8) void {
		self.mutex.lockUncancelable(self.io);
		setStr(self.allocator, &self.query, query) catch {};

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const typed = std.mem.trim(u8, query, " \r\t");
		const covered = matchRows(arena.allocator(), self.suggestions.items, query).rows.len > 0;
		const stale = self.suggestions.items.len > 0;
		self.mutex.unlock(self.io);

		self.hub.publish();

		const gen = self.search_gen.fetchAdd(1, .monotonic) + 1;

		if (typed.len == 0) {
			if (stale) self.dismissSuggestions();
			return;
		}

		if (covered or typed.len < 3) return;

		const copy = self.allocator.dupe(u8, query) catch return;
		const thread = std.Thread.spawn(.{}, debounced, .{ self, copy, gen }) catch {
			self.allocator.free(copy);
			return;
		};
		thread.detach();
	}

	fn debounced(self: *Weather, query: []u8, gen: u64) void {
		defer self.allocator.free(query);

		sleep.ms(self.debounce_ms);

		if (self.search_gen.load(.monotonic) != gen) return;

		self.search(query);
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
		if (!usablePlace(label)) return;

		self.mutex.lockUncancelable(self.io);
		const at = self.index;
		setStr(self.allocator, &self.places[at], label) catch {};
		self.slots[at].lat = lat;
		self.slots[at].lon = lon;
		self.slots[at].failed = false;
		self.mutex.unlock(self.io);

		for (self.suggestions.items) |item| {
			self.allocator.free(item.label);
			self.allocator.free(item.name);
		}
		self.suggestions.deinit(self.allocator);
		self.suggestions = .empty;

		self.storePlaces();
		self.refreshSlot(at);
		self.hub.publish();
	}

	pub fn add(self: *Weather, label: []const u8, lat: f64, lon: f64) void {
		if (!usablePlace(label)) return;

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
		for (self.suggestions.items) |item| {
			self.allocator.free(item.label);
			self.allocator.free(item.name);
		}
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
				const info = describe(self.codes, day.code);

				days.append(arena, .{
					.date = day.date,
					.day = day.day,
					.code = day.code,
					.text = info.text,
					.glyph = info.glyph,
					.temps = dayTemps(arena, day),
					.tempMax = day.temp_max,
					.tempMin = day.temp_min,
					.feels = day.feels,
					.wind = day.wind,
					.humidity = day.humidity,
				}) catch {};
			}

			const code = slot.code();
			const info = describe(self.codes, code);

			saved.append(arena, .{
				.place = slot.place,
				.temp = slot.temp,
				.feels = slot.feels,
				.wind = slot.wind,
				.humidity = slot.humidity,
				.code = code,
				.text = info.text,
				.glyph = info.glyph,
				.tempValue = splitTemp(slot.temp).value,
				.tempUnit = splitTemp(slot.temp).unit,
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
				const info = describe(self.codes, day.code);

				try days.append(arena, .{
					.date = day.date,
					.day = day.day,
					.code = day.code,
					.text = info.text,
					.glyph = info.glyph,
					.temps = dayTemps(arena, day),
					.tempMax = day.temp_max,
					.tempMin = day.temp_min,
					.feels = day.feels,
					.wind = day.wind,
					.humidity = day.humidity,
				});
			}

			const code = slot.code();
			const info = describe(self.codes, code);

			try slots.append(arena, .{
				.place = slot.place,
				.temp = slot.temp,
				.feels = slot.feels,
				.wind = slot.wind,
				.humidity = slot.humidity,
				.code = code,
				.text = info.text,
				.glyph = info.glyph,
				.tempValue = splitTemp(slot.temp).value,
				.tempUnit = splitTemp(slot.temp).unit,
				.stationCode = slot.station_code,
				.failed = slot.failed,
				.days = days.items,
			});
		}

		var suggestions: std.ArrayListUnmanaged(SuggestOut) = .empty;
		for (self.suggestions.items) |item| {
			try suggestions.append(arena, .{ .label = item.label, .name = item.name, .region = regionOf(item.label, item.name), .lat = item.lat, .lon = item.lon });
		}

		const matches = matchRows(arena, self.suggestions.items, self.query);

		const out = Out{
			.places = places.items,
			.index = self.index,
			.slots = slots.items,
			.suggestions = suggestions.items,
			.rows = matches.rows,
			.ghost = matches.ghost,
			.status = self.status,
			.fetched = self.fetched,
			.unit = self.temp_unit,
		};

		try writer.print("{f}", .{std.json.fmt(out, .{})});
	}
};

const Info = struct {
	text: []const u8 = "",
	glyph: []const u8 = "",
};

const Split = struct {
	value: []const u8 = "",
	unit: []const u8 = "",
};

fn splitTemp(text: []const u8) Split {
	const trimmed = std.mem.trim(u8, text, " ");

	var end: usize = 0;
	if (end < trimmed.len and (trimmed[end] == '+' or trimmed[end] == '-')) end += 1;

	var digits: usize = 0;
	while (end < trimmed.len and (std.ascii.isDigit(trimmed[end]) or trimmed[end] == '.')) : (end += 1) {
		if (trimmed[end] != '.') digits += 1;
	}

	if (digits == 0) return .{ .value = trimmed };

	return .{ .value = trimmed[0..end], .unit = std.mem.trim(u8, trimmed[end..], " ") };
}

fn dayTemps(arena: std.mem.Allocator, day: Day) []const u8 {
	return std.fmt.allocPrint(arena, "{s}\u{00b0} {s}\u{00b0}", .{ splitTemp(day.temp_max).value, splitTemp(day.temp_min).value }) catch "";
}

fn describe(codes: []const config.CodeRow, code: i64) Info {
	for (codes) |row| {
		if (row.code == code) return .{ .text = row.name, .glyph = row.glyph };
	}

	return .{};
}

const Matches = struct {
	rows: []SuggestOut,
	ghost: []const u8,
};

fn matchRows(arena: Allocator, items: []const Suggest, query: []const u8) Matches {
	const typed = std.mem.trim(u8, query, " \r\t");
	const lowered = std.ascii.allocLowerString(arena, typed) catch return .{ .rows = &.{}, .ghost = "" };

	var rows: std.ArrayListUnmanaged(SuggestOut) = .empty;

	for (items) |item| {
		if (rows.items.len >= 5) break;

		if (lowered.len > 0) {
			const label = std.ascii.allocLowerString(arena, item.label) catch continue;
			if (!std.mem.startsWith(u8, label, lowered)) continue;
		}

		rows.append(arena, .{ .label = item.label, .name = item.name, .region = regionOf(item.label, item.name), .lat = item.lat, .lon = item.lon }) catch break;
	}

	if (rows.items.len == 0 or query.len == 0) return .{ .rows = rows.items, .ghost = "" };

	const raw = std.ascii.allocLowerString(arena, query) catch return .{ .rows = rows.items, .ghost = "" };
	const name = std.ascii.allocLowerString(arena, rows.items[0].name) catch return .{ .rows = rows.items, .ghost = "" };

	if (!std.mem.startsWith(u8, name, raw)) return .{ .rows = rows.items, .ghost = "" };

	return .{ .rows = rows.items, .ghost = rows.items[0].name[query.len..] };
}

fn pickRegion(rows: []const json.Value, region: []const u8) ?json.Value {
	if (rows.len == 0) return null;
	if (region.len == 0) return rows[0];

	for (rows) |row| {
		if (std.ascii.eqlIgnoreCase(json.textAt(row, "admin1"), region)) return row;
		if (std.ascii.eqlIgnoreCase(json.textAt(row, "country"), region)) return row;
	}

	return rows[0];
}

fn regionOf(label: []const u8, name: []const u8) []const u8 {
	if (name.len == 0 or !std.mem.startsWith(u8, label, name)) return "";

	return std.mem.trimStart(u8, label[name.len..], ", \t");
}

test "geocoding picks the row in the labelled region" {
	const body =
		\\{"results":[{"name":"Palm Springs","admin1":"California","country":"United States","latitude":33.8,"longitude":-116.5},{"name":"Palm Springs","admin1":"Florida","country":"United States","latitude":26.6,"longitude":-80.1}]}
	;
	const parsed = try json.parse(std.testing.allocator, body);
	defer parsed.deinit();
	const rows = json.listAt(parsed.value, "results");

	try std.testing.expectEqual(@as(f64, 26.6), json.numberAt(pickRegion(rows, "Florida").?, "latitude"));
	try std.testing.expectEqual(@as(f64, 33.8), json.numberAt(pickRegion(rows, "").?, "latitude"));
	try std.testing.expectEqual(@as(f64, 33.8), json.numberAt(pickRegion(rows, "Texas").?, "latitude"));
}

test "the region is what follows the name in the label" {
	try std.testing.expectEqualStrings("Paris", regionOf("Paris, Paris", "Paris")[0..5]);
	try std.testing.expectEqualStrings("Texas", regionOf("Paris, Texas", "Paris"));
	try std.testing.expectEqualStrings("", regionOf("Paris", "Paris"));
	try std.testing.expectEqualStrings("", regionOf("Rome", "Paris"));
}

fn usablePlace(label: []const u8) bool {
	var count: usize = 0;

	for (label) |byte| {
		if (byte != ' ') count += 1;
	}

	return count >= 2 and std.mem.trim(u8, label, " ").len > 0;
}

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

	const names = [_][]const u8{ "SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT" };

	return names[fmt.weekdayIndex(year, month, day)];
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

test "temps split into value and unit" {
	const split = splitTemp("82\u{00b0}F");
	try std.testing.expectEqualStrings("82", split.value);
	try std.testing.expectEqualStrings("\u{00b0}F", split.unit);

	const negative = splitTemp("-3 \u{00b0}c");
	try std.testing.expectEqualStrings("-3", negative.value);
	try std.testing.expectEqualStrings("\u{00b0}c", negative.unit);

	const blank = splitTemp("");
	try std.testing.expectEqualStrings("", blank.value);
	try std.testing.expectEqualStrings("", blank.unit);
}

test "suggestions match the query best first and complete it" {
	var state = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer state.deinit();
	const arena = state.allocator();

	const items = [_]Suggest{
		.{ .label = @constCast("Paris, Ile-de-France"), .name = @constCast("Paris"), .lat = 1, .lon = 2 },
		.{ .label = @constCast("Parma, Emilia-Romagna"), .name = @constCast("Parma"), .lat = 3, .lon = 4 },
		.{ .label = @constCast("Berlin, Berlin"), .name = @constCast("Berlin"), .lat = 5, .lon = 6 },
	};

	const par = matchRows(arena, &items, "par");
	try std.testing.expectEqual(@as(usize, 2), par.rows.len);
	try std.testing.expectEqualStrings("Paris, Ile-de-France", par.rows[0].label);
	try std.testing.expectEqualStrings("Parma, Emilia-Romagna", par.rows[1].label);
	try std.testing.expectEqualStrings("is", par.ghost);

	const spaced = matchRows(arena, &items, " Par ");
	try std.testing.expectEqual(@as(usize, 2), spaced.rows.len);
	try std.testing.expectEqualStrings("", spaced.ghost);

	const none = matchRows(arena, &items, "Zurich");
	try std.testing.expectEqual(@as(usize, 0), none.rows.len);
	try std.testing.expectEqualStrings("", none.ghost);

	const blank = matchRows(arena, &items, "");
	try std.testing.expectEqual(@as(usize, 3), blank.rows.len);
	try std.testing.expectEqualStrings("", blank.ghost);
}

test "the matching rows stop at five" {
	var state = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer state.deinit();

	var items: [7]Suggest = undefined;
	for (&items, 0..) |*item, i| item.* = .{ .label = @constCast("Town"), .name = @constCast("Town"), .lat = @floatFromInt(i), .lon = 0 };

	const rows = matchRows(state.allocator(), &items, "t");
	try std.testing.expectEqual(@as(usize, 5), rows.rows.len);
}

test "codes describe the condition" {
	const rows = [_]config.CodeRow{
		.{ .code = 0, .name = "Clear", .glyph = "\u{f0599}" },
		.{ .code = 61, .name = "Light rain", .glyph = "\u{f0597}" },
	};

	try std.testing.expectEqualStrings("Light rain", describe(&rows, 61).text);
	try std.testing.expectEqualStrings("\u{f0597}", describe(&rows, 61).glyph);
	try std.testing.expectEqualStrings("Clear", describe(&rows, 0).text);

	const unknown = describe(&rows, 99);
	try std.testing.expectEqualStrings("", unknown.text);
	try std.testing.expectEqualStrings("", unknown.glyph);
}
