const std = @import("std");
const proc = @import("proc.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const extensions = [_][]const u8{ ".png", ".svg", ".xpm" };
const max_rank: u32 = 4096;

pub const Icons = struct {
	allocator: Allocator,
	io: Io,
	mutex: std.Io.Mutex = .init,
	files: std.StringHashMapUnmanaged([]u8) = .empty,
	ranks: std.StringHashMapUnmanaged(u32) = .empty,
	desktop: std.StringHashMapUnmanaged([]u8) = .empty,
	scanned_at: i64 = 0,

	pub fn create(allocator: Allocator, io: Io) !*Icons {
		const self = try allocator.create(Icons);
		self.* = .{ .allocator = allocator, .io = io };

		return self;
	}

	pub fn ensure(self: *Icons) void {
		const now = std.Io.Clock.real.now(self.io).toMilliseconds();

		self.mutex.lockUncancelable(self.io);
		const stale = self.scanned_at == 0 or now - self.scanned_at > 300_000;
		self.mutex.unlock(self.io);

		if (!stale) return;

		self.scan();
	}

	pub fn scan(self: *Icons) void {
		var files: std.StringHashMapUnmanaged([]u8) = .empty;
		var ranks: std.StringHashMapUnmanaged(u32) = .empty;
		var desktop: std.StringHashMapUnmanaged([]u8) = .empty;

		const home = proc.env(self.io, self.allocator, "HOME") orelse "/";

		const icon_roots = [_][]const u8{
			"/usr/share/icons",
			"/usr/local/share/icons",
			"/var/lib/flatpak/exports/share/icons",
			"/usr/share/pixmaps",
		};

		for (icon_roots) |root| self.walkIcons(&files, &ranks, root, 0);

		const user_icons = std.fmt.allocPrint(self.allocator, "{s}/.local/share/icons", .{home}) catch "";
		if (user_icons.len > 0) {
			defer self.allocator.free(user_icons);
			self.walkIcons(&files, &ranks, user_icons, 0);
		}

		const user_pixmaps = std.fmt.allocPrint(self.allocator, "{s}/.local/share/pixmaps", .{home}) catch "";
		if (user_pixmaps.len > 0) {
			defer self.allocator.free(user_pixmaps);
			self.walkIcons(&files, &ranks, user_pixmaps, 0);
		}

		for ([_][]const u8{ "/usr/share/applications", "/usr/local/share/applications", "/var/lib/flatpak/exports/share/applications" }) |dir|
			self.walkDesktop(&desktop, dir, 0);

		const user_apps = std.fmt.allocPrint(self.allocator, "{s}/.local/share/applications", .{home}) catch "";
		if (user_apps.len > 0) {
			defer self.allocator.free(user_apps);
			self.walkDesktop(&desktop, user_apps, 0);
		}

		self.mutex.lockUncancelable(self.io);

		self.clearMap(&self.files);
		self.files = files;

		var rank_it = self.ranks.iterator();
		while (rank_it.next()) |entry| self.allocator.free(entry.key_ptr.*);
		self.ranks.deinit(self.allocator);
		self.ranks = ranks;

		self.clearMap(&self.desktop);
		self.desktop = desktop;

		self.scanned_at = std.Io.Clock.real.now(self.io).toMilliseconds();
		self.mutex.unlock(self.io);
	}

	fn clearMap(self: *Icons, map: *std.StringHashMapUnmanaged([]u8)) void {
		var it = map.iterator();

		while (it.next()) |entry| {
			self.allocator.free(entry.key_ptr.*);
			self.allocator.free(entry.value_ptr.*);
		}

		map.deinit(self.allocator);
	}

	fn walkIcons(self: *Icons, files: *std.StringHashMapUnmanaged([]u8), ranks: *std.StringHashMapUnmanaged(u32), path: []const u8, depth: usize) void {
		var dir = std.Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true }) catch return;
		defer dir.close(self.io);

		var it = dir.iterate();

		while (it.next(self.io) catch null) |item| {
			const child = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ path, item.name }) catch continue;
			defer self.allocator.free(child);

			if (item.kind == .directory) {
				if (depth < 3) self.walkIcons(files, ranks, child, depth + 1);
				continue;
			}

			if (item.kind != .file and item.kind != .sym_link) continue;
			if (extensionOf(item.name) == null) continue;

			const name = stemOf(item.name);
			if (name.len == 0) continue;

			const rank = rankOf(path) + if (std.mem.endsWith(u8, item.name, ".svg")) max_rank else 0;

			if (ranks.get(name)) |known| {
				if (rank <= known) continue;
			}

			const key = self.allocator.dupe(u8, name) catch continue;
			const value = self.allocator.dupe(u8, child) catch {
				self.allocator.free(key);
				continue;
			};

			if (files.getEntry(key)) |entry| {
				self.allocator.free(entry.value_ptr.*);
				entry.value_ptr.* = value;
				self.allocator.free(key);
			} else {
				files.put(self.allocator, key, value) catch {
					self.allocator.free(key);
					self.allocator.free(value);
					continue;
				};
			}

			const rank_key = self.allocator.dupe(u8, name) catch continue;

			if (ranks.getEntry(rank_key)) |entry| {
				entry.value_ptr.* = rank;
				self.allocator.free(rank_key);
			} else {
				ranks.put(self.allocator, rank_key, rank) catch {
					self.allocator.free(rank_key);
					continue;
				};
			}
		}
	}

	fn walkDesktop(self: *Icons, desktop: *std.StringHashMapUnmanaged([]u8), path: []const u8, depth: usize) void {
		var dir = std.Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true }) catch return;
		defer dir.close(self.io);

		var it = dir.iterate();

		while (it.next(self.io) catch null) |item| {
			const child = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ path, item.name }) catch continue;
			defer self.allocator.free(child);

			if (item.kind == .directory) {
				if (depth < 4) self.walkDesktop(desktop, child, depth + 1);
				continue;
			}

			if (!std.mem.endsWith(u8, item.name, ".desktop")) continue;

			const body = proc.readFile(self.io, self.allocator, child) catch continue;
			defer self.allocator.free(body);

			const icon = entryIcon(body) orelse continue;
			const id = item.name[0 .. item.name.len - ".desktop".len];

			if (desktop.contains(id)) continue;

			const key = self.allocator.dupe(u8, id) catch continue;
			const value = self.allocator.dupe(u8, icon) catch {
				self.allocator.free(key);
				continue;
			};

			desktop.put(self.allocator, key, value) catch {
				self.allocator.free(key);
				self.allocator.free(value);
			};
		}
	}

	pub fn resolve(self: *Icons, name: []const u8) []const u8 {
		if (name.len == 0) return "";

		self.ensure();

		if (std.mem.indexOfScalar(u8, name, '/') != null) {
			return if (proc.exists(self.io, name)) name else "";
		}

		var lower_buf: [160]u8 = undefined;
		const trimmed = if (std.mem.endsWith(u8, name, ".desktop")) name[0 .. name.len - ".desktop".len] else name;
		const lower = lowercase(trimmed, &lower_buf);

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		if (self.files.get(name)) |path| return path;

		if (self.desktop.get(name)) |icon| {
			if (self.files.get(icon)) |path| return path;
			if (self.fallback(icon)) |path| return path;
		}

		if (self.fallback(name)) |path| return path;

		if (!std.mem.eql(u8, lower, name)) {
			if (self.files.get(lower)) |path| return path;

			if (self.desktop.get(lower)) |icon| {
				if (self.files.get(icon)) |path| return path;
				if (self.fallback(icon)) |path| return path;
			}

			if (self.fallback(lower)) |path| return path;
		}

		return "";
	}

	fn fallback(self: *Icons, name: []const u8) ?[]const u8 {
		var current = name;
		var trimmed: [128]u8 = undefined;

		if (std.mem.endsWith(u8, current, "-symbolic") and current.len - "-symbolic".len < trimmed.len) {
			@memcpy(trimmed[0 .. current.len - "-symbolic".len], current[0 .. current.len - "-symbolic".len]);
			current = trimmed[0 .. current.len - "-symbolic".len];
			if (self.files.get(current)) |path| return path;
		}

		var attempts: usize = 0;

		while (attempts < 4) : (attempts += 1) {
			const dash = std.mem.lastIndexOfScalar(u8, current, '-') orelse return null;
			current = current[0..dash];

			if (self.files.get(current)) |path| return path;
		}

		return null;
	}

	pub fn resolvePid(self: *Icons, pid: i64) []const u8 {
		if (pid <= 0) return "";

		var current = pid;
		var hops: usize = 0;

		while (current > 1 and hops < 8) : (hops += 1) {
			const comm_path = std.fmt.allocPrint(self.allocator, "/proc/{d}/comm", .{current}) catch return "";
			defer self.allocator.free(comm_path);

			const comm = proc.readFile(self.io, self.allocator, comm_path) catch "";
			defer if (comm.len > 0) self.allocator.free(comm);

			const name = std.mem.trim(u8, comm, " \n\r");

			if (name.len > 0) {
				const path = self.resolve(name);
				if (path.len > 0) return path;
			}

			const stat_path = std.fmt.allocPrint(self.allocator, "/proc/{d}/stat", .{current}) catch return "";
			defer self.allocator.free(stat_path);

			const stat = proc.readFile(self.io, self.allocator, stat_path) catch return "";
			defer self.allocator.free(stat);

			current = parentOf(stat) orelse return "";
		}

		return "";
	}
};

fn lowercase(name: []const u8, buffer: []u8) []const u8 {
	const len = @min(name.len, buffer.len);

	for (name[0..len], 0..) |byte, index| buffer[index] = std.ascii.toLower(byte);

	return buffer[0..len];
}

fn extensionOf(name: []const u8) ?[]const u8 {
	for (extensions) |extension| {
		if (std.mem.endsWith(u8, name, extension)) return extension;
	}

	return null;
}

fn stemOf(name: []const u8) []const u8 {
	const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return name;
	return name[0..dot];
}

fn rankOf(path: []const u8) u32 {
	var rank: u32 = 1;
	var it = std.mem.splitScalar(u8, path, '/');

	while (it.next()) |part| {
		const x = std.mem.indexOfScalar(u8, part, 'x') orelse continue;

		const left = std.fmt.parseInt(u32, part[0..x], 10) catch continue;
		if (left > rank) rank = left;
	}

	return rank;
}

fn entryIcon(body: []const u8) ?[]const u8 {
	var in_entry = false;
	var hidden = false;
	var icon: []const u8 = "";

	var lines = std.mem.splitScalar(u8, body, '\n');

	while (lines.next()) |raw| {
		const line = std.mem.trim(u8, raw, " \t\r");

		if (line.len == 0 or line[0] == '#' or line[0] == ';') continue;

		if (line[0] == '[') {
			in_entry = std.mem.eql(u8, line, "[Desktop Entry]");
			continue;
		}

		if (!in_entry) continue;

		const split = std.mem.indexOfScalar(u8, line, '=') orelse continue;
		const key = std.mem.trim(u8, line[0..split], " \t");
		const value = std.mem.trim(u8, line[split + 1 ..], " \t");

		if (std.mem.eql(u8, key, "Icon")) icon = value;
		if (std.mem.eql(u8, key, "Hidden") and std.mem.eql(u8, value, "true")) hidden = true;
		if (std.mem.eql(u8, key, "NoDisplay") and std.mem.eql(u8, value, "true")) hidden = true;
	}

	if (hidden or icon.len == 0) return null;

	return icon;
}

fn parentOf(stat: []const u8) ?i64 {
	const close = std.mem.lastIndexOfScalar(u8, stat, ')') orelse return null;
	const rest = std.mem.trim(u8, stat[close + 1 ..], " ");
	var fields = std.mem.tokenizeScalar(u8, rest, ' ');

	_ = fields.next() orelse return null;
	const ppid = fields.next() orelse return null;

	return std.fmt.parseInt(i64, ppid, 10) catch null;
}

test "an icon name finds the file under a theme dir" {
	try std.testing.expectEqualStrings("audio-card", stemOf("audio-card.svg"));
	try std.testing.expectEqualStrings("audio-card", stemOf("audio-card"));
	try std.testing.expect(extensionOf("x.png") != null);
	try std.testing.expect(extensionOf("x.txt") == null);
}

test "the biggest theme dir wins" {
	try std.testing.expectEqual(@as(u32, 256), rankOf("/usr/share/icons/hicolor/256x256/apps/x.png"));
	try std.testing.expectEqual(@as(u32, 1), rankOf("/usr/share/icons/hicolor/x.png"));
}

test "a desktop entry gives up its icon" {
	const body =
		\\[Desktop Entry]
		\\Name=Helium
		\\Icon=helium-browser
		\\Hidden=false
	;

	try std.testing.expectEqualStrings("helium-browser", entryIcon(body).?);
	try std.testing.expect(entryIcon("[Desktop Entry]\nName=x\nHidden=true\nIcon=y\n") == null);
	try std.testing.expect(entryIcon("[Desktop Entry]\nName=x\n") == null);
}

test "the parent pid is read out of stat" {
	try std.testing.expectEqual(@as(?i64, 12), parentOf("123 (name with space) S 12 123 123 0 -1"));
	try std.testing.expect(parentOf("garbage") == null);
}
