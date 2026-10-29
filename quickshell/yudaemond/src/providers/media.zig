const std = @import("std");
const hubmod = @import("../hub.zig");
const json = @import("../primitives/json.zig");
const exec = @import("../primitives/exec.zig");
const sleep = @import("../primitives/sleep.zig");
const setStr = @import("opencode.zig").setStr;

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const playing_ms: u64 = 1_000;
const idle_ms: u64 = 4_000;
const max_players = 4;
const prefix = "org.mpris.MediaPlayer2.";
const bus_path = "/org/mpris/MediaPlayer2";
const player_interface = "org.mpris.MediaPlayer2.Player";
const props_interface = "org.freedesktop.DBus.Properties";

const Out = struct {
	name: []const u8,
	playing: bool,
	title: []const u8,
	artist: []const u8,
	album: []const u8,
	art: []const u8,
	elapsed: []const u8,
	total: []const u8,
	percent: f64,
	known: bool,
	wanted: bool,
};

pub const Media = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	name: []u8 = &.{},
	playing: bool = false,
	title: []u8 = &.{},
	artist: []u8 = &.{},
	album: []u8 = &.{},
	art: []u8 = &.{},
	length_us: i64 = 0,
	position_us: i64 = 0,
	signature: []u8 = &.{},

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Media {
		const self = try allocator.create(Media);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.scratch = std.heap.ArenaAllocator.init(allocator),
		};

		return self;
	}

	pub fn provider(self: *Media) hubmod.Provider {
		return .{ .key = "media", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Media = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn start(self: *Media) !void {
		const thread = try std.Thread.spawn(.{}, loop, .{self});
		thread.detach();
	}

	fn loop(self: *Media) void {
		while (true) {
			self.poll();

			self.mutex.lockUncancelable(self.io);
			const playing = self.playing;
			self.mutex.unlock(self.io);

			sleep.ms(if (playing) playing_ms else idle_ms);
		}
	}

	fn poll(self: *Media) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const players = self.names(arena.allocator());

		var found = false;
		var snapshot: Snapshot = .{};

		for (players) |name| {
			const props = self.properties(arena.allocator(), name) orelse continue;

			if (!found or props.playing) {
				snapshot = props;
				snapshot.name = name;
				found = true;
			}

			if (props.playing) break;
		}

		const signature = std.fmt.allocPrint(arena.allocator(), "{s}|{d}|{s}|{s}|{s}|{s}|{d}|{d}", .{
			snapshot.name,
			@intFromBool(snapshot.playing),
			snapshot.title,
			snapshot.artist,
			snapshot.album,
			snapshot.art,
			snapshot.length_us,
			snapshot.position_us,
		}) catch return;

		self.mutex.lockUncancelable(self.io);
		const same = std.mem.eql(u8, self.signature, signature);
		self.mutex.unlock(self.io);

		if (same) return;

		self.mutex.lockUncancelable(self.io);
		setStr(self.allocator, &self.signature, signature) catch {};
		setStr(self.allocator, &self.name, snapshot.name) catch {};
		setStr(self.allocator, &self.title, snapshot.title) catch {};
		setStr(self.allocator, &self.artist, snapshot.artist) catch {};
		setStr(self.allocator, &self.album, snapshot.album) catch {};
		setStr(self.allocator, &self.art, snapshot.art) catch {};
		self.playing = snapshot.playing;
		self.length_us = snapshot.length_us;
		self.position_us = snapshot.position_us;
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn names(self: *Media, arena: Allocator) []const []const u8 {
		const result = exec.run(self.io, self.allocator, &.{ "busctl", "--user", "list", "--no-legend", "--no-pager" }) catch return &.{};
		defer result.deinit(self.allocator);

		var out: std.ArrayList([]const u8) = .empty;
		var lines = std.mem.splitScalar(u8, result.out, '\n');

		while (lines.next()) |line| {
			const end = std.mem.indexOfScalar(u8, line, ' ') orelse line.len;
			const token = std.mem.trim(u8, line[0..end], " \t");

			if (!std.mem.startsWith(u8, token, prefix)) continue;
			if (out.items.len >= max_players) break;

			out.append(arena, arena.dupe(u8, token) catch break) catch continue;
		}

		return out.items;
	}

	const Snapshot = struct {
		name: []const u8 = "",
		playing: bool = false,
		title: []const u8 = "",
		artist: []const u8 = "",
		album: []const u8 = "",
		art: []const u8 = "",
		length_us: i64 = 0,
		position_us: i64 = 0,
	};

	fn properties(self: *Media, arena: Allocator, name: []const u8) ?Snapshot {
		const result = exec.run(self.io, self.allocator, &.{ "busctl", "--user", "--json=short", "call", name, bus_path, props_interface, "GetAll", "s", player_interface }) catch return null;
		defer result.deinit(self.allocator);

		const parsed = json.parse(arena, result.out) catch return null;
		const props = json.listAt(parsed.value, "data");
		if (props.len == 0) return null;

		const values = props[0];
		const metadata = json.deep(values, &.{ "Metadata", "data" });

		var out = Snapshot{
			.playing = std.mem.eql(u8, json.textDeep(values, &.{ "PlaybackStatus", "data" }), "Playing"),
			.position_us = json.integer(json.deep(values, &.{ "Position", "data" })),
		};

		if (metadata) |rows| {
			out.title = json.textDeep(rows, &.{ "xesam:title", "data" });
			out.album = json.textDeep(rows, &.{ "xesam:album", "data" });
			out.art = json.textDeep(rows, &.{ "mpris:artUrl", "data" });
			out.length_us = json.integer(json.deep(rows, &.{ "mpris:length", "data" }));

			if (json.deep(rows, &.{"xesam:artist"})) |artists| out.artist = join(arena, artists) catch "";
		}

		return out;
	}

	pub fn action(self: *Media, what: []const u8) void {
		const method = if (std.mem.eql(u8, what, "playPause"))
			"PlayPause"
		else if (std.mem.eql(u8, what, "next"))
			"Next"
		else if (std.mem.eql(u8, what, "previous"))
			"Previous"
		else
			return;

		self.mutex.lockUncancelable(self.io);
		const name = self.allocator.dupe(u8, self.name) catch {
			self.mutex.unlock(self.io);
			return;
		};
		self.mutex.unlock(self.io);
		defer self.allocator.free(name);

		if (name.len == 0) return;

		const result = exec.run(self.io, self.allocator, &.{ "busctl", "--user", "call", name, bus_path, player_interface, method }) catch return;
		result.deinit(self.allocator);

		self.poll();
	}

	fn render(self: *Media, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);
		const arena = self.scratch.allocator();

		const length = @divTrunc(@max(self.length_us, 0), 1_000_000);
		const at = if (self.length_us > 0) @min(@max(self.position_us, 0), self.length_us) else 0;
		const seconds = @divTrunc(at, 1_000_000);

		const out = Out{
			.name = self.name,
			.playing = self.playing,
			.title = self.title,
			.artist = self.artist,
			.album = self.album,
			.art = self.art,
			.elapsed = timeText(arena, seconds),
			.total = timeText(arena, length),
			.percent = if (self.length_us > 0) 100.0 * @as(f64, @floatFromInt(at)) / @as(f64, @floatFromInt(self.length_us)) else 0,
			.known = self.length_us > 0,
			.wanted = self.playing or self.title.len > 0,
		};

		try writer.print("{f}", .{std.json.fmt(out, .{})});
	}
};

fn join(arena: Allocator, value: json.Value) ![]const u8 {
	var out: std.ArrayList(u8) = .empty;

	for (json.listAt(value, "data")) |entry| {
		const text = json.text(entry);
		if (text.len == 0) continue;

		if (out.items.len > 0) try out.appendSlice(arena, ", ");
		try out.appendSlice(arena, text);
	}

	return out.items;
}

fn timeText(arena: Allocator, seconds: i64) []const u8 {
	const total = @max(seconds, 0);
	const minutes = @divTrunc(total, 60);
	const rest = @mod(total, 60);

	if (minutes < 60) return std.fmt.allocPrint(arena, "{d}:{d:0>2}", .{ minutes, @as(u8, @intCast(rest)) }) catch "";

	return std.fmt.allocPrint(arena, "{d}:{d:0>2}:{d:0>2}", .{
		@divTrunc(minutes, 60),
		@as(u8, @intCast(@mod(minutes, 60))),
		@as(u8, @intCast(rest)),
	}) catch "";
}

test "time text matches the clock" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const inner = arena.allocator();

	try std.testing.expectEqualStrings("3:07", timeText(inner, 187));
	try std.testing.expectEqualStrings("0:00", timeText(inner, 0));
	try std.testing.expectEqualStrings("4:41", timeText(inner, 281));
	try std.testing.expectEqualStrings("1:02:03", timeText(inner, 3723));
	try std.testing.expectEqualStrings("0:00", timeText(inner, -4));
}

test "artists join into one line" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const parsed = try json.parse(arena.allocator(), "{\"type\":\"a{sv}\",\"data\":[{\"Metadata\":{\"type\":\"a{sv}\",\"data\":{\"xesam:artist\":{\"type\":\"as\",\"data\":[\"Anderson .Paak\",\"Kendrick Lamar\"]}}}}]}");
	const values = json.listAt(parsed.value, "data")[0];
	const artists = json.deep(values, &.{ "Metadata", "data", "xesam:artist" }).?;

	try std.testing.expectEqualStrings("Anderson .Paak, Kendrick Lamar", try join(arena.allocator(), artists));
}
