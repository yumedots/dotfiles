const std = @import("std");
const hubmod = @import("../hub.zig");
const json = @import("../primitives/json.zig");
const exec = @import("../primitives/exec.zig");
const sleep = @import("../primitives/sleep.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const pending_ms = 600;

const Write = struct {
	id: i64,
	level: f64 = 0,
	mute: bool = false,
	kind: enum { volume, mute },
};

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
	pending: f64 = -1,
	pending_until: i64 = 0,
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
	appId: []const u8,
	appIds: []const []const u8,
	class: []const u8,
	description: []const u8,
	volume: f64,
	volumeText: []const u8,
	mute: bool,
	muted: bool,
	isStream: bool,
	isSink: bool,
	isDefault: bool,
	shown: bool,
	playing: bool,
	ready: bool,
	running: bool,
	props: PropsOut,
};

const Out = struct {
	nodes: []NodeOut,
	sink: i64,
	source: i64,
	hasInput: bool,
	recording: bool,
	watch: bool,
};

pub const Audio = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	sample_mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	nodes: std.ArrayListUnmanaged(Node) = .empty,
	sink: i64 = 0,
	source: i64 = 0,
	has_input: bool = false,
	watch: std.atomic.Value(bool) = .init(false),
	dirty: std.atomic.Value(bool) = .init(true),
	write_mutex: std.Io.Mutex = .init,
	writes: [16]Write = undefined,
	write_count: usize = 0,
	write_ready: std.atomic.Value(bool) = .init(false),

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

		const events = try std.Thread.spawn(.{}, subscribe, .{self});
		events.detach();

		const writer = try std.Thread.spawn(.{}, writeLoop, .{self});
		writer.detach();
	}

	fn writeLoop(self: *Audio) void {
		while (true) {
			if (!self.write_ready.swap(false, .monotonic)) {
				sleep.ms(15);
				continue;
			}

			while (self.takeWrite()) |item| self.runWrite(item);
		}
	}

	fn runWrite(self: *Audio, item: Write) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();
		const id_text = std.fmt.allocPrint(allocator, "{d}", .{item.id}) catch return;

		var argv: std.ArrayList([]const u8) = .empty;

		switch (item.kind) {
			.volume => {
				const text = std.fmt.allocPrint(allocator, "{d}%", .{@as(i64, @intFromFloat(@round(item.level * 100)))}) catch return;

				for ([_][]const u8{ "wpctl", "set-volume", id_text, text }) |arg| argv.append(allocator, arg) catch return;
			},
			.mute => {
				const flag = if (item.mute) "1" else "0";

				for ([_][]const u8{ "wpctl", "set-mute", id_text, flag }) |arg| argv.append(allocator, arg) catch return;
			},
		}

		if (exec.run(self.io, self.allocator, argv.items)) |result| {
			result.deinit(self.allocator);
		} else |_| {}

		self.sampleSerial();
	}

	fn takeWrite(self: *Audio) ?Write {
		self.write_mutex.lockUncancelable(self.io);
		defer self.write_mutex.unlock(self.io);

		if (self.write_count == 0) return null;

		const item = self.writes[0];

		var index: usize = 1;
		while (index < self.write_count) : (index += 1) {
			self.writes[index - 1] = self.writes[index];
		}

		self.write_count -= 1;

		return item;
	}

	fn queueWrite(self: *Audio, item: Write) void {
		self.write_mutex.lockUncancelable(self.io);

		var index: usize = 0;
		var replaced = false;

		while (index < self.write_count) : (index += 1) {
			if (self.writes[index].id == item.id and self.writes[index].kind == item.kind) {
				self.writes[index] = item;
				replaced = true;
			}
		}

		if (!replaced and self.write_count < self.writes.len) {
			self.writes[self.write_count] = item;
			self.write_count += 1;
		}

		self.write_mutex.unlock(self.io);

		self.write_ready.store(true, .monotonic);
	}

	fn subscribe(self: *Audio) void {
		while (true) {
			self.follow();
			sleep.ms(5000);
		}
	}

	fn follow(self: *Audio) void {
		const child = std.process.spawn(self.io, .{
			.argv = &.{ "stdbuf", "-oL", "pactl", "subscribe" },
			.stdin = .ignore,
			.stdout = .pipe,
			.stderr = .ignore,
		}) catch return;

		defer if (child.id) |id| {
			_ = std.posix.kill(id, std.posix.SIG.KILL) catch {};
		};

		const fd = child.stdout.?.handle;

		var chunk: [1024]u8 = undefined;
		var line: [256]u8 = undefined;
		var used: usize = 0;

		while (true) {
			var fds = [_]std.posix.pollfd{.{ .fd = fd, .events = std.posix.POLL.IN, .revents = 0 }};

			const ready = std.posix.poll(&fds, 1000) catch break;
			if (ready == 0) continue;

			const count = std.posix.read(fd, &chunk) catch break;
			if (count == 0) break;

			for (chunk[0..count]) |byte| {
				if (byte == '\n') {
					self.onEvent(line[0..used]);
					used = 0;
					continue;
				}

				if (used < line.len) {
					line[used] = byte;
					used += 1;
				}
			}
		}
	}

	fn onEvent(self: *Audio, line: []const u8) void {
		if (!streamObject(line)) return;

		self.sampleSerial();
	}

	fn loop(self: *Audio) void {
		var tick: usize = 0;

		while (true) {
			if (self.dirty.swap(false, .monotonic)) self.sampleSerial();
			if (tick % 5 == 0) self.sampleSerial();

			tick +%= 1;
			sleep.ms(1000);
		}
	}

	pub fn setWatch(self: *Audio, watched: bool) void {
		const was = self.watch.swap(watched, .monotonic);

		if (watched and !was) self.sampleSerial();
	}

	fn sampleSerial(self: *Audio) void {
		self.sample_mutex.lockUncancelable(self.io);
		defer self.sample_mutex.unlock(self.io);

		self.sample();
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

						if (json.field(first, "channelVolumes")) |channels| {
							for (json.list(channels)) |channel| volume = @max(volume, json.number(channel));
							volume = std.math.cbrt(volume);
						}

						if (volume == 0) {
							if (json.field(first, "volume")) |value| {
								switch (value) {
									.integer, .float, .number_string => volume = json.number(value),
									.array => {
										for (json.list(value)) |channel| volume = @max(volume, json.number(channel));
									},
									else => {},
								}
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

		const now = std.Io.Clock.real.now(self.io).toMilliseconds();

		for (next.items) |*node| {
			for (self.nodes.items) |old| {
				if (old.id != node.id) continue;

				node.pending = old.pending;
				node.pending_until = old.pending_until;

				if (old.pending >= 0 and now < old.pending_until) node.volume = old.pending;
			}
		}

		const changed = !sameNodes(self.nodes.items, next.items, self.sink, sink) or
			self.source != source or
			self.has_input != (sources_seen and has_input);

		for (self.nodes.items) |node| self.freeNode(node);
		self.nodes.deinit(self.allocator);
		self.nodes = next;
		self.sink = sink;
		self.source = source;
		self.has_input = sources_seen and has_input;
		self.mutex.unlock(self.io);

		return changed;
	}

	pub fn setVolume(self: *Audio, id: i64, fraction: f64) void {
		const level = std.math.clamp(fraction, 0, 1);
		const until = std.Io.Clock.real.now(self.io).toMilliseconds() + pending_ms;

		self.mutex.lockUncancelable(self.io);
		for (self.nodes.items) |*node| {
			if (node.id != id) continue;

			node.volume = level;
			node.pending = level;
			node.pending_until = until;
		}
		self.mutex.unlock(self.io);

		self.hub.publish();
		self.queueWrite(.{ .id = id, .level = level, .kind = .volume });
	}

	pub fn setMute(self: *Audio, id: i64, mute: bool) void {
		const until = std.Io.Clock.real.now(self.io).toMilliseconds() + pending_ms;

		self.mutex.lockUncancelable(self.io);
		for (self.nodes.items) |*node| {
			if (node.id != id) continue;

			node.mute = mute;
			node.pending = -1;
			node.pending_until = until;
		}
		self.mutex.unlock(self.io);

		self.hub.publish();
		self.queueWrite(.{ .id = id, .mute = mute, .kind = .mute });
	}

	pub fn setDefault(self: *Audio, id: i64) void {
		const id_text = std.fmt.allocPrint(self.allocator, "{d}", .{id}) catch return;
		defer self.allocator.free(id_text);

		const result = exec.run(self.io, self.allocator, &.{ "wpctl", "set-default", id_text }) catch return;
		result.deinit(self.allocator);

		self.dirty.store(true, .monotonic);
	}

	fn render(self: *Audio, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);
		const arena = self.scratch.allocator();

		var nodes: std.ArrayListUnmanaged(NodeOut) = .empty;
		var recording = false;

		for (self.nodes.items) |node| {
			const running = std.mem.eql(u8, node.state, "running");
			const ready = node.state.len > 0;
			const input = std.mem.indexOf(u8, node.class, "Input") != null;

			if (node.is_stream and running and input) recording = true;

			try nodes.append(arena, .{
				.id = node.id,
				.name = node.name,
				.app = node.app,
				.appId = if (node.name.len > 0) node.name else node.app,
				.appIds = try appIds(arena, node),
				.class = node.class,
				.description = node.description,
				.volume = node.volume,
				.volumeText = try percentText(arena, node.volume),
				.mute = node.mute,
				.muted = node.mute,
				.isStream = node.is_stream,
				.isSink = node.is_sink,
				.isDefault = node.id == self.sink or node.id == self.source,
				.shown = ready and node.is_stream and !input,
				.playing = running,
				.ready = ready,
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
			.recording = recording,
			.watch = self.watch.load(.monotonic),
		}, .{})});
	}
};

fn percentText(arena: Allocator, volume: f64) ![]const u8 {
	return std.fmt.allocPrint(arena, "{d}%", .{@as(i64, @intFromFloat(@round(volume * 100)))});
}

fn appIds(arena: Allocator, node: Node) ![]const []const u8 {
	var list: std.ArrayListUnmanaged([]const u8) = .empty;

	if (node.name.len > 0) try list.append(arena, node.name);
	if (node.app.len > 0) try list.append(arena, node.app);

	if (digitRun(node.name) orelse digitRun(node.app)) |digits| {
		try list.append(arena, try std.fmt.allocPrint(arena, "steam_app_{s}", .{digits}));
	}

	const binary = if (std.mem.lastIndexOfScalar(u8, node.binary, '/')) |at| node.binary[at + 1 ..] else node.binary;
	if (binary.len > 0) try list.append(arena, binary);

	return list.items;
}

fn digitRun(text: []const u8) ?[]const u8 {
	var index: usize = 0;

	while (index < text.len) : (index += 1) {
		if (!std.ascii.isDigit(text[index])) continue;

		const start = index;
		while (index < text.len and std.ascii.isDigit(text[index])) index += 1;

		const end = index;
		if (end - start < 3) continue;
		if (end < text.len and (std.ascii.isAlphanumeric(text[end]) or text[end] == '_')) continue;

		return text[start..end];
	}

	return null;
}

fn sameNodes(a: []const Node, b: []const Node, sink_a: i64, sink_b: i64) bool {
	if (a.len != b.len or sink_a != sink_b) return false;

	for (a, b) |old, new| {
		if (old.id != new.id) return false;
		if (old.mute != new.mute) return false;
		if (old.is_stream != new.is_stream or old.is_sink != new.is_sink) return false;
		if (@abs(old.volume - new.volume) > 0.0005) return false;
		if (!std.mem.eql(u8, old.state, new.state)) return false;
		if (!std.mem.eql(u8, old.name, new.name)) return false;
		if (!std.mem.eql(u8, old.app, new.app)) return false;
	}

	return true;
}

fn streamObject(line: []const u8) bool {
	const kinds = [_][]const u8{ "on sink #", "on sink-input #", "on source #", "on source-output #" };

	for (kinds) |kind| {
		if (std.mem.indexOf(u8, line, kind) != null) return true;
	}

	return false;
}

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
	\\ {"id":60,"type":"PipeWire:Interface:Node","info":{"state":"running","props":{
	\\   "media.class":"Stream/Output/Audio","node.name":"browser","application.name":"Browser"},
	\\   "params":{"Props":[{"volume":1.0,"channelVolumes":[0.064,0.064],"mute":false}]}}},
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
		.io = std.Io.Threaded.global_single_threaded.io(),
		.hub = undefined,
		.scratch = std.heap.ArenaAllocator.init(std.testing.allocator),
	};

	try std.testing.expect(audio.apply(dump_fixture));

	try std.testing.expectEqual(@as(usize, 4), audio.nodes.items.len);
	try std.testing.expectEqual(@as(i64, 52), audio.sink);
	try std.testing.expectEqual(@as(i64, 54), audio.source);
	try std.testing.expectEqual(false, audio.has_input);

	const browser = audio.nodes.items[2];
	try std.testing.expectEqual(@as(f64, 0.4), browser.volume);

	const player = audio.nodes.items[3];
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

test "only audio objects wake the mixer" {
	try std.testing.expect(streamObject("Event 'change' on sink #52"));
	try std.testing.expect(streamObject("Event 'new' on sink-input #118"));
	try std.testing.expect(!streamObject("Event 'change' on client #90"));
	try std.testing.expect(!streamObject("Event 'remove' on module #12"));
}

test "volume text is the percent the mixer draws" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();

	try std.testing.expectEqualStrings("72%", try percentText(allocator, 0.72));
	try std.testing.expectEqualStrings("100%", try percentText(allocator, 1));
	try std.testing.expectEqualStrings("0%", try percentText(allocator, 0.004));
	try std.testing.expectEqualStrings("150%", try percentText(allocator, 1.5));
}

test "the steam id is the first digit run of three" {
	try std.testing.expectEqualStrings("12345", digitRun("Civilization (12345)").?);
	try std.testing.expectEqualStrings("732", digitRun("game-732").?);
	try std.testing.expect(digitRun("mp3") == null);
	try std.testing.expect(digitRun("x99") == null);
	try std.testing.expect(digitRun("123abc") == null);
	try std.testing.expectEqualStrings("123", digitRun("123 abc").?);
	try std.testing.expectEqualStrings("777", digitRun("a 1 b 777").?);
}

test "render emits the node fields the mixer binds" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();

	var audio: Audio = .{
		.allocator = allocator,
		.io = std.Io.Threaded.global_single_threaded.io(),
		.hub = undefined,
		.scratch = std.heap.ArenaAllocator.init(allocator),
	};

	audio.sink = 52;
	audio.source = 54;

	try audio.nodes.append(allocator, .{
		.id = 52,
		.name = try allocator.dupe(u8, "speakers"),
		.app = try allocator.dupe(u8, "Speakers"),
		.class = try allocator.dupe(u8, "Audio/Sink"),
		.description = try allocator.dupe(u8, "Speakers"),
		.binary = try allocator.dupe(u8, ""),
		.pid = try allocator.dupe(u8, ""),
		.volume = 0.72,
		.mute = false,
		.is_stream = false,
		.is_sink = true,
		.state = try allocator.dupe(u8, "running"),
	});

	try audio.nodes.append(allocator, .{
		.id = 60,
		.name = try allocator.dupe(u8, "browser"),
		.app = try allocator.dupe(u8, "Browser 12345"),
		.class = try allocator.dupe(u8, "Stream/Output/Audio"),
		.description = try allocator.dupe(u8, "Browser"),
		.binary = try allocator.dupe(u8, "/usr/lib/browser"),
		.pid = try allocator.dupe(u8, "1234"),
		.volume = 0.064,
		.mute = true,
		.is_stream = true,
		.is_sink = false,
		.state = try allocator.dupe(u8, "running"),
	});

	try audio.nodes.append(allocator, .{
		.id = 62,
		.name = try allocator.dupe(u8, "recorder"),
		.app = try allocator.dupe(u8, "Recorder"),
		.class = try allocator.dupe(u8, "Stream/Input/Audio"),
		.description = try allocator.dupe(u8, "Recorder"),
		.binary = try allocator.dupe(u8, ""),
		.pid = try allocator.dupe(u8, ""),
		.volume = 1,
		.mute = false,
		.is_stream = true,
		.is_sink = false,
		.state = try allocator.dupe(u8, "running"),
	});

	var out: std.Io.Writer.Allocating = .init(allocator);
	defer out.deinit();

	try audio.render(&out.writer);

	const parsed = try json.parse(allocator, out.written());
	const nodes = json.listAt(parsed.value, "nodes");

	try std.testing.expectEqual(@as(usize, 3), nodes.len);
	try std.testing.expect(json.flag(parsed.value, "recording"));

	const sink = nodes[0];
	try std.testing.expectEqualStrings("72%", json.textAt(sink, "volumeText"));
	try std.testing.expect(json.flag(sink, "isDefault"));
	try std.testing.expect(!json.flag(sink, "isStream"));
	try std.testing.expect(!json.flag(sink, "shown"));

	const stream = nodes[1];
	try std.testing.expectEqualStrings("6%", json.textAt(stream, "volumeText"));
	try std.testing.expect(json.flag(stream, "shown"));
	try std.testing.expect(json.flag(stream, "playing"));
	try std.testing.expect(json.flag(stream, "muted"));
	try std.testing.expect(!json.flag(stream, "isDefault"));
	try std.testing.expectEqualStrings("browser", json.textAt(stream, "appId"));

	const ids = json.listAt(stream, "appIds");
	try std.testing.expectEqualStrings("browser", json.text(ids[0]));
	try std.testing.expectEqualStrings("Browser 12345", json.text(ids[1]));
	try std.testing.expectEqualStrings("steam_app_12345", json.text(ids[2]));
	try std.testing.expectEqualStrings("browser", json.text(ids[3]));

	const input = nodes[2];
	try std.testing.expect(!json.flag(input, "shown"));
	try std.testing.expect(json.flag(input, "playing"));
}
