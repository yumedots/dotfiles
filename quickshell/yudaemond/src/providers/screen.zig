const std = @import("std");
const hubmod = @import("../hub.zig");
const hypr = @import("../primitives/hypr.zig");
const json = @import("../primitives/json.zig");
const sleep = @import("../primitives/sleep.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const Mode = struct {
	width: i64,
	height: i64,
	refresh: f64,
};

const Monitor = struct {
	id: i64,
	name: []u8,
	description: []u8,
	make: []u8,
	model: []u8,
	width: i64,
	height: i64,
	refresh: f64,
	x: i64,
	y: i64,
	scale: f64,
	transform: i64,
	focused: bool,
	disabled: bool,
	workspace: []u8,
	modes: std.ArrayListUnmanaged(Mode) = .empty,
};

const ModeOut = struct {
	width: i64,
	height: i64,
	refresh: f64,
	label: []const u8,
};

const ResOut = struct {
	width: i64,
	height: i64,
	refreshes: []ModeOut,
};

const MonitorOut = struct {
	id: i64,
	name: []const u8,
	description: []const u8,
	make: []const u8,
	model: []const u8,
	width: i64,
	height: i64,
	refresh: f64,
	x: i64,
	y: i64,
	scale: f64,
	transform: i64,
	focused: bool,
	disabled: bool,
	workspace: []const u8,
	modes: []ModeOut,
	resolutions: []ResOut,
};

const Out = struct {
	monitors: []MonitorOut,
	raw: []const u8,
};

pub const Screen = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	monitors: std.ArrayListUnmanaged(Monitor) = .empty,
	raw: []u8 = &.{},
	available: bool = false,

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Screen {
		const self = try allocator.create(Screen);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.scratch = std.heap.ArenaAllocator.init(allocator),
		};

		return self;
	}

	pub fn provider(self: *Screen) hubmod.Provider {
		return .{ .key = "screen", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Screen = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn start(self: *Screen) !void {
		const thread = try std.Thread.spawn(.{}, loop, .{self});
		thread.detach();
	}

	fn loop(self: *Screen) void {
		self.poll();

		while (true) {
			sleep.ms(3000);
			self.poll();
		}
	}

	fn poll(self: *Screen) void {
		const body = hypr.request(self.io, self.allocator, "j/monitors") catch {
			return;
		};
		defer self.allocator.free(body);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const parsed = json.parse(arena.allocator(), body) catch return;

		var next: std.ArrayListUnmanaged(Monitor) = .empty;

		for (json.list(parsed.value)) |entry| {
			const mode_list = json.listAt(entry, "availableModes");
			var modes: std.ArrayListUnmanaged(Mode) = .empty;

			for (mode_list) |mode| {
				const label = json.text(mode);
				const parsed_mode = parseMode(label) orelse continue;
				modes.append(self.allocator, parsed_mode) catch continue;
			}

			const workspace = json.field(entry, "activeWorkspace") orelse json.Value{ .null = {} };

			next.append(self.allocator, .{
				.id = json.integer(json.field(entry, "id")),
				.name = self.allocator.dupe(u8, json.textAt(entry, "name")) catch continue,
				.description = self.allocator.dupe(u8, json.textAt(entry, "description")) catch continue,
				.make = self.allocator.dupe(u8, json.textAt(entry, "make")) catch continue,
				.model = self.allocator.dupe(u8, json.textAt(entry, "model")) catch continue,
				.width = json.integer(json.field(entry, "width")),
				.height = json.integer(json.field(entry, "height")),
				.refresh = json.numberAt(entry, "refreshRate"),
				.x = json.integer(json.field(entry, "x")),
				.y = json.integer(json.field(entry, "y")),
				.scale = json.numberAt(entry, "scale"),
				.transform = json.integer(json.field(entry, "transform")),
				.focused = json.flag(entry, "focused"),
				.disabled = json.flag(entry, "disabled"),
				.workspace = self.allocator.dupe(u8, workspaceString(workspace)) catch continue,
				.modes = modes,
			}) catch continue;
		}

		self.mutex.lockUncancelable(self.io);
		self.available = true;
		if (self.raw.len > 0) self.allocator.free(self.raw);
		self.raw = self.allocator.dupe(u8, body) catch &.{};
		for (self.monitors.items) |*monitor| self.freeMonitor(monitor);
		self.monitors.deinit(self.allocator);
		self.monitors = next;
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn freeMonitor(self: *Screen, monitor: *Monitor) void {
		self.allocator.free(monitor.name);
		self.allocator.free(monitor.description);
		self.allocator.free(monitor.make);
		self.allocator.free(monitor.model);
		self.allocator.free(monitor.workspace);
		monitor.modes.deinit(self.allocator);
	}

	fn render(self: *Screen, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);
		const arena = self.scratch.allocator();

		var monitors: std.ArrayListUnmanaged(MonitorOut) = .empty;

		for (self.monitors.items) |*monitor| {
			var modes: std.ArrayListUnmanaged(ModeOut) = .empty;

			for (monitor.modes.items) |mode| {
				const label = try std.fmt.allocPrint(arena, "{d}x{d}@{d:.2}", .{ mode.width, mode.height, mode.refresh });
				try modes.append(arena, .{
					.width = mode.width,
					.height = mode.height,
					.refresh = mode.refresh,
					.label = label,
				});
			}

			var resolutions: std.ArrayListUnmanaged(ResOut) = .empty;

			for (monitor.modes.items) |mode| {
				var found: ?*ResOut = null;
				for (resolutions.items) |*res| {
					if (res.width == mode.width and res.height == mode.height) {
						found = res;
						break;
					}
				}

				if (found == null) {
					try resolutions.append(arena, .{ .width = mode.width, .height = mode.height, .refreshes = &.{} });
					found = &resolutions.items[resolutions.items.len - 1];
				}

				var refreshes: std.ArrayListUnmanaged(ModeOut) = .empty;
				for (found.?.refreshes) |entry| try refreshes.append(arena, entry);
				try refreshes.append(arena, .{
					.width = mode.width,
					.height = mode.height,
					.refresh = mode.refresh,
					.label = try std.fmt.allocPrint(arena, "{d} Hz", .{@as(i64, @intFromFloat(@round(mode.refresh)))}),
				});
				std.mem.sort(ModeOut, refreshes.items, {}, byRefreshDesc);
				found.?.refreshes = refreshes.items;
			}

			try monitors.append(arena, .{
				.id = monitor.id,
				.name = monitor.name,
				.description = monitor.description,
				.make = monitor.make,
				.model = monitor.model,
				.width = monitor.width,
				.height = monitor.height,
				.refresh = monitor.refresh,
				.x = monitor.x,
				.y = monitor.y,
				.scale = monitor.scale,
				.transform = monitor.transform,
				.focused = monitor.focused,
				.disabled = monitor.disabled,
				.workspace = monitor.workspace,
				.modes = modes.items,
				.resolutions = resolutions.items,
			});
		}

		const out = Out{ .monitors = monitors.items, .raw = self.raw };
		try writer.print("{f}", .{std.json.fmt(out, .{})});
	}
};

fn byRefreshDesc(_: void, a: ModeOut, b: ModeOut) bool {
	return a.refresh > b.refresh;
}

fn workspaceString(workspace: json.Value) []const u8 {
	const name = json.textAt(workspace, "name");
	if (name.len > 0) return name;

	const id = json.integer(json.field(workspace, "id"));
	if (id == 0) return "";

	return std.fmt.allocPrint(std.heap.smp_allocator, "{d}", .{id}) catch "";
}

fn parseMode(label: []const u8) ?Mode {
	const at = std.mem.indexOfScalar(u8, label, '@') orelse return null;
	const x = std.mem.indexOfScalar(u8, label[0..at], 'x') orelse return null;

	const width = std.fmt.parseInt(i64, label[0..x], 10) catch return null;
	const height_text = label[x + 1 .. at];
	const height = std.fmt.parseInt(i64, height_text, 10) catch return null;

	const refresh_text = label[at + 1 ..];
	const cut = std.mem.indexOfAny(u8, refresh_text, "Hh ") orelse refresh_text.len;
	const refresh = std.fmt.parseFloat(f64, refresh_text[0..cut]) catch return null;

	return .{ .width = width, .height = height, .refresh = refresh };
}

test "modes parse from hyprctl labels" {
	const mode = parseMode("2560x1440@165.00Hz") orelse return error.NoMode;
	try std.testing.expectEqual(@as(i64, 2560), mode.width);
	try std.testing.expectEqual(@as(i64, 1440), mode.height);
	try std.testing.expectApproxEqAbs(@as(f64, 165), mode.refresh, 0.01);
	try std.testing.expect(parseMode("nonsense") == null);
}
