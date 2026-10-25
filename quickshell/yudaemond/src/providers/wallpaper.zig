const std = @import("std");
const hubmod = @import("../hub.zig");
const exec = @import("../primitives/exec.zig");
const proc = @import("../primitives/proc.zig");
const sleep = @import("../primitives/sleep.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const default_dir = "~/Documents/Wallpaper";
const max_depth = 2;
const transition = "fade";
const transition_ms = 400;
const transition_fps = 60;
const extensions = [_][]const u8{ ".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".avif" };

const Entry = struct {
	path: []u8,
	name: []u8,
};

const EntryOut = struct {
	path: []const u8,
	name: []const u8,
};

const Out = struct {
	dir: []const u8,
	active: []const u8,
	list: []EntryOut,
};

pub const Wallpaper = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	dir: []u8 = &.{},
	active: []u8 = &.{},
	entries: std.ArrayListUnmanaged(Entry) = .empty,
	seen_at: std.Io.Timestamp = .zero,

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Wallpaper {
		const self = try allocator.create(Wallpaper);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.scratch = std.heap.ArenaAllocator.init(allocator),
		};

		return self;
	}

	pub fn provider(self: *Wallpaper) hubmod.Provider {
		return .{ .key = "wallpaper", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Wallpaper = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn start(self: *Wallpaper) !void {
		self.reload();

		const thread = try std.Thread.spawn(.{}, loop, .{self});
		thread.detach();
	}

	fn loop(self: *Wallpaper) void {
		while (true) {
			sleep.ms(2000);
			self.watch();
		}
	}

	fn watch(self: *Wallpaper) void {
		const settings = settingsPath(self.io, self.allocator) catch return;
		defer self.allocator.free(settings);

		const stat = std.Io.Dir.cwd().statFile(self.io, settings, .{}) catch return;

		if (stat.mtime.nanoseconds == self.seen_at.nanoseconds) return;

		self.reload();
	}

	pub fn reload(self: *Wallpaper) void {
		const settings = settingsPath(self.io, self.allocator) catch return;
		defer self.allocator.free(settings);

		const body = proc.readFile(self.io, self.allocator, settings) catch "";
		defer if (body.len > 0) self.allocator.free(body);

		const stat = std.Io.Dir.cwd().statFile(self.io, settings, .{}) catch null;

		var dir: []const u8 = value(body, "wallpaperDir") orelse default_dir;
		if (dir.len == 0) dir = default_dir;

		const active: []const u8 = value(body, "wallpaper") orelse "";

		var next: std.ArrayListUnmanaged(Entry) = .empty;

		const home = proc.home(self.io, self.allocator);
		const expanded = expand(self.allocator, home, dir) catch self.allocator.dupe(u8, dir) catch return;
		defer self.allocator.free(expanded);

		self.scanDir(expanded, &next, 0);

		std.mem.sort(Entry, next.items, {}, struct {
			fn less(_: void, a: Entry, b: Entry) bool {
				return std.mem.lessThan(u8, a.path, b.path);
			}
		}.less);

		self.mutex.lockUncancelable(self.io);
		for (self.entries.items) |entry| {
			self.allocator.free(entry.path);
			self.allocator.free(entry.name);
		}
		self.entries.deinit(self.allocator);
		self.entries = next;
		self.setStr(&self.dir, dir);
		self.setStr(&self.active, active);
		if (stat) |info| self.seen_at = info.mtime;
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn scanDir(self: *Wallpaper, path: []const u8, out: *std.ArrayListUnmanaged(Entry), depth: usize) void {
		var dir = std.Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true }) catch return;
		defer dir.close(self.io);

		var it = dir.iterate();

		while (it.next(self.io) catch null) |item| {
			const child = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ path, item.name }) catch continue;
			defer self.allocator.free(child);

			if (item.kind == .directory) {
				if (depth + 1 < max_depth) self.scanDir(child, out, depth + 1);
				continue;
			}

			if (item.kind != .file and item.kind != .sym_link) continue;
			if (!supported(item.name)) continue;

			out.append(self.allocator, .{
				.path = self.allocator.dupe(u8, child) catch continue,
				.name = nameOf(self.allocator, item.name) catch continue,
			}) catch continue;
		}
	}

	pub fn apply(self: *Wallpaper, path: []const u8, band: f64) void {
		if (path.len == 0) return;

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();

		const duration = std.fmt.allocPrint(allocator, "{d:.3}", .{@as(f64, @floatFromInt(transition_ms)) / 1000.0}) catch return;
		const fps = std.fmt.allocPrint(allocator, "{d}", .{transition_fps}) catch return;

		var argv: std.ArrayList([]const u8) = .empty;

		for ([_][]const u8{ "awww", "img", "--transition-type", transition, "--transition-duration", duration, "--transition-fps", fps }) |arg|
			argv.append(allocator, arg) catch return;

		if (band > 0) {
			const text = std.fmt.allocPrint(allocator, "{d}", .{@as(i64, @intFromFloat(@ceil(band)))}) catch return;
			argv.append(allocator, "--ink-band") catch return;
			argv.append(allocator, text) catch return;
		}

		argv.append(allocator, path) catch return;

		const result = exec.run(self.io, self.allocator, argv.items) catch return;
		result.deinit(self.allocator);

		self.save(path);
	}

	fn save(self: *Wallpaper, path: []const u8) void {
		const settings = settingsPath(self.io, self.allocator) catch return;
		defer self.allocator.free(settings);

		self.mutex.lockUncancelable(self.io);
		const dir = self.allocator.dupe(u8, self.dir) catch {
			self.mutex.unlock(self.io);
			return;
		};
		self.mutex.unlock(self.io);
		defer self.allocator.free(dir);

		const body = std.fmt.allocPrint(self.allocator, "return {{\n    wallpaper = \"{s}\",\n    wallpaperDir = \"{s}\",\n}}\n", .{ path, dir }) catch return;
		defer self.allocator.free(body);

		proc.writeFileAtomic(self.io, self.allocator, settings, body) catch return;

		self.mutex.lockUncancelable(self.io);
		self.setStr(&self.active, path);
		if (std.Io.Dir.cwd().statFile(self.io, settings, .{})) |info| {
			self.seen_at = info.mtime;
		} else |_| {}
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn setStr(self: *Wallpaper, slot: *[]u8, text: []const u8) void {
		const copy = self.allocator.dupe(u8, text) catch return;
		self.allocator.free(slot.*);
		slot.* = copy;
	}

	fn render(self: *Wallpaper, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);
		const arena = self.scratch.allocator();

		var list: std.ArrayListUnmanaged(EntryOut) = .empty;

		for (self.entries.items) |entry| {
			try list.append(arena, .{ .path = entry.path, .name = entry.name });
		}

		try writer.print("{f}", .{std.json.fmt(Out{
			.dir = self.dir,
			.active = self.active,
			.list = list.items,
		}, .{})});
	}
};

fn settingsPath(io: Io, allocator: Allocator) ![]u8 {
	return std.fmt.allocPrint(allocator, "{s}/.config/quickshell/cache/settings.lua", .{proc.home(io, allocator)});
}

fn value(body: []const u8, key: []const u8) ?[]const u8 {
	var at: usize = 0;

	while (std.mem.indexOfPos(u8, body, at, key)) |found| {
		at = found + key.len;
		if (at >= body.len) return null;

		var index = at;
		while (index < body.len and (body[index] == ' ' or body[index] == '\t')) index += 1;
		if (index >= body.len or body[index] != '=') continue;

		index += 1;
		while (index < body.len and (body[index] == ' ' or body[index] == '\t')) index += 1;
		if (index >= body.len) return null;
		if (body[index] != '"' and body[index] != '\'') return null;

		const quote = body[index];
		const start = index + 1;
		const end = std.mem.indexOfScalarPos(u8, body, start, quote) orelse return null;

		return body[start..end];
	}

	return null;
}

fn expand(allocator: Allocator, home: []const u8, dir: []const u8) ![]u8 {
	if (std.mem.startsWith(u8, dir, "~/")) return std.fmt.allocPrint(allocator, "{s}/{s}", .{ home, dir[2..] });

	return allocator.dupe(u8, dir);
}

fn supported(name: []const u8) bool {
	const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return false;
	const lower = name[dot..];

	for (extensions) |ext| {
		if (std.ascii.eqlIgnoreCase(lower, ext)) return true;
	}

	return false;
}

fn nameOf(allocator: Allocator, file: []const u8) ![]u8 {
	const dot = std.mem.lastIndexOfScalar(u8, file, '.') orelse file.len;
	const base = if (dot == 0) file else file[0..dot];
	const trimmed = std.mem.trim(u8, base, " -_");

	const out = try allocator.alloc(u8, trimmed.len);

	for (trimmed, 0..) |ch, index| {
		out[index] = if (ch == '-' or ch == '_') ' ' else ch;
	}

	return out;
}

test "settings values are read from the lua the shell writes" {
	const body =
		\\return {
		\\    wallpaper = "/home/me/wall.png",
		\\    wallpaperDir = "~/Pictures/Walls",
		\\}
	;

	try std.testing.expectEqualStrings("/home/me/wall.png", value(body, "wallpaper").?);
	try std.testing.expectEqualStrings("~/Pictures/Walls", value(body, "wallpaperDir").?);
	try std.testing.expect(value(body, "missing") == null);
	try std.testing.expectEqualStrings("/home/me/wall.png", value(body, "wallpaper").?);
}

test "wallpaper files are the ones the picker shows" {
	try std.testing.expect(supported("a.PNG"));
	try std.testing.expect(supported("b.jpeg"));
	try std.testing.expect(!supported("c.txt"));
	try std.testing.expect(!supported("noext"));
}

test "the scan lists the wallpapers under the directory" {
	const io = std.Io.Threaded.global_single_threaded.io();

	var hub: hubmod.Hub = .{ .allocator = std.testing.allocator, .io = io };
	const self = try Wallpaper.create(std.testing.allocator, io, &hub);
	defer {
		for (self.entries.items) |entry| {
			std.testing.allocator.free(entry.path);
			std.testing.allocator.free(entry.name);
		}
		self.entries.deinit(std.testing.allocator);
		std.testing.allocator.free(self.dir);
		std.testing.allocator.free(self.active);
		self.scratch.deinit();
		std.testing.allocator.destroy(self);
	}

	var tmp = std.testing.tmpDir(.{});
	defer tmp.cleanup();

	try tmp.dir.writeFile(io, .{ .sub_path = "one.png", .data = "" });
	try tmp.dir.writeFile(io, .{ .sub_path = "two.JPG", .data = "" });
	try tmp.dir.writeFile(io, .{ .sub_path = "notes.txt", .data = "" });
	try tmp.dir.createDirPath(io, "inner");
	try tmp.dir.writeFile(io, .{ .sub_path = "inner/three-wall.webp", .data = "" });

	var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
	const len = try tmp.dir.realPath(io, &buffer);

	var out: std.ArrayListUnmanaged(Entry) = .empty;
	defer {
		for (out.items) |entry| {
			std.testing.allocator.free(entry.path);
			std.testing.allocator.free(entry.name);
		}
		out.deinit(std.testing.allocator);
	}

	self.scanDir(buffer[0..len], &out, 0);

	try std.testing.expectEqual(@as(usize, 3), out.items.len);

	var names: [3][]const u8 = undefined;
	for (out.items, 0..) |entry, index| names[index] = entry.name;

	std.mem.sort([]const u8, &names, {}, struct {
		fn less(_: void, a: []const u8, b: []const u8) bool {
			return std.mem.lessThan(u8, a, b);
		}
	}.less);

	try std.testing.expectEqualStrings("one", names[0]);
	try std.testing.expectEqualStrings("three wall", names[1]);
	try std.testing.expectEqualStrings("two", names[2]);
}
