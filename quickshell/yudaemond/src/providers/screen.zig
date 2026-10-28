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

const Apply = struct {
	kind: []u8,
	value: []u8,
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
	pending: bool,
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
	apply_mutex: std.Io.Mutex = .init,
	queued: ?Apply = null,
	pending: std.atomic.Value(bool) = .init(false),
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

		const apply_thread = try std.Thread.spawn(.{}, applyLoop, .{self});
		apply_thread.detach();
	}

	fn applyLoop(self: *Screen) void {
		while (true) {
			const item = self.takeApply() orelse {
				if (self.clearPending()) self.hub.publish();
				sleep.ms(10);
				continue;
			};

			self.applyValue(item.kind, item.value);

			self.allocator.free(item.kind);
			self.allocator.free(item.value);

			self.hub.publish();
		}
	}

	fn takeApply(self: *Screen) ?Apply {
		self.apply_mutex.lockUncancelable(self.io);
		defer self.apply_mutex.unlock(self.io);

		const item = self.queued;
		self.queued = null;
		return item;
	}

	fn clearPending(self: *Screen) bool {
		self.apply_mutex.lockUncancelable(self.io);
		defer self.apply_mutex.unlock(self.io);

		if (self.queued != null) return false;

		return self.pending.swap(false, .monotonic);
	}

	fn queueApply(self: *Screen, kind: []const u8, value: []const u8) void {
		const kind_copy = self.allocator.dupe(u8, kind) catch return;
		const value_copy = self.allocator.dupe(u8, value) catch {
			self.allocator.free(kind_copy);
			return;
		};

		self.apply_mutex.lockUncancelable(self.io);

		if (self.queued) |old| {
			self.allocator.free(old.kind);
			self.allocator.free(old.value);
		}

		self.queued = .{ .kind = kind_copy, .value = value_copy };
		self.pending.store(true, .monotonic);

		self.apply_mutex.unlock(self.io);
	}

	fn loop(self: *Screen) void {
		self.poll();

		while (true) {
			sleep.ms(500);
			self.poll();
		}
	}

	fn poll(self: *Screen) void {
		const body = hypr.request(self.io, self.allocator, "j/monitors") catch {
			return;
		};
		defer self.allocator.free(body);

		self.mutex.lockUncancelable(self.io);
		const unchanged = self.raw.len > 0 and std.mem.eql(u8, self.raw, body);
		self.mutex.unlock(self.io);

		if (unchanged) return;

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

	const Snap = struct {
		name: []const u8,
		width: i64,
		height: i64,
		refresh: f64,
		scale: f64,
		modes: []const Mode,
	};

	fn focusedSnap(self: *Screen, arena: Allocator) ?Snap {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		return self.focusedSnapLocked(arena);
	}

	fn focusedSnapLocked(self: *Screen, arena: Allocator) ?Snap {
		if (self.monitors.items.len == 0) return null;

		var monitor: *Monitor = &self.monitors.items[0];
		for (self.monitors.items) |*entry| {
			if (entry.focused) {
				monitor = entry;
				break;
			}
		}

		const modes = arena.alloc(Mode, monitor.modes.items.len) catch return null;
		@memcpy(modes, monitor.modes.items);

		return .{
			.name = arena.dupe(u8, monitor.name) catch return null,
			.width = monitor.width,
			.height = monitor.height,
			.refresh = monitor.refresh,
			.scale = monitor.scale,
			.modes = modes,
		};
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
		self.keyboard = false;

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		if (self.focusedSnap(arena.allocator())) |snap| {
			if (self.optionsFor(arena.allocator(), snap, kind)) |options| {
				for (options, 0..) |option, index| {
					if (std.mem.eql(u8, option, value)) {
						self.step = @intCast(index);
						break;
					}
				}
			} else |_| {}
		}

		self.queueApply(kind, value);
		self.hub.publish();
	}

	fn bestMode(self: *Screen, monitor: *Monitor, width: i64, height: i64) ?Mode {
		_ = self;
		var best: ?Mode = null;

		for (monitor.modes.items) |mode| {
			if (mode.width != width or mode.height != height) continue;
			if (best == null or mode.refresh > best.?.refresh) best = mode;
		}

		return best;
	}

	fn refreshOf(text: []const u8) ?f64 {
		var index: usize = 0;

		while (index < text.len and (text[index] == ' ' or text[index] == '\t')) index += 1;

		const from = index;
		while (index < text.len and text[index] >= '0' and text[index] <= '9') index += 1;
		if (index == from) return null;

		return std.fmt.parseFloat(f64, text[from..index]) catch null;
	}

	fn sizeOf(text: []const u8) ?struct { width: i64, height: i64 } {
		const x = std.mem.indexOfScalar(u8, text, 'x') orelse return null;

		const width = std.fmt.parseInt(i64, std.mem.trim(u8, text[0..x], " "), 10) catch return null;
		const height = std.fmt.parseInt(i64, std.mem.trim(u8, text[x + 1 ..], " "), 10) catch return null;

		if (width <= 0 or height <= 0) return null;

		return .{ .width = width, .height = height };
	}

	fn settingsTarget(self: *Screen, monitor: *Monitor) ?*settings.Settings {
		const target = self.settings orelse return null;
		if (monitor.name.len == 0) return null;
		return target;
	}

	fn applyValue(self: *Screen, kind: []const u8, value: []const u8) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const snap = self.focusedSnap(arena.allocator()) orelse return;
		const target = self.settings orelse return;
		if (snap.name.len == 0) return;

		if (std.mem.eql(u8, kind, "font")) {
			const size = std.fmt.parseInt(i64, std.mem.trim(u8, value, " "), 10) catch return;
			target.setFontSize(size);
			return;
		}

		if (std.mem.eql(u8, kind, "scale")) {
			const number = std.fmt.parseFloat(f64, std.mem.trim(u8, value, " ")) catch return;
			if (number <= 0) return;

			target.setOutput(snap.name, null, number);

			const mode = std.fmt.allocPrint(arena.allocator(), "{d}x{d}@{d:.2}", .{ snap.width, snap.height, snap.refresh }) catch return;
			self.applyMonitor(snap.name, mode, number);

			if (!self.waitApplied(snap.name, null, number, 60)) self.reload();

			self.poll();
			return;
		}

		if (std.mem.eql(u8, kind, "refresh")) {
			const wanted = refreshOf(value) orelse return;

			var best: ?Mode = null;
			var best_delta: f64 = 1e9;

			for (snap.modes) |mode| {
				if (mode.width != snap.width or mode.height != snap.height) continue;

				const delta = @abs(@round(mode.refresh) - wanted);
				if (delta < best_delta) {
					best_delta = delta;
					best = mode;
				}
			}

			const mode = best orelse return;
			const text = std.fmt.allocPrint(arena.allocator(), "{d}x{d}@{d:.2}Hz", .{ mode.width, mode.height, mode.refresh }) catch return;

			target.setOutput(snap.name, text, null);
			self.applyMonitor(snap.name, text, snap.scale);

			if (!self.waitApplied(snap.name, mode.refresh, null, 40)) self.reload();

			self.poll();
			return;
		}

		const size = sizeOf(value) orelse return;

		var best: ?Mode = null;
		for (snap.modes) |mode| {
			if (mode.width != size.width or mode.height != size.height) continue;
			if (best == null or mode.refresh > best.?.refresh) best = mode;
		}

		const mode = best orelse return;
		const text = std.fmt.allocPrint(arena.allocator(), "{d}x{d}@{d:.2}Hz", .{ mode.width, mode.height, mode.refresh }) catch return;

		target.setOutput(snap.name, text, null);
		self.applyMonitor(snap.name, text, snap.scale);

		const jump: usize = if (mode.width != snap.width or mode.height != snap.height) 80 else 40;

		if (!self.waitApplied(snap.name, mode.refresh, null, jump)) self.reload();

		self.poll();
	}

	fn apply(self: *Screen) void {
		if (self.monitors.items.len == 0) return;

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const snap = self.focusedSnap(arena.allocator()) orelse return;

		const names = [_][]const u8{ "scale", "refresh", "font", "resolution" };
		const kind = names[@intCast(@mod(self.row, 4))];
		const options = self.optionsFor(arena.allocator(), snap, kind) catch return;

		if (options.len == 0) return;

		const step: usize = @intCast(@mod(self.step, @as(i64, @intCast(options.len))));
		self.step = @intCast(step);

		self.queueApply(kind, options[step]);
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

	fn currentMode(self: *Screen, monitor: *Monitor) ![]u8 {
		return std.fmt.allocPrint(self.allocator, "{d}x{d}@{d:.2}", .{ monitor.width, monitor.height, monitor.refresh });
	}

	fn reload(self: *Screen) void {
		const result = exec.run(self.io, self.allocator, &.{ "hyprctl", "reload" }) catch return;
		result.deinit(self.allocator);
	}

	fn liveState(self: *Screen, name: []const u8) ?struct { refresh: f64, scale: f64 } {
		const body = hypr.request(self.io, self.allocator, "j/monitors") catch return null;
		defer self.allocator.free(body);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const parsed = json.parse(arena.allocator(), body) catch return null;

		for (json.list(parsed.value)) |entry| {
			if (!std.mem.eql(u8, json.textAt(entry, "name"), name)) continue;

			return .{ .refresh = json.numberAt(entry, "refreshRate"), .scale = json.numberAt(entry, "scale") };
		}

		return null;
	}

	fn waitApplied(self: *Screen, name: []const u8, refresh: ?f64, scale: ?f64, limit: usize) bool {
		var tries: usize = 0;

		while (tries < limit) : (tries += 1) {
			if (self.liveState(name)) |live| {
				const refresh_ok = if (refresh) |want| @abs(live.refresh - want) < 1.0 else true;
				const scale_ok = if (scale) |want| @abs(live.scale - want) < 0.01 else true;

				if (refresh_ok and scale_ok) return true;
			}

			sleep.ms(80);
		}

		return false;
	}

	fn applyMonitor(self: *Screen, name: []const u8, mode: []const u8, scale: f64) void {
		const script = std.fmt.allocPrint(self.allocator, "hl.monitor({{output=\"{s}\", mode=\"{s}\", position=\"auto\", scale=\"{d:.4}\"}})", .{ name, mode, scale }) catch return;
		defer self.allocator.free(script);

		const result = exec.run(self.io, self.allocator, &.{ "hyprctl", "eval", script }) catch return;
		result.deinit(self.allocator);
	}

	fn panelLocked(self: *Screen, arena: Allocator) !PanelOut {
		const names = [_][]const u8{ "scale", "refresh", "font", "resolution" };
		var options: std.ArrayListUnmanaged([]const u8) = .empty;

		const kind = names[@intCast(@mod(self.row, 4))];
		const pending = self.pending.load(.monotonic);

		const snap = self.focusedSnapLocked(arena) orelse {
			return .{ .row = 0, .step = 0, .rows = &names, .cursor = names[0], .keyboard = false, .pending = pending, .options = &.{}, .selected = -1, .value = "", .selectedRow = &.{}, .groups = &.{} };
		};

		for (try self.optionsFor(arena, snap, kind)) |option| try options.append(arena, option);

		const step: usize = if (options.items.len == 0) 0 else @intCast(@mod(self.step, @as(i64, @intCast(options.items.len))));
		self.step = @intCast(step);

		const selected: i64 = if (pending) @intCast(step) else self.currentLocked(kind, snap, options.items);

		var groups: std.ArrayListUnmanaged(GroupOut) = .empty;
		var selected_rows: std.ArrayListUnmanaged(i64) = .empty;

		const kinds = [_][]const u8{ "scale", "refresh", "font" };
		const titles = [_][]const u8{ self.title_scale, self.title_refresh, self.title_font };

		for (kinds, 0..) |group_kind, i| {
			var group_options: std.ArrayListUnmanaged([]const u8) = .empty;

			const built = try self.optionsFor(arena, snap, group_kind);
			for (built) |option| try group_options.append(arena, option);

			const selected_index: i64 = if (pending and std.mem.eql(u8, group_kind, kind) and group_options.items.len > 0)
				@intCast(step)
			else
				self.currentLocked(group_kind, snap, &.{});

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
			.pending = pending,
			.options = options.items,
			.selected = selected,
			.value = if (options.items.len == 0) "" else options.items[step],
			.selectedRow = selected_rows.items,
			.groups = groups.items,
		};
	}

	fn scaleOptions(self: *Screen, arena: Allocator, monitor: Snap) ![]const []const u8 {
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

	fn optionsFor(self: *Screen, arena: Allocator, monitor: Snap, kind: []const u8) ![]const []const u8 {
		var options: std.ArrayListUnmanaged([]const u8) = .empty;

		if (std.mem.eql(u8, kind, "scale")) {
			for (try self.scaleOptions(arena, monitor)) |value| try options.append(arena, value);
		} else if (std.mem.eql(u8, kind, "refresh")) {
			var modes: std.ArrayListUnmanaged(Mode) = .empty;
			for (monitor.modes) |mode| {
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
		} else {
			var seen: std.ArrayListUnmanaged(ResSize) = .empty;

			for (monitor.modes) |mode| {
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

		return options.items;
	}

	fn currentLocked(self: *Screen, kind: []const u8, monitor: Snap, options: []const []const u8) i64 {
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

			for (monitor.modes) |mode| {
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

		for (monitor.modes) |mode| {
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

test "the newest pick replaces the queued one" {
	const io = std.Io.Threaded.global_single_threaded.io();
	const arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	var screen: Screen = .{ .allocator = std.testing.allocator, .io = io, .hub = undefined, .scratch = arena };

	screen.queueApply("scale", "1.0000");
	screen.queueApply("scale", "1.6667");

	try std.testing.expect(screen.pending.load(.monotonic));

	const item = screen.takeApply() orelse return error.NoPick;
	defer std.testing.allocator.free(item.kind);
	defer std.testing.allocator.free(item.value);

	try std.testing.expectEqualStrings("scale", item.kind);
	try std.testing.expectEqualStrings("1.6667", item.value);
	try std.testing.expect(screen.takeApply() == null);
	try std.testing.expect(screen.clearPending());
	try std.testing.expect(!screen.pending.load(.monotonic));
	try std.testing.expect(!screen.clearPending());
}
