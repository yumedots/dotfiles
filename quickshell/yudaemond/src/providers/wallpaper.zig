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
const extensions = [_][]const u8{ ".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".avif" };

const cache_root = ".cache/quickshell/wallpaper";
const thumb_bin = "/usr/bin/vipsthumbnail";
const thumb_px = 480;
const preview_px = 1280;
const jpeg_quality = 80;

const Entry = struct {
	path: []u8,
	name: []u8,
	key: []u8,
	thumb: []u8,
	preview: []u8,
};

const EntryOut = struct {
	path: []const u8,
	name: []const u8,
	thumb: []const u8,
	preview: []const u8,
};

const Work = struct {
	key: []u8,
	path: []u8,
	thumb: []u8,
	preview: []u8,
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
	cache: []u8 = &.{},
	entries: std.ArrayListUnmanaged(Entry) = .empty,
	seen_at: std.Io.Timestamp = .zero,
	working: std.atomic.Value(bool) = .init(false),

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

		const cache = std.fmt.allocPrint(self.allocator, "{s}/" ++ cache_root, .{home}) catch return;
		defer self.allocator.free(cache);

		std.Io.Dir.cwd().createDirPath(self.io, cache) catch {};

		self.scanDir(expanded, &next, 0);

		std.mem.sort(Entry, next.items, {}, struct {
			fn less(_: void, a: Entry, b: Entry) bool {
				return std.mem.lessThan(u8, a.path, b.path);
			}
		}.less);

		for (next.items) |*entry| self.derive(entry, cache);

		self.mutex.lockUncancelable(self.io);
		for (self.entries.items) |entry| freeEntry(self.allocator, entry);
		self.entries.deinit(self.allocator);
		self.entries = next;
		self.setStr(&self.dir, dir);
		self.setStr(&self.active, active);
		if (self.cache.len == 0) self.cache = self.allocator.dupe(u8, cache) catch &.{};
		if (stat) |info| self.seen_at = info.mtime;
		self.mutex.unlock(self.io);

		self.hub.publish();
		self.prune(cache);
		self.ensureWorker();
	}

	fn derive(self: *Wallpaper, entry: *Entry, cache: []const u8) void {
		entry.thumb = self.derived(cache, entry.key, "thumb");
		entry.preview = self.derived(cache, entry.key, "preview");
	}

	fn derived(self: *Wallpaper, cache: []const u8, key: []const u8, kind: []const u8) []u8 {
		const path = std.fmt.allocPrint(self.allocator, "{s}/{s}-{s}.jpg", .{ cache, key, kind }) catch return &.{};
		if (proc.exists(self.io, path)) return path;

		self.allocator.free(path);
		return self.allocator.dupe(u8, "") catch &.{};
	}

	fn prune(self: *Wallpaper, cache: []const u8) void {
		var keep = std.StringHashMap(void).init(self.allocator);
		defer {
			var keys = keep.keyIterator();
			while (keys.next()) |key| self.allocator.free(key.*);
			keep.deinit();
		}

		self.mutex.lockUncancelable(self.io);
		for (self.entries.items) |entry| {
			for ([_][]const u8{ "thumb", "preview" }) |kind| {
				const name = std.fmt.allocPrint(self.allocator, "{s}-{s}.jpg", .{ entry.key, kind }) catch continue;
				keep.put(name, {}) catch self.allocator.free(name);
			}
		}
		self.mutex.unlock(self.io);

		var dir = std.Io.Dir.cwd().openDir(self.io, cache, .{ .iterate = true }) catch return;
		defer dir.close(self.io);

		var it = dir.iterate();
		while (it.next(self.io) catch null) |item| {
			if (item.kind != .file) continue;
			if (!std.mem.endsWith(u8, item.name, ".jpg")) continue;
			if (std.mem.endsWith(u8, item.name, ".part.jpg")) continue;
			if (keep.contains(item.name)) continue;

			const path = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ cache, item.name }) catch continue;
			defer self.allocator.free(path);
			std.Io.Dir.cwd().deleteFile(self.io, path) catch {};
		}
	}

	fn ensureWorker(self: *Wallpaper) void {
		if (self.working.swap(true, .acquire)) return;

		const thread = std.Thread.spawn(.{}, renderLoop, .{self}) catch {
			self.working.store(false, .release);
			return;
		};
		thread.detach();
	}

	fn renderLoop(self: *Wallpaper) void {
		while (true) {
			var work: std.ArrayListUnmanaged(Work) = .empty;

			self.mutex.lockUncancelable(self.io);
			for (self.entries.items) |entry| {
				if (entry.thumb.len > 0 and entry.preview.len > 0) continue;

				work.append(self.allocator, .{
					.key = self.allocator.dupe(u8, entry.key) catch continue,
					.path = self.allocator.dupe(u8, entry.path) catch continue,
					.thumb = std.fmt.allocPrint(self.allocator, "{s}/{s}-thumb.jpg", .{ self.cache, entry.key }) catch &.{},
					.preview = std.fmt.allocPrint(self.allocator, "{s}/{s}-preview.jpg", .{ self.cache, entry.key }) catch &.{},
				}) catch continue;
			}
			self.mutex.unlock(self.io);

			if (work.items.len == 0) {
				work.deinit(self.allocator);
				break;
			}

			for (work.items) |item| self.renderOne(item);

			for (work.items) |item| {
				self.allocator.free(item.key);
				self.allocator.free(item.path);
				self.allocator.free(item.thumb);
				self.allocator.free(item.preview);
			}
			work.deinit(self.allocator);
		}

		self.working.store(false, .release);
		if (self.missing()) self.ensureWorker();
	}

	fn missing(self: *Wallpaper) bool {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		for (self.entries.items) |entry| {
			if (entry.thumb.len == 0 or entry.preview.len == 0) return true;
		}

		return false;
	}

	fn renderOne(self: *Wallpaper, item: Work) void {
		const thumb = self.convert(item.path, item.thumb, thumb_px);
		const preview = self.convert(item.path, item.preview, preview_px);

		if (!thumb and !preview) return;

		self.mutex.lockUncancelable(self.io);
		for (self.entries.items) |*entry| {
			if (!std.mem.eql(u8, entry.key, item.key)) continue;

			if (thumb and entry.thumb.len == 0) self.setStr(&entry.thumb, item.thumb);
			if (preview and entry.preview.len == 0) self.setStr(&entry.preview, item.preview);
		}
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn convert(self: *Wallpaper, src: []const u8, dest: []const u8, px: u32) bool {
		if (dest.len == 0) return false;
		if (proc.exists(self.io, dest)) return true;

		const size = std.fmt.allocPrint(self.allocator, "{d}x{d}", .{ px, px }) catch return false;
		defer self.allocator.free(size);

		const part = std.fmt.allocPrint(self.allocator, "{s}.part.jpg", .{dest}) catch return false;
		defer self.allocator.free(part);

		const target = std.fmt.allocPrint(self.allocator, "{s}[Q={d},strip]", .{ part, jpeg_quality }) catch return false;
		defer self.allocator.free(target);

		const result = exec.run(self.io, self.allocator, &.{ thumb_bin, src, "-s", size, "-o", target }) catch return false;
		defer result.deinit(self.allocator);

		if (result.code != 0) {
			std.Io.Dir.cwd().deleteFile(self.io, part) catch {};
			return false;
		}

		std.Io.Dir.cwd().rename(part, std.Io.Dir.cwd(), dest, self.io) catch return false;
		return true;
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

			const stat = std.Io.Dir.cwd().statFile(self.io, child, .{}) catch continue;

			out.append(self.allocator, .{
				.path = self.allocator.dupe(u8, child) catch continue,
				.name = nameOf(self.allocator, item.name) catch continue,
				.key = cacheKey(self.allocator, child, stat.mtime.nanoseconds) catch continue,
				.thumb = self.allocator.dupe(u8, "") catch continue,
				.preview = self.allocator.dupe(u8, "") catch continue,
			}) catch continue;
		}
	}

	pub fn activePath(self: *Wallpaper, allocator: Allocator) ?[]u8 {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		if (self.active.len == 0) return null;

		return allocator.dupe(u8, self.active) catch null;
	}

	pub fn save(self: *Wallpaper, path: []const u8) void {
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
			try list.append(arena, .{
				.path = entry.path,
				.name = entry.name,
				.thumb = entry.thumb,
				.preview = entry.preview,
			});
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

fn freeEntry(allocator: Allocator, entry: Entry) void {
	allocator.free(entry.path);
	allocator.free(entry.name);
	allocator.free(entry.key);
	allocator.free(entry.thumb);
	allocator.free(entry.preview);
}

fn cacheKey(allocator: Allocator, path: []const u8, mtime: i128) ![]u8 {
	var hash = std.hash.Wyhash.init(0);
	hash.update(path);
	hash.update(std.mem.asBytes(&mtime));

	var buf: [32]u8 = undefined;
	const stem = stemOf(path, &buf);

	return std.fmt.allocPrint(allocator, "{s}-{x:0>16}", .{ stem, hash.final() });
}

fn stemOf(path: []const u8, buf: *[32]u8) []const u8 {
	const base = std.fs.path.basename(path);
	const dot = std.mem.lastIndexOfScalar(u8, base, '.') orelse base.len;

	var len: usize = 0;
	for (base[0..dot]) |ch| {
		if (len == buf.len) break;
		if (!std.ascii.isAlphanumeric(ch)) continue;

		buf[len] = std.ascii.toLower(ch);
		len += 1;
	}

	if (len == 0) return "wall";
	return buf[0..len];
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

test "the cache key follows the path and its mtime" {
	const a = try cacheKey(std.testing.allocator, "/walls/My Wall 2.jpg", 1000);
	defer std.testing.allocator.free(a);

	const same = try cacheKey(std.testing.allocator, "/walls/My Wall 2.jpg", 1000);
	defer std.testing.allocator.free(same);

	const changed = try cacheKey(std.testing.allocator, "/walls/My Wall 2.jpg", 1001);
	defer std.testing.allocator.free(changed);

	const other = try cacheKey(std.testing.allocator, "/walls/Other.jpg", 1000);
	defer std.testing.allocator.free(other);

	try std.testing.expectEqualStrings(a, same);
	try std.testing.expect(!std.mem.eql(u8, a, changed));
	try std.testing.expect(!std.mem.eql(u8, a, other));
	try std.testing.expect(std.mem.startsWith(u8, a, "mywall2-"));
	try std.testing.expect(std.mem.indexOfScalar(u8, a, '/') == null);
}

test "the scan lists the wallpapers under the directory" {
	const io = std.Io.Threaded.global_single_threaded.io();

	var hub: hubmod.Hub = .{ .allocator = std.testing.allocator, .io = io };
	const self = try Wallpaper.create(std.testing.allocator, io, &hub);
	defer {
		for (self.entries.items) |entry| freeEntry(std.testing.allocator, entry);
		self.entries.deinit(std.testing.allocator);
		std.testing.allocator.free(self.dir);
		std.testing.allocator.free(self.active);
		std.testing.allocator.free(self.cache);
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
		for (out.items) |entry| freeEntry(std.testing.allocator, entry);
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
