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
	volume: f64,
	mute: bool,
};

const NodeOut = struct {
	id: i64,
	name: []const u8,
	app: []const u8,
	class: []const u8,
	volume: f64,
	mute: bool,
};

const Out = struct {
	nodes: []NodeOut,
};

pub const Audio = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	nodes: std.ArrayListUnmanaged(Node) = .empty,

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
		while (true) {
			self.sample();
			sleep.ms(5000);
		}
	}

	fn sample(self: *Audio) void {
		const result = exec.run(self.io, self.allocator, &.{ "pw-dump" }) catch return;
		defer result.deinit(self.allocator);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const parsed = json.parse(arena.allocator(), result.out) catch return;

		var next: std.ArrayListUnmanaged(Node) = .empty;

		for (json.list(parsed.value)) |entry| {
			const kind = json.textAt(entry, "type");
			if (!std.mem.eql(u8, kind, "PipeWire:Interface:Node")) continue;

			const info = json.field(entry, "info") orelse continue;
			const props = json.field(info, "props") orelse continue;

			const class = json.textAt(props, "media.class");
			if (class.len == 0) continue;

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
			if (app.len == 0) app = json.textAt(props, "node.name");

			next.append(self.allocator, .{
				.id = json.integer(json.field(entry, "id")),
				.name = self.allocator.dupe(u8, json.textAt(props, "node.name")) catch continue,
				.app = self.allocator.dupe(u8, app) catch continue,
				.class = self.allocator.dupe(u8, class) catch continue,
				.volume = @round(volume * 1000) / 1000,
				.mute = mute,
			}) catch continue;
		}

		self.mutex.lockUncancelable(self.io);
		for (self.nodes.items) |node| {
			self.allocator.free(node.name);
			self.allocator.free(node.app);
			self.allocator.free(node.class);
		}
		self.nodes.deinit(self.allocator);
		self.nodes = next;
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	pub fn setVolume(self: *Audio, id: i64, fraction: f64) void {
		const text = std.fmt.allocPrint(self.allocator, "{d}%", .{@as(i64, @intFromFloat(fraction * 100))}) catch return;
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

	fn render(self: *Audio, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);
		const arena = self.scratch.allocator();

		var nodes: std.ArrayListUnmanaged(NodeOut) = .empty;
		for (self.nodes.items) |node| {
			try nodes.append(arena, .{
				.id = node.id,
				.name = node.name,
				.app = node.app,
				.class = node.class,
				.volume = node.volume,
				.mute = node.mute,
			});
		}

		try writer.print("{f}", .{std.json.fmt(Out{ .nodes = nodes.items }, .{})});
	}
};
