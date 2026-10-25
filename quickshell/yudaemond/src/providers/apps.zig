const std = @import("std");
const hubmod = @import("../hub.zig");
const proc = @import("../primitives/proc.zig");
const sleep = @import("../primitives/sleep.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

pub const Entry = struct {
	id: []u8,
	name: []u8,
	icon: []u8,
	exec: []u8,
	command: []u8,
	terminal: bool = false,
	wmclass: []u8 = &.{},
	comment: []u8 = &.{},
};

pub const EntryOut = struct {
	id: []const u8,
	name: []const u8,
	icon: []const u8,
	exec: []const u8,
	command: []const u8,
	terminal: bool,
	wmclass: []const u8,
	comment: []const u8,
};

pub const Apps = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	entries: std.ArrayListUnmanaged(Entry) = .empty,

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Apps {
		const self = try allocator.create(Apps);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.scratch = std.heap.ArenaAllocator.init(allocator),
		};

		return self;
	}

	pub fn provider(self: *Apps) hubmod.Provider {
		return .{ .key = "apps", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Apps = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	/// Hands the parsed entries to `callback` while the list is locked for the
	/// duration of the call. The slice is valid only inside the callback.
	pub fn view(self: *Apps, ctx: anytype, callback: fn (@TypeOf(ctx), []const Entry) void) void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		callback(ctx, self.entries.items);
	}

	pub fn start(self: *Apps) !void {
		const thread = try std.Thread.spawn(.{}, loop, .{self});
		thread.detach();
	}

	fn loop(self: *Apps) void {
		self.scan();

		while (true) {
			sleep.ms(60_000);
			self.scan();
		}
	}

	fn scan(self: *Apps) void {
		var found: std.ArrayListUnmanaged(Entry) = .empty;

		const home = proc.home(self.io, self.allocator);
		const user = std.fmt.allocPrint(self.allocator, "{s}/.local/share/applications", .{home}) catch return;
		defer self.allocator.free(user);

		self.scanDir(user, &found, 0);
		self.scanDir("/var/lib/flatpak/exports/share/applications", &found, 0);

		const flatpak_user = std.fmt.allocPrint(self.allocator, "{s}/.local/share/flatpak/exports/share/applications", .{home}) catch "";
		if (flatpak_user.len > 0) {
			defer self.allocator.free(flatpak_user);
			self.scanDir(flatpak_user, &found, 0);
		}

		const data_dirs = proc.env(self.io, self.allocator, "XDG_DATA_DIRS") orelse "/usr/local/share:/usr/share";
		var dirs = std.mem.splitScalar(u8, data_dirs, ':');

		while (dirs.next()) |dir| {
			if (dir.len == 0) continue;

			const path = std.fmt.allocPrint(self.allocator, "{s}/applications", .{dir}) catch continue;
			defer self.allocator.free(path);

			self.scanDir(path, &found, 0);
		}

		self.mutex.lockUncancelable(self.io);
		for (self.entries.items) |entry| self.freeEntry(entry);
		self.entries.deinit(self.allocator);
		self.entries = found;
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn freeEntry(self: *Apps, entry: Entry) void {
		self.allocator.free(entry.id);
		self.allocator.free(entry.name);
		self.allocator.free(entry.icon);
		self.allocator.free(entry.exec);
		self.allocator.free(entry.command);
		if (entry.wmclass.len > 0) self.allocator.free(entry.wmclass);
		if (entry.comment.len > 0) self.allocator.free(entry.comment);
	}

	fn scanDir(self: *Apps, path: []const u8, out: *std.ArrayListUnmanaged(Entry), depth: usize) void {
		var dir = std.Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true }) catch return;
		defer dir.close(self.io);

		var it = dir.iterate();

		while (it.next(self.io) catch null) |item| {
			const child = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ path, item.name }) catch continue;
			defer self.allocator.free(child);

			if (item.kind == .directory) {
				if (depth < 5) self.scanDir(child, out, depth + 1);
				continue;
			}

			if (item.kind != .file and item.kind != .sym_link) continue;
			if (!std.mem.endsWith(u8, item.name, ".desktop")) continue;

			if (self.parseEntry(child, item.name)) |entry| {
				if (hasId(out.items, entry.id)) {
					self.freeEntry(entry);
					continue;
				}

				out.append(self.allocator, entry) catch continue;
			}
		}
	}

	fn parseEntry(self: *Apps, path: []const u8, file_name: []const u8) ?Entry {
		const body = proc.readFile(self.io, self.allocator, path) catch return null;
		defer self.allocator.free(body);

		var name: []const u8 = "";
		var icon: []const u8 = "";
		var exec: []const u8 = "";
		var comment: []const u8 = "";
		var wmclass: []const u8 = "";
		var terminal = false;
		var hidden = false;
		var in_entry = false;

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

			if (std.mem.eql(u8, key, "Name")) name = value;
			if (std.mem.eql(u8, key, "Icon")) icon = value;
			if (std.mem.eql(u8, key, "Exec")) exec = value;
			if (std.mem.eql(u8, key, "Comment")) comment = value;
			if (std.mem.eql(u8, key, "StartupWMClass")) wmclass = value;
			if (std.mem.eql(u8, key, "Terminal")) terminal = std.mem.eql(u8, value, "true");
			if (std.mem.eql(u8, key, "NoDisplay") and std.mem.eql(u8, value, "true")) hidden = true;
			if (std.mem.eql(u8, key, "Hidden") and std.mem.eql(u8, value, "true")) hidden = true;
		}

		if (hidden or name.len == 0 or exec.len == 0) return null;

		const dot = std.mem.lastIndexOfScalar(u8, file_name, '.') orelse file_name.len;

		const command = self.commandOf(exec) catch return null;

		return .{
			.id = self.allocator.dupe(u8, file_name[0..dot]) catch return null,
			.name = self.allocator.dupe(u8, name) catch return null,
			.icon = self.allocator.dupe(u8, icon) catch return null,
			.exec = self.allocator.dupe(u8, command) catch return null,
			.command = command,
			.terminal = terminal,
			.wmclass = self.allocator.dupe(u8, wmclass) catch &.{},
			.comment = self.allocator.dupe(u8, comment) catch &.{},
		};
	}

	fn commandOf(self: *Apps, exec: []const u8) ![]u8 {
		var out: std.ArrayList(u8) = .empty;
		errdefer out.deinit(self.allocator);

		var it = std.mem.tokenizeAny(u8, exec, " \t");
		var first = true;

		while (it.next()) |token| {
			if (token.len > 0 and token[0] == '%') continue;
			if (std.mem.indexOfScalar(u8, token, '%')) |_| {
				const cleaned = stripFieldCodes(self.allocator, token) catch continue;
				defer self.allocator.free(cleaned);
				if (cleaned.len == 0) continue;
				if (!first) try out.append(self.allocator, ' ');
				try out.appendSlice(self.allocator, cleaned);
				first = false;
				continue;
			}

			if (!first) try out.append(self.allocator, ' ');
			try out.appendSlice(self.allocator, token);
			first = false;
		}

		return out.toOwnedSlice(self.allocator);
	}

	fn render(self: *Apps, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);

		try writer.writeAll("{\"entries\":{");
		for (self.entries.items, 0..) |entry, i| {
			if (i > 0) try writer.writeAll(",");
			try writer.print("\"{s}\":", .{entry.id});
			try writer.print("{f}", .{std.json.fmt(EntryOut{
				.id = entry.id,
				.name = entry.name,
				.icon = entry.icon,
				.exec = entry.exec,
				.command = entry.command,
				.terminal = entry.terminal,
				.wmclass = entry.wmclass,
				.comment = entry.comment,
			}, .{})});
		}
		try writer.writeAll("}}");
	}
};

fn hasId(entries: []const Entry, id: []const u8) bool {
	for (entries) |entry| {
		if (std.mem.eql(u8, entry.id, id)) return true;
	}

	return false;
}

fn stripFieldCodes(allocator: Allocator, token: []const u8) ![]u8 {
	var out: std.ArrayList(u8) = .empty;
	errdefer out.deinit(allocator);

	var index: usize = 0;
	while (index < token.len) : (index += 1) {
		if (token[index] == '%' and index + 1 < token.len) {
			index += 1;
			continue;
		}

		try out.append(allocator, token[index]);
	}

	return out.toOwnedSlice(allocator);
}

test "the desktop scan walks nested dirs, skips hidden entries and stops at the depth limit" {
	const io = std.Io.Threaded.global_single_threaded.io();

	var hub: hubmod.Hub = .{ .allocator = std.testing.allocator, .io = io };
	const self = try Apps.create(std.testing.allocator, io, &hub);
	defer {
		for (self.entries.items) |entry| self.freeEntry(entry);
		self.entries.deinit(std.testing.allocator);
		self.scratch.deinit();
		std.testing.allocator.destroy(self);
	}

	var tmp = std.testing.tmpDir(.{});
	defer tmp.cleanup();

	const visible =
		"[Desktop Entry]\n" ++
		"Name=Top App\n" ++
		"Icon=top\n" ++
		"Exec=/bin/top %U\n";

	try tmp.dir.writeFile(io, .{ .sub_path = "Top.desktop", .data = visible });
	try tmp.dir.createDirPath(io, "sub/deeper/one/two/three/four");
	try tmp.dir.writeFile(io, .{ .sub_path = "sub/Nested.desktop", .data = visible });
	try tmp.dir.writeFile(io, .{ .sub_path = "sub/notes.txt", .data = "not a desktop file" });
	try tmp.dir.writeFile(io, .{ .sub_path = "sub/Hidden.desktop", .data =
		"[Desktop Entry]\n" ++
		"Name=Hidden App\n" ++
		"Exec=/bin/hidden\n" ++
		"Hidden=true\n" });
	try tmp.dir.writeFile(io, .{ .sub_path = "sub/deeper/one/two/three/four/Missed.desktop", .data = visible });

	var buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
	const len = try tmp.dir.realPath(io, &buffer);

	var out: std.ArrayListUnmanaged(Entry) = .empty;
	defer {
		for (out.items) |entry| self.freeEntry(entry);
		out.deinit(std.testing.allocator);
	}

	self.scanDir(buffer[0..len], &out, 0);

	try std.testing.expectEqual(@as(usize, 2), out.items.len);

	var ids: [2][]const u8 = undefined;
	for (out.items, 0..) |entry, index| ids[index] = entry.id;

	std.mem.sort([]const u8, &ids, {}, struct {
		fn less(_: void, a: []const u8, b: []const u8) bool {
			return std.mem.lessThan(u8, a, b);
		}
	}.less);

	try std.testing.expectEqualStrings("Nested", ids[0]);
	try std.testing.expectEqualStrings("Top", ids[1]);

	for (out.items) |entry| {
		try std.testing.expectEqualStrings("Top App", entry.name);
		try std.testing.expectEqualStrings("/bin/top", entry.command);
	}
}
