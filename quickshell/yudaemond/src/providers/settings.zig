const std = @import("std");
const hubmod = @import("../hub.zig");
const proc = @import("../primitives/proc.zig");
const watch = @import("../primitives/watch.zig");
const setStr = @import("opencode.zig").setStr;

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const Output = struct {
	name: []u8,
	mode: []u8,
	scale: f64,
};

const OutputOut = struct {
	name: []const u8,
	mode: []const u8,
	scale: f64,
};

const Out = struct {
	fontSize: i64,
	iconSize: i64,
	fallbackMode: []const u8,
	fallbackScale: f64,
	outputs: []OutputOut,
	record: []const u8,
};

pub const Settings = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	font_size: i64 = 0,
	icon_size: i64 = 0,
	fallback_mode: []u8 = &.{},
	fallback_scale: f64 = 1,
	outputs: std.ArrayListUnmanaged(Output) = .empty,
	record: []u8 = &.{},

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Settings {
		const self = try allocator.create(Settings);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.scratch = std.heap.ArenaAllocator.init(allocator),
		};

		return self;
	}

	pub fn provider(self: *Settings) hubmod.Provider {
		return .{ .key = "settings", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Settings = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn start(self: *Settings) !void {
		const thread = try std.Thread.spawn(.{}, watchLoop, .{self});
		thread.detach();
	}

	fn path(self: *Settings, allocator: Allocator) []const u8 {
		return std.fmt.allocPrint(allocator, "{s}/.config/quickshell/cache/display.lua", .{proc.home(self.io, allocator)}) catch "/nonexistent";
	}

	fn watchLoop(self: *Settings) void {
		self.reload();
		const file = self.path(self.allocator);
		defer self.allocator.free(file);

		watch.watchFile(self.io, self.allocator, file, self, reloadThunk) catch {};
	}

	fn reloadThunk(ctx: *anyopaque) void {
		const self: *Settings = @ptrCast(@alignCast(ctx));
		self.reload();
	}

	fn reload(self: *Settings) void {
		const file = self.path(self.allocator);
		defer self.allocator.free(file);

		const body = proc.readFile(self.io, self.allocator, file) catch "";
		defer if (body.len > 0) self.allocator.free(body);

		self.mutex.lockUncancelable(self.io);
		setStr(self.allocator, &self.record, body) catch {};
		self.parse(body);
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn parse(self: *Settings, body: []const u8) void {
		for (self.outputs.items) |entry| {
			self.allocator.free(entry.name);
			self.allocator.free(entry.mode);
		}
		self.outputs.clearRetainingCapacity();

		var lines = std.mem.splitScalar(u8, body, '\n');

		while (lines.next()) |raw| {
			const line = std.mem.trim(u8, raw, " \t\r");

			if (startsWithKey(line, "fontSize")) {
				self.font_size = numberAfter(line);
				continue;
			}

			if (startsWithKey(line, "iconSize")) {
				self.icon_size = numberAfter(line);
				continue;
			}

			if (startsWithKey(line, "fallback")) {
				const mode_at = std.mem.indexOf(u8, line, "mode") orelse 0;
				const mode = quoted(line[mode_at..]) orelse "";
				const scale = scaleAfter(line);

				setStr(self.allocator, &self.fallback_mode, mode) catch {};
				self.fallback_scale = scale;
				continue;
			}

			if (std.mem.indexOf(u8, line, "[\"")) |at| {
				const close = std.mem.indexOfScalarPos(u8, line, at + 2, '"') orelse continue;
				const name = line[at + 2 .. close];
				const mode_at = std.mem.indexOf(u8, line[close..], "mode") orelse continue;
				const mode = quoted(line[close + mode_at ..]) orelse "";
				const scale = scaleAfter(line);

				self.outputs.append(self.allocator, .{
					.name = self.allocator.dupe(u8, name) catch continue,
					.mode = self.allocator.dupe(u8, mode) catch continue,
					.scale = scale,
				}) catch continue;
			}
		}
	}

	pub fn setFontSize(self: *Settings, size: i64) void {
		self.mutex.lockUncancelable(self.io);
		self.font_size = @max(1, size);
		self.renderToFile();
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	pub fn setOutput(self: *Settings, name: []const u8, mode: ?[]const u8, scale: ?f64) void {
		self.mutex.lockUncancelable(self.io);

		var found = false;
		for (self.outputs.items) |*entry| {
			if (!std.mem.eql(u8, entry.name, name)) continue;

			if (mode) |value| setStr(self.allocator, &entry.mode, value) catch {};
			if (scale) |value| entry.scale = value;
			found = true;
			break;
		}

		if (!found) {
			self.outputs.append(self.allocator, .{
				.name = self.allocator.dupe(u8, name) catch {
					self.mutex.unlock(self.io);
					return;
				},
				.mode = self.allocator.dupe(u8, mode orelse "") catch {
					self.mutex.unlock(self.io);
					return;
				},
				.scale = scale orelse 1,
			}) catch {
				self.mutex.unlock(self.io);
				return;
			};
		}

		self.renderToFile();
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn renderToFile(self: *Settings) void {
		var out: std.Io.Writer.Allocating = .init(self.allocator);
		defer out.deinit();

		out.writer.print("return {{\n\tfontSize = {d},\n\ticonSize = {d},\n\tfallback = {{ mode = \"{s}\", scale = {d:.6} }},\n\toutputs = {{\n", .{
			self.font_size,
			self.icon_size,
			self.fallback_mode,
			self.fallback_scale,
		}) catch return;

		for (self.outputs.items) |entry| {
			out.writer.print("\t\t[\"{s}\"] = {{ mode = \"{s}\", scale = {d:.6} }},\n", .{ entry.name, entry.mode, entry.scale }) catch return;
		}

		out.writer.print("\t}},\n}}\n", .{}) catch return;

		setStr(self.allocator, &self.record, out.written()) catch {};

		const file = self.path(self.allocator);
		defer self.allocator.free(file);

		proc.writeFileAtomic(self.io, self.allocator, file, out.written()) catch {};
	}

	fn render(self: *Settings, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);
		const arena = self.scratch.allocator();

		var outputs: std.ArrayListUnmanaged(OutputOut) = .empty;
		for (self.outputs.items) |entry| {
			try outputs.append(arena, .{ .name = entry.name, .mode = entry.mode, .scale = entry.scale });
		}

		const out = Out{
			.fontSize = self.font_size,
			.iconSize = self.icon_size,
			.fallbackMode = self.fallback_mode,
			.fallbackScale = self.fallback_scale,
			.outputs = outputs.items,
			.record = self.record,
		};

		try writer.print("{f}", .{std.json.fmt(out, .{})});
	}
};

fn startsWithKey(line: []const u8, key: []const u8) bool {
	return std.mem.startsWith(u8, line, key);
}

fn numberAfter(line: []const u8) i64 {
	const eq = std.mem.indexOfScalar(u8, line, '=') orelse return 0;
	const rest = std.mem.trim(u8, line[eq + 1 ..], " \t,");

	return std.fmt.parseInt(i64, rest[0..digitLength(rest)], 10) catch 0;
}

fn digitLength(text: []const u8) usize {
	var index: usize = 0;
	while (index < text.len and (std.ascii.isDigit(text[index]) or text[index] == '-')) : (index += 1) {}

	return index;
}

fn quoted(text: []const u8) ?[]const u8 {
	const open = std.mem.indexOfScalar(u8, text, '"') orelse return null;
	const close = std.mem.indexOfScalarPos(u8, text, open + 1, '"') orelse return null;

	return text[open + 1 .. close];
}

fn scaleAfter(line: []const u8) f64 {
	const at = std.mem.indexOf(u8, line, "scale") orelse return 1;
	const rest = line[at + "scale".len ..];
	const eq = std.mem.indexOfScalar(u8, rest, '=') orelse return 1;
	const value = std.mem.trim(u8, rest[eq + 1 ..], " \t,}");

	var end: usize = 0;
	while (end < value.len and (std.ascii.isDigit(value[end]) or value[end] == '.')) : (end += 1) {}

	return std.fmt.parseFloat(f64, value[0..end]) catch 1;
}

test "lua display state parses" {
	const body = "return {\n\tfontSize = 12,\n\ticonSize = 10,\n\tfallback = { mode = \"2560x1440@144.00Hz\", scale = 1.5 },\n\toutputs = {\n\t\t[\"DP-2\"] = { mode = \"2560x1440@240.00Hz\", scale = 1.25 },\n\t},\n}";

	var hub: hubmod.Hub = .{ .allocator = std.testing.allocator, .io = std.Io.Threaded.global_single_threaded.io() };
	const self = try Settings.create(std.testing.allocator, hub.io, &hub);
	defer {
		for (self.outputs.items) |entry| {
			std.testing.allocator.free(entry.name);
			std.testing.allocator.free(entry.mode);
		}
		self.outputs.deinit(std.testing.allocator);
		std.testing.allocator.free(self.fallback_mode);
		std.testing.allocator.destroy(self);
	}

	self.mutex.lockUncancelable(self.io);
	self.parse(body);
	self.mutex.unlock(self.io);

	try std.testing.expectEqual(@as(i64, 12), self.font_size);
	try std.testing.expectEqual(@as(i64, 10), self.icon_size);
	try std.testing.expectEqualStrings("2560x1440@144.00Hz", self.fallback_mode);
	try std.testing.expectApproxEqAbs(@as(f64, 1.5), self.fallback_scale, 0.001);
	try std.testing.expectEqual(@as(usize, 1), self.outputs.items.len);
	try std.testing.expectApproxEqAbs(@as(f64, 1.25), self.outputs.items[0].scale, 0.001);
}
