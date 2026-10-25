const std = @import("std");
const hubmod = @import("../hub.zig");
const hypr = @import("../primitives/hypr.zig");
const json = @import("../primitives/json.zig");
const sleep = @import("../primitives/sleep.zig");
const config = @import("../primitives/config.zig");
const settings = @import("settings.zig");
const exec = @import("../primitives/exec.zig");

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
	label: []const u8,
	maxRefresh: i64,
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
	scales: []f64,
};

const GroupOut = struct {
	label: []const u8,
	kind: []const u8,
	options: []const []const u8,
	selected: i64,
	shown: []const u8,
	visible: bool,
};

const PanelOut = struct {
	row: i64,
	step: i64,
	rows: []const []const u8,
	cursor: []const u8,
	keyboard: bool,
	options: []const []const u8,
	selected: i64,
	value: []const u8,
	selectedRow: []const i64,
	groups: []GroupOut,
};

const Out = struct {
	primary: i64,
	monitors: []MonitorOut,
	panel: PanelOut,
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
	scale_min: f64 = 1,
	scale_max: f64 = 2,
	title_scale: []u8 = &.{},
	title_refresh: []u8 = &.{},
	title_font: []u8 = &.{},
	row: i64 = 0,
	step: i64 = 0,
	keyboard: bool = false,
	fonts: [12]i64 = @splat(0),
	font_count: usize = 0,
	settings: ?*settings.Settings = null,

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Screen {
		const self = try allocator.create(Screen);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.scratch = std.heap.ArenaAllocator.init(allocator),
		};

		self.loadConfig();

		return self;
	}

	fn loadConfig(self: *Screen) void {
		const cfg = config.Config.load(self.io, self.allocator) catch return;
		defer cfg.deinit();

		self.scale_min = cfg.number("displayScaleMin", 1);
		self.scale_max = cfg.number("displayScaleMax", 2);

		self.title_scale = cfg.string("displayScaleTitle", self.allocator) orelse self.allocator.dupe(u8, "Scale") catch &.{};
		self.title_refresh = cfg.string("displayRefreshTitle", self.allocator) orelse self.allocator.dupe(u8, "Refresh") catch &.{};
		self.title_font = cfg.string("displayFontTitle", self.allocator) orelse self.allocator.dupe(u8, "Font") catch &.{};

		const fonts = cfg.numbers("displayFonts", self.allocator) catch &.{};
		self.font_count = @min(fonts.len, self.fonts.len);

		for (fonts[0..self.font_count], 0..) |value, i| self.fonts[i] = value;

		if (fonts.len > 0) self.allocator.free(fonts);

		if (self.font_count == 0) {
			self.fonts[0] = 12;
			self.fonts[1] = 14;
			self.fonts[2] = 16;
			self.font_count = 3;
		}
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

	pub fn attachSettings(self: *Screen, target: *settings.Settings) void {
		self.settings = target;
	}

	pub fn keyCode(self: *Screen, code: i64) void {
		const name = switch (code) {
			0x01000012 => "left",
			0x01000013 => "up",
			0x01000014 => "right",
			0x01000015 => "down",
			0x01000004, 0x01000005 => "enter",
			else => "",
		};

		if (name.len > 0) self.key(name);
	}

	pub fn pick(self: *Screen, kind: []const u8, value: []const u8) void {
		const kinds = [_][]const u8{ "scale", "refresh", "font", "resolution" };
		var row: i64 = 0;

		for (kinds, 0..) |name, i| {
			if (std.mem.eql(u8, name, kind)) row = @intCast(i);
		}

		self.row = row;
		self.step = 0;

		var options = self.panelOptions(self.allocator, kind) catch return;
		defer {
			for (options.items) |option| self.allocator.free(option);
			options.deinit(self.allocator);
		}

		for (options.items, 0..) |option, i| {
			if (std.mem.eql(u8, option, value)) {
				self.step = @intCast(i);
				break;
			}
		}

		self.apply();
	}

	fn panelOptions(self: *Screen, allocator: Allocator, kind: []const u8) !std.ArrayListUnmanaged([]u8) {
		var options: std.ArrayListUnmanaged([]u8) = .empty;

		if (self.monitors.items.len == 0) return options;

		var monitor = &self.monitors.items[0];
		for (self.monitors.items) |*entry| {
			if (entry.focused) {
				monitor = entry;
				break;
			}
		}

		if (std.mem.eql(u8, kind, "scale")) {
			const steps = [_]f64{ 1.0, 1.25, 1.33, 1.5, 1.75, 2.0 };
			for (steps) |value| {
				if (value < self.scale_min or value > self.scale_max) continue;
				try options.append(allocator, try std.fmt.allocPrint(allocator, "{d}", .{value}));
			}
		} else if (std.mem.eql(u8, kind, "refresh")) {
			for (monitor.modes.items) |mode| {
				try options.append(allocator, try std.fmt.allocPrint(allocator, "{d} Hz", .{@as(i64, @intFromFloat(@round(mode.refresh)))}));
			}
		} else if (std.mem.eql(u8, kind, "font")) {
			for (self.fonts[0..self.font_count]) |size| {
				try options.append(allocator, try std.fmt.allocPrint(allocator, "{d}", .{size}));
			}
		} else {
			var seen: std.ArrayListUnmanaged(ResSize) = .empty;
			defer seen.deinit(allocator);

			for (monitor.modes.items) |mode| {
				var found = false;
				for (seen.items) |item| {
					if (item.width == mode.width and item.height == mode.height) {
						found = true;
						break;
					}
				}
				if (found) continue;

				try seen.append(allocator, .{ .width = mode.width, .height = mode.height });
				try options.append(allocator, try std.fmt.allocPrint(allocator, "{d}x{d}", .{ mode.width, mode.height }));
			}
		}

		return options;
	}

	pub fn detect(self: *Screen) void {
		const target = self.settings orelse return;
		if (self.monitors.items.len == 0) return;

		for (self.monitors.items) |monitor| {
			const text = std.fmt.allocPrint(self.allocator, "{d}x{d}@{d:.2}Hz", .{ monitor.width, monitor.height, monitor.refresh }) catch continue;
			defer self.allocator.free(text);

			target.setOutput(monitor.name, text, monitor.scale);
		}
	}

	pub fn key(self: *Screen, name: []const u8) void {
		self.keyboard = true;
		if (std.mem.eql(u8, name, "up")) {
			self.row = @mod(self.row - 1 + 4, 4);
			self.step = 0;
		} else if (std.mem.eql(u8, name, "down")) {
			self.row = @mod(self.row + 1, 4);
			self.step = 0;
		} else if (std.mem.eql(u8, name, "left")) {
			self.step = @max(0, self.step - 1);
		} else if (std.mem.eql(u8, name, "right")) {
			self.step += 1;
		} else if (std.mem.eql(u8, name, "enter")) {
			self.apply();
		}

		self.hub.publish();
	}

	fn apply(self: *Screen) void {
		const target = self.settings orelse return;
		if (self.monitors.items.len == 0) return;

		var monitor = &self.monitors.items[0];
		for (self.monitors.items) |*entry| {
			if (entry.focused) {
				monitor = entry;
				break;
			}
		}

		const kind = @mod(self.row, 4);
		const step: usize = if (self.step < 0) 0 else @intCast(self.step);

		if (kind == 0) {
			defer self.reloadHyprland();

			const grid: i64 = 120;
			const low: i64 = @intFromFloat(@ceil(self.scale_min * @as(f64, @floatFromInt(grid))));
			const high: i64 = @intFromFloat(@floor(self.scale_max * @as(f64, @floatFromInt(grid))));

			var valid: [256]f64 = undefined;
			var count: usize = 0;

			var candidate = low;
			while (candidate <= high and count < valid.len) : (candidate += 1) {
				if (@rem(monitor.width * grid, candidate) != 0) continue;
				if (@rem(monitor.height * grid, candidate) != 0) continue;

				valid[count] = @as(f64, @floatFromInt(candidate)) / @as(f64, @floatFromInt(grid));
				count += 1;
			}

			if (count == 0) return;
			target.setOutput(monitor.name, null, valid[step % count]);
		} else if (kind == 1) {
			defer self.reloadHyprland();
			var modes: std.ArrayListUnmanaged(Mode) = .empty;
			defer modes.deinit(self.allocator);

			for (monitor.modes.items) |mode| {
				if (mode.width == monitor.width and mode.height == monitor.height) modes.append(self.allocator, mode) catch {};
			}

			std.mem.sort(Mode, modes.items, {}, struct {
				fn less(_: void, a: Mode, b: Mode) bool {
					return a.refresh > b.refresh;
				}
			}.less);

			if (modes.items.len == 0) return;
			const mode = modes.items[step % modes.items.len];

			const text = std.fmt.allocPrint(self.allocator, "{d}x{d}@{d:.2}Hz", .{ mode.width, mode.height, mode.refresh }) catch return;
			defer self.allocator.free(text);

			target.setOutput(monitor.name, text, null);
		} else if (kind == 2) {
			if (self.font_count == 0) return;
			target.setFontSize(self.fonts[step % self.font_count]);
		} else {
			if (monitor.modes.items.len == 0) return;

			var sizes: [16]struct { width: i64, height: i64 } = undefined;
			var count: usize = 0;

			for (monitor.modes.items) |mode| {
				var seen = false;
				for (sizes[0..count]) |size| {
					if (size.width == mode.width and size.height == mode.height) {
						seen = true;
						break;
					}
				}
				if (seen or count == sizes.len) continue;

				sizes[count] = .{ .width = mode.width, .height = mode.height };
				count += 1;
			}

			if (count == 0) return;
			const picked = sizes[step % count];

			var best = monitor.modes.items[0];
			for (monitor.modes.items) |mode| {
				if (mode.width != picked.width or mode.height != picked.height) continue;
				if (mode.refresh > best.refresh) best = mode;
			}

			const text = std.fmt.allocPrint(self.allocator, "{d}x{d}@{d:.2}Hz", .{ best.width, best.height, best.refresh }) catch return;
			defer self.allocator.free(text);

			target.setOutput(monitor.name, text, null);
		}
	}

	fn reloadHyprland(self: *Screen) void {
		const result = exec.run(self.io, self.allocator, &.{ "hyprctl", "reload" }) catch return;
		result.deinit(self.allocator);
	}

	fn panelLocked(self: *Screen, arena: Allocator) !PanelOut {
		const names = [_][]const u8{ "scale", "refresh", "font", "resolution" };
		var options: std.ArrayListUnmanaged([]const u8) = .empty;

		if (self.monitors.items.len == 0) {
			return .{ .row = 0, .step = 0, .rows = &names, .cursor = names[0], .keyboard = false, .options = &.{}, .selected = -1, .value = "", .selectedRow = &.{}, .groups = &.{} };
		}

		const monitor = &self.monitors.items[0];
		const kind = names[@intCast(@mod(self.row, 4))];

		if (std.mem.eql(u8, kind, "scale")) {
			const steps = [_]f64{ 1.0, 1.25, 1.33, 1.5, 1.75, 2.0 };
			for (steps) |value| {
				if (value < self.scale_min or value > self.scale_max) continue;
				try options.append(arena, try std.fmt.allocPrint(arena, "{d}", .{value}));
			}
		} else if (std.mem.eql(u8, kind, "refresh")) {
			for (try self.optionsFor(arena, monitor, "refresh")) |option| try options.append(arena, option);
		} else if (std.mem.eql(u8, kind, "font")) {
			for (try self.optionsFor(arena, monitor, "font")) |option| try options.append(arena, option);
		} else {
			var seen: std.ArrayListUnmanaged(ResSize) = .empty;
			for (monitor.modes.items) |mode| {
				var found = false;
				for (seen.items) |item| {
					if (item.width == mode.width and item.height == mode.height) {
						found = true;
						break;
					}
				}
				if (found) continue;

				try seen.append(arena, .{ .width = mode.width, .height = mode.height });
				try options.append(arena, try std.fmt.allocPrint(arena, "{d}x{d}", .{ mode.width, mode.height }));
			}
		}

		const step: usize = if (options.items.len == 0) 0 else @intCast(@mod(self.step, @as(i64, @intCast(options.items.len))));
		self.step = @intCast(step);

		const selected = self.currentLocked(kind, monitor, options.items);

		var groups: std.ArrayListUnmanaged(GroupOut) = .empty;
		var selected_rows: std.ArrayListUnmanaged(i64) = .empty;

		const kinds = [_][]const u8{ "scale", "refresh", "font" };
		const titles = [_][]const u8{ self.title_scale, self.title_refresh, self.title_font };

		for (kinds, 0..) |group_kind, i| {
			const selected_index = self.currentLocked(group_kind, monitor, &.{});
			var group_options: std.ArrayListUnmanaged([]const u8) = .empty;

			const built = try self.optionsFor(arena, monitor, group_kind);
			for (built) |option| try group_options.append(arena, option);

			const shown: []const u8 = if (selected_index >= 0 and @as(usize, @intCast(selected_index)) < group_options.items.len)
				group_options.items[@intCast(selected_index)]
			else
				"";

			try groups.append(arena, .{
				.label = titles[i],
				.kind = group_kind,
				.options = group_options.items,
				.selected = selected_index,
				.shown = shown,
				.visible = group_options.items.len > 0,
			});
		}

		for (groups.items) |group| try selected_rows.append(arena, group.selected);

		return .{
			.row = self.row,
			.step = self.step,
			.rows = &names,
			.cursor = kind,
			.keyboard = self.keyboard,
			.options = options.items,
			.selected = selected,
			.value = if (options.items.len == 0) "" else options.items[step],
			.selectedRow = selected_rows.items,
			.groups = groups.items,
		};
	}

	fn scaleOptions(self: *Screen, arena: Allocator, monitor: *Monitor) ![]const []const u8 {
		var options: std.ArrayListUnmanaged([]const u8) = .empty;
		const grid: i64 = 120;
		const low: i64 = @intFromFloat(@ceil(self.scale_min * @as(f64, @floatFromInt(grid))));
		const high: i64 = @intFromFloat(@floor(self.scale_max * @as(f64, @floatFromInt(grid))));

		var step = low;
		while (step <= high) : (step += 1) {
			if (!scaleValid(monitor.width, monitor.height, step)) continue;

			const value = @as(f64, @floatFromInt(step)) / @as(f64, @floatFromInt(grid));
			try options.append(arena, try std.fmt.allocPrint(arena, "{d:.4}", .{value}));
		}

		return options.items;
	}

	fn optionsFor(self: *Screen, arena: Allocator, monitor: *Monitor, kind: []const u8) ![]const []const u8 {
		var options: std.ArrayListUnmanaged([]const u8) = .empty;

		if (std.mem.eql(u8, kind, "scale")) {
			for (try self.scaleOptions(arena, monitor)) |value| try options.append(arena, value);
		} else if (std.mem.eql(u8, kind, "refresh")) {
			var modes: std.ArrayListUnmanaged(Mode) = .empty;
			for (monitor.modes.items) |mode| {
				if (mode.width == monitor.width and mode.height == monitor.height) try modes.append(arena, mode);
			}

			std.mem.sort(Mode, modes.items, {}, struct {
				fn less(_: void, a: Mode, b: Mode) bool {
					return a.refresh > b.refresh;
				}
			}.less);

			for (modes.items) |mode| {
				try options.append(arena, try std.fmt.allocPrint(arena, "{d} Hz", .{@as(i64, @intFromFloat(@round(mode.refresh)))}));
			}
		} else if (std.mem.eql(u8, kind, "font")) {
			for (self.fonts[0..self.font_count]) |size| try options.append(arena, try std.fmt.allocPrint(arena, "{d}", .{size}));
		}

		return options.items;
	}

	fn currentLocked(self: *Screen, kind: []const u8, monitor: *Monitor, options: []const []const u8) i64 {
		_ = options;

		if (std.mem.eql(u8, kind, "scale")) {
			var best: i64 = -1;
			var best_delta: f64 = 1e9;
			var index: i64 = 0;

			const grid: i64 = 120;
			const low: i64 = @intFromFloat(@ceil(self.scale_min * @as(f64, @floatFromInt(grid))));
			const high: i64 = @intFromFloat(@floor(self.scale_max * @as(f64, @floatFromInt(grid))));

			var candidate = low;
			while (candidate <= high) : (candidate += 1) {
				if (!scaleValid(monitor.width, monitor.height, candidate)) continue;

				const value = @as(f64, @floatFromInt(candidate)) / @as(f64, @floatFromInt(grid));
				const delta = @abs(value - monitor.scale);
				if (delta < best_delta) {
					best_delta = delta;
					best = index;
				}

				index += 1;
			}

			return best;
		}

		if (std.mem.eql(u8, kind, "refresh")) {
			var index: i64 = 0;
			var modes: std.ArrayListUnmanaged(Mode) = .empty;
			defer modes.deinit(self.allocator);

			for (monitor.modes.items) |mode| {
				if (mode.width == monitor.width and mode.height == monitor.height) modes.append(self.allocator, mode) catch {};
			}

			std.mem.sort(Mode, modes.items, {}, struct {
				fn less(_: void, a: Mode, b: Mode) bool {
					return a.refresh > b.refresh;
				}
			}.less);

			for (modes.items) |mode| {
				if (@abs(mode.refresh - monitor.refresh) < 0.5) return index;
				index += 1;
			}

			return 0;
		}

		if (std.mem.eql(u8, kind, "font")) {
			const target = if (self.settings) |target_settings| target_settings.font_size else 0;

			for (self.fonts[0..self.font_count], 0..) |size, i| {
				if (size == target) return @intCast(i);
			}

			return 0;
		}

		var index: i64 = 0;
		var seen: std.ArrayListUnmanaged(ResSize) = .empty;
		defer seen.deinit(self.allocator);

		for (monitor.modes.items) |mode| {
			var found = false;
			for (seen.items) |item| {
				if (item.width == mode.width and item.height == mode.height) {
					found = true;
					break;
				}
			}

			if (found) continue;
			seen.append(self.allocator, .{ .width = mode.width, .height = mode.height }) catch return 0;

			if (mode.width == monitor.width and mode.height == monitor.height) return index;
			index += 1;
		}

		return 0;
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
					try resolutions.append(arena, .{ .width = mode.width, .height = mode.height, .label = "", .maxRefresh = 0, .refreshes = &.{} });
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

			var scales: std.ArrayListUnmanaged(f64) = .empty;
			const scale_steps = [_]f64{ 1.0, 1.25, 1.33, 1.5, 1.75, 2.0 };

			for (scale_steps) |value| {
				if (value < self.scale_min or value > self.scale_max) continue;
				try scales.append(arena, value);
			}

			var max_refresh: f64 = 0;
			for (monitor.modes.items) |mode| {
				if (mode.width == monitor.width and mode.height == monitor.height and mode.refresh > max_refresh) max_refresh = mode.refresh;
			}

			for (resolutions.items) |*res| {
				res.label = try std.fmt.allocPrint(arena, "{d}x{d}", .{ res.width, res.height });
				res.maxRefresh = @intFromFloat(@round(res.refreshes[0].refresh));
			}

			if (max_refresh == 0) max_refresh = monitor.refresh;

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
				.scales = scales.items,
			});
		}

		const panel = try self.panelLocked(arena);

		var primary: i64 = 0;
		for (self.monitors.items, 0..) |monitor, i| {
			if (monitor.focused) {
				primary = @intCast(i);
				break;
			}
		}

		const out = Out{ .primary = primary, .monitors = monitors.items, .panel = panel, .raw = self.raw };
		try writer.print("{f}", .{std.json.fmt(out, .{})});
	}
};

const ResSize = struct {
	width: i64,
	height: i64,
};

fn byRefreshDesc(_: void, a: ModeOut, b: ModeOut) bool {
	return a.refresh > b.refresh;
}

fn scaleValid(width: i64, height: i64, step: i64) bool {
	const grid: i64 = 120;
	if (step <= 0) return false;

	return @rem(width * grid, step) == 0 and @rem(height * grid, step) == 0;
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

test "scales that hyprland accepts" {
	try std.testing.expect(scaleValid(2560, 1440, 160));
	try std.testing.expect(!scaleValid(2560, 1440, 180));
	try std.testing.expect(scaleValid(1920, 1080, 120));
	try std.testing.expect(!scaleValid(2560, 1440, 0));
}

test "modes parse from hyprctl labels" {
	const mode = parseMode("2560x1440@165.00Hz") orelse return error.NoMode;
	try std.testing.expectEqual(@as(i64, 2560), mode.width);
	try std.testing.expectEqual(@as(i64, 1440), mode.height);
	try std.testing.expectApproxEqAbs(@as(f64, 165), mode.refresh, 0.01);
	try std.testing.expect(parseMode("nonsense") == null);
}
