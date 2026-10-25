const std = @import("std");
const hubmod = @import("../hub.zig");
const json = @import("../primitives/json.zig");
const exec = @import("../primitives/exec.zig");
const sleep = @import("../primitives/sleep.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const Node = struct {
	id: i64,
	name: []u8,
	app: []u8,
	class: []u8,
	description: []u8,
	binary: []u8,
	pid: []u8,
	volume: f64,
	mute: bool,
	is_stream: bool,
	is_sink: bool,
	state: []u8,
};

const PropsOut = struct {
	@"node.name": []const u8,
	@"application.name": []const u8,
	@"application.process.binary": []const u8,
	@"application.process.id": []const u8,
	@"media.class": []const u8,
};

const NodeOut = struct {
	id: i64,
	name: []const u8,
	app: []const u8,
	class: []const u8,
	description: []const u8,
	volume: f64,
	mute: bool,
	isStream: bool,
	isSink: bool,
	ready: bool,
	running: bool,
	props: PropsOut,
};

const Out = struct {
	nodes: []NodeOut,
	sink: i64,
	source: i64,
	hasInput: bool,
};

pub const Audio = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	nodes: std.ArrayListUnmanaged(Node) = .empty,
	sink: i64 = 0,
	source: i64 = 0,
	has_input: bool = false,
	watch: std.atomic.Value(bool) = .init(false),

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Audio {
		const self = try allocator.create(Audio);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.scratch = std.heap.ArenaAllocator.init(allocator),
		};

		return self;
	}

	pub fn provider(self: *Audio) hubmod.Provider {
		return .{ .key = "audio", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Audio = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn start(self: *Audio) !void {
		const thread = try std.Thread.spawn(.{}, loop, .{self});
		thread.detach();
	}

	fn loop(self: *Audio) void {
		var tick: usize = 0;

		while (true) {
			if (tick % 5 == 0 or self.watch.load(.monotonic)) self.sample();

			tick +%= 1;
			sleep.ms(1000);
		}
	}

	pub fn setWatch(self: *Audio, watched: bool) void {
		const was = self.watch.swap(watched, .monotonic);

		if (watched and !was) self.sample();
	}

	fn freeNode(self: *Audio, node: Node) void {
		self.allocator.free(node.name);
		self.allocator.free(node.app);
		self.allocator.free(node.class);
		self.allocator.free(node.description);
		self.allocator.free(node.binary);
		self.allocator.free(node.pid);
		self.allocator.free(node.state);
	}

	fn pidOf(self: *Audio, props: json.Value) []u8 {
		const value = json.field(props, "application.process.id") orelse return self.allocator.dupe(u8, "") catch &.{};

		if (value == .string) return self.allocator.dupe(u8, value.string) catch &.{};

		return std.fmt.allocPrint(self.allocator, "{d}", .{json.integer(value)}) catch &.{};
	}

	fn sample(self: *Audio) void {
		const result = exec.run(self.io, self.allocator, &.{ "pw-dump" }) catch return;
		defer result.deinit(self.allocator);

		if (self.apply(result.out)) self.hub.publish();
	}

	fn apply(self: *Audio, body: []const u8) bool {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const parsed = json.parse(arena.allocator(), body) catch return false;
		const dump = json.list(parsed.value);

		var sink_name: []const u8 = "";
		var source_name: []const u8 = "";

		for (dump) |entry| {
			if (!std.mem.eql(u8, json.textAt(entry, "type"), "PipeWire:Interface:Metadata")) continue;

			for (json.listAt(entry, "metadata")) |item| {
				const key = json.textAt(item, "key");
				const value = json.field(item, "value") orelse continue;

				if (std.mem.eql(u8, key, "default.audio.sink")) sink_name = json.textAt(value, "name");
				if (std.mem.eql(u8, key, "default.audio.source")) source_name = json.textAt(value, "name");
			}
		}

		var routes: [16]struct { device: []const u8, free: bool } = undefined;
		var route_count: usize = 0;

		for (dump) |entry| {
			if (!std.mem.eql(u8, json.textAt(entry, "type"), "PipeWire:Interface:Device")) continue;
			if (route_count == routes.len) break;

			const info = json.field(entry, "info") orelse continue;
			const params = json.field(info, "params") orelse continue;
			const list = json.field(params, "EnumRoute") orelse continue;

			var free = false;
			for (json.list(list)) |route| {
				if (json.field(route, "available")) |_| {
					if (!std.mem.eql(u8, json.textAt(route, "available"), "no") and
						std.mem.eql(u8, json.textAt(route, "direction"), "Input")) free = true;
				} else free = true;
			}

			const props = json.field(info, "props") orelse continue;

			routes[route_count] = .{ .device = json.textAt(props, "device.id"), .free = free };
			route_count += 1;
		}

		var next: std.ArrayListUnmanaged(Node) = .empty;
		var sink: i64 = 0;
		var source: i64 = 0;
		var has_input = true;
		var sources_seen = false;

		for (dump) |entry| {
			if (!std.mem.eql(u8, json.textAt(entry, "type"), "PipeWire:Interface:Node")) continue;

			const info = json.field(entry, "info") orelse continue;
			const props = json.field(info, "props") orelse continue;

			const class = json.textAt(props, "media.class");
			if (class.len == 0) continue;

			const name = json.textAt(props, "node.name");
			const state = json.textAt(info, "state");

			var volume: f64 = 0;
			var mute = false;

			if (json.field(info, "params")) |params| {
				if (json.field(params, "Props")) |props_list| {
					if (json.list(props_list).len > 0) {
						const first = json.list(props_list)[0];
						if (json.field(first, "volume")) |value| {
							switch (value) {
								.integer, .float, .number_string => volume = json.number(value),
								.array => {
									for (json.list(value)) |channel| volume = @max(volume, json.number(channel));
								},
								else => {},
							}
						}

						mute = json.flag(first, "mute");
					}
				}
			}

			var app = json.textAt(props, "application.name");
			if (app.len == 0) app = json.textAt(props, "node.description");
			if (app.len == 0) app = name;

			var description = json.textAt(props, "node.description");
			if (description.len == 0) description = app;

			if (std.mem.eql(u8, name, sink_name)) sink = json.integer(json.field(entry, "id"));
			if (std.mem.eql(u8, name, source_name)) source = json.integer(json.field(entry, "id"));

			if (std.mem.indexOf(u8, class, "Audio/Source") != null) {
				sources_seen = true;

				const device = json.textAt(props, "device.id");
				var free = true;

				for (routes[0..route_count]) |route| {
					if (std.mem.eql(u8, route.device, device)) free = route.free;
				}

				has_input = has_input and free;
			}

			next.append(self.allocator, .{
				.id = json.integer(json.field(entry, "id")),
				.name = self.allocator.dupe(u8, name) catch continue,
				.app = self.allocator.dupe(u8, app) catch continue,
				.class = self.allocator.dupe(u8, class) catch continue,
				.description = self.allocator.dupe(u8, description) catch continue,
				.binary = self.allocator.dupe(u8, json.textAt(props, "application.process.binary")) catch continue,
				.pid = self.pidOf(props),
				.volume = @round(volume * 1000) / 1000,
				.mute = mute,
				.is_stream = std.mem.startsWith(u8, class, "Stream/"),
				.is_sink = std.mem.eql(u8, class, "Audio/Sink"),
				.state = self.allocator.dupe(u8, state) catch continue,
			}) catch continue;
		}

		if (sink == 0) {
			for (next.items) |node| {
				if (node.is_sink) {
					sink = node.id;
					break;
				}
			}
		}

		if (source == 0) {
			for (next.items) |node| {
				if (std.mem.indexOf(u8, node.class, "Audio/Source") != null) {
					source = node.id;
					break;
				}
			}
		}

		self.mutex.lockUncancelable(self.io);
		for (self.nodes.items) |node| self.freeNode(node);
		self.nodes.deinit(self.allocator);
		self.nodes = next;
		self.sink = sink;
		self.source = source;
		self.has_input = sources_seen and has_input;
		self.mutex.unlock(self.io);

		return true;
	}

	pub fn setVolume(self: *Audio, id: i64, fraction: f64) void {
		const text = std.fmt.allocPrint(self.allocator, "{d}%", .{@as(i64, @intFromFloat(@round(fraction * 100)))}) catch return;
		defer self.allocator.free(text);

		const id_text = std.fmt.allocPrint(self.allocator, "{d}", .{id}) catch return;
		defer self.allocator.free(id_text);

		const result = exec.run(self.io, self.allocator, &.{ "wpctl", "set-volume", id_text, text }) catch return;
		result.deinit(self.allocator);

		self.sample();
	}

	pub fn setMute(self: *Audio, id: i64, mute: bool) void {
		const id_text = std.fmt.allocPrint(self.allocator, "{d}", .{id}) catch return;
		defer self.allocator.free(id_text);

		const result = exec.run(self.io, self.allocator, &.{ "wpctl", "set-mute", id_text, if (mute) "1" else "0" }) catch return;
		result.deinit(self.allocator);

		self.sample();
	}

	pub fn setDefault(self: *Audio, id: i64) void {
		const id_text = std.fmt.allocPrint(self.allocator, "{d}", .{id}) catch return;
		defer self.allocator.free(id_text);

		const result = exec.run(self.io, self.allocator, &.{ "wpctl", "set-default", id_text }) catch return;
		result.deinit(self.allocator);

		self.sample();
	}

	fn render(self: *Audio, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);
		const arena = self.scratch.allocator();

		var nodes: std.ArrayListUnmanaged(NodeOut) = .empty;

		for (self.nodes.items) |node| {
			const running = std.mem.eql(u8, node.state, "running");

			try nodes.append(arena, .{
				.id = node.id,
				.name = node.name,
				.app = node.app,
				.class = node.class,
				.description = node.description,
				.volume = node.volume,
				.mute = node.mute,
				.isStream = node.is_stream,
				.isSink = node.is_sink,
				.ready = node.state.len > 0,
				.running = running,
				.props = .{
					.@"node.name" = node.name,
					.@"application.name" = node.app,
					.@"application.process.binary" = node.binary,
					.@"application.process.id" = node.pid,
					.@"media.class" = node.class,
				},
			});
		}

		try writer.print("{f}", .{std.json.fmt(Out{
			.nodes = nodes.items,
			.sink = self.sink,
			.source = self.source,
			.hasInput = self.has_input,
		}, .{})});
	}
};

const dump_fixture =
	\\[
	\\ {"id":39,"type":"PipeWire:Interface:Metadata","metadata":[
	\\   {"key":"default.audio.sink","value":{"name":"speakers"}},
	\\   {"key":"default.audio.source","value":{"name":"mic"}}]},
	\\ {"id":44,"type":"PipeWire:Interface:Device","info":{"props":{"device.id":7},"params":{"EnumRoute":[
	\\   {"direction":"Input","available":"no"}]}}},
	\\ {"id":52,"type":"PipeWire:Interface:Node","info":{"state":"suspended","props":{
	\\   "media.class":"Audio/Sink","node.name":"speakers","node.description":"Speakers"},
	\\   "params":{"Props":[{"volume":0.5,"mute":false}]}}},
	\\ {"id":54,"type":"PipeWire:Interface:Node","info":{"state":"suspended","props":{
	\\   "media.class":"Audio/Source","node.name":"mic","node.description":"Mic","device.id":7},
	\\   "params":{"Props":[{"volume":1.0,"mute":true}]}}},
	\\ {"id":68,"type":"PipeWire:Interface:Node","info":{"state":"running","props":{
	\\   "media.class":"Stream/Output/Audio","node.name":"player","application.name":"Player",
	\\   "application.process.id":1234},"params":{"Props":[{"volume":0.25,"mute":false}]}}}
	\\]
;

test "pw-dump maps to the mixer shape" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	var audio: Audio = .{
		.allocator = arena.allocator(),
		.io = undefined,
		.hub = undefined,
		.scratch = std.heap.ArenaAllocator.init(std.testing.allocator),
	};

	try std.testing.expect(audio.apply(dump_fixture));

	try std.testing.expectEqual(@as(usize, 3), audio.nodes.items.len);
	try std.testing.expectEqual(@as(i64, 52), audio.sink);
	try std.testing.expectEqual(@as(i64, 54), audio.source);
	try std.testing.expectEqual(false, audio.has_input);

	const player = audio.nodes.items[2];
	try std.testing.expect(player.is_stream);
	try std.testing.expect(!player.is_sink);
	try std.testing.expectEqualStrings("Player", player.app);
	try std.testing.expectEqualStrings("1234", player.pid);
	try std.testing.expectEqual(@as(f64, 0.25), player.volume);
	try std.testing.expectEqualStrings("running", player.state);

	const mic = audio.nodes.items[1];
	try std.testing.expect(mic.mute);
	try std.testing.expectEqual(@as(f64, 1), mic.volume);
}
