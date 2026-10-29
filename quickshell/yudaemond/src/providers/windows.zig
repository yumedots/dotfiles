const std = @import("std");
const hubmod = @import("../hub.zig");
const json = @import("../primitives/json.zig");
const hypr = @import("../primitives/hypr.zig");
const proc = @import("../primitives/proc.zig");
const sleep = @import("../primitives/sleep.zig");
const exec = @import("../primitives/exec.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const terminals = [_][]const u8{ "foot", "footclient" };

pub const Window = struct {
	address: []const u8,
	title: []const u8,
	app_id: []const u8,
	workspace: []const u8,
	slot: i64,
	version: i64,
	focus: i64,
};

const Out = struct {
	id: []const u8,
	kind: []const u8,
	name: []const u8,
	title: []const u8,
	appId: []const u8,
	address: []const u8,
	workspace: []const u8,
	slot: i64,
	version: i64,
	focus: i64,
};

const Desktop = struct {
	exec: []const u8,
	terminal: bool,
};

pub const Windows = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	list: []Window = &.{},
	query: []u8 = &.{},

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Windows {
		const self = try allocator.create(Windows);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.scratch = std.heap.ArenaAllocator.init(allocator),
		};

		return self;
	}

	pub fn provider(self: *Windows) hubmod.Provider {
		return .{ .key = "windows", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Windows = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn start(self: *Windows) !void {
		self.refresh();

		const thread = try std.Thread.spawn(.{}, loop, .{self});
		thread.detach();
	}

	fn loop(self: *Windows) void {
		while (true) {
			sleep.ms(1000);
			if (!self.watched()) continue;
			self.refresh();
		}
	}

	fn watched(self: *Windows) bool {
		const server = self.hub.ipc orelse return false;
		return server.clients.items.len > 0;
	}

	pub fn refresh(self: *Windows) void {
		const body = hypr.request(self.io, self.allocator, "j/clients") catch return;
		defer self.allocator.free(body);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();
		const versions = self.versionsFile(allocator);
		const next = parseClients(allocator, body, parseVersions(allocator, versions)) catch return;

		self.mutex.lockUncancelable(self.io);

		if (sameAs(self.list, next)) {
			self.mutex.unlock(self.io);
			return;
		}

		const owned = cloneList(self.allocator, next) catch {
			self.mutex.unlock(self.io);
			return;
		};

		freeList(self.allocator, self.list);
		self.list = owned;

		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn versionsFile(self: *Windows, allocator: Allocator) []const u8 {
		const path = std.fmt.allocPrint(allocator, "{s}/.config/quickshell/cache/versions.json", .{proc.home(self.io, self.allocator)}) catch return "";
		return proc.readFile(self.io, allocator, path) catch "";
	}

	fn usingLua(self: *Windows) bool {
		return hypr.usingLua(self.io, self.allocator);
	}

	pub fn setQuery(self: *Windows, query: []const u8) void {
		const next = self.allocator.dupe(u8, query) catch return;

		self.mutex.lockUncancelable(self.io);

		if (std.mem.eql(u8, self.query, next)) {
			self.mutex.unlock(self.io);
			self.allocator.free(next);
			return;
		}

		self.allocator.free(self.query);
		self.query = next;
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	pub fn focus(self: *Windows, address: []const u8) void {
		if (address.len == 0) return;

		const copy = self.allocator.dupe(u8, address) catch return;

		const thread = std.Thread.spawn(.{}, focusThread, .{ self, copy }) catch {
			self.allocator.free(copy);
			return;
		};
		thread.detach();
	}

	fn focusThread(self: *Windows, raw: []u8) void {
		defer self.allocator.free(raw);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();
		const address = if (std.mem.startsWith(u8, raw, "0x"))
			raw
		else
			std.fmt.allocPrint(allocator, "0x{s}", .{raw}) catch return;

		var slot: i64 = 0;
		var version: i64 = 1;

		self.mutex.lockUncancelable(self.io);
		for (self.list) |window| {
			if (!std.mem.eql(u8, window.address, address)) continue;
			slot = window.slot;
			version = window.version;
		}
		self.mutex.unlock(self.io);

		for (0..3) |attempt| {
			self.dispatch(allocator, address, slot, version);

			if (attempt == 2 or self.focused(address)) return;

			sleep.ms(60);
		}
	}

	fn dispatch(self: *Windows, allocator: Allocator, address: []const u8, slot: i64, version: i64) void {
		if (self.usingLua()) {
			const script = std.fmt.allocPrint(allocator, "require(\"versions\").visit({d}, {d}); hl.dispatch(hl.dsp.focus({{window = \"address:{s}\"}}))", .{ slot, version, address }) catch return;
			const result = exec.run(self.io, self.allocator, &.{ "hyprctl", "eval", script }) catch return;
			result.deinit(self.allocator);
			return;
		}

		const command = std.fmt.allocPrint(allocator, "dispatch focuswindow address:{s}", .{address}) catch return;
		const answer = hypr.request(self.io, self.allocator, command) catch return;
		self.allocator.free(answer);
	}

	fn focused(self: *Windows, address: []const u8) bool {
		const body = hypr.request(self.io, self.allocator, "j/activewindow") catch return true;
		defer self.allocator.free(body);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const parsed = json.parse(arena.allocator(), std.mem.trim(u8, body, " \t\r\n")) catch return true;

		return std.mem.eql(u8, json.textAt(parsed.value, "address"), address);
	}

	pub fn launch(self: *Windows, id: []const u8) void {
		if (id.len == 0) return;

		const copy = self.allocator.dupe(u8, id) catch return;

		const thread = std.Thread.spawn(.{}, launchThread, .{ self, copy }) catch {
			self.allocator.free(copy);
			return;
		};
		thread.detach();
	}

	fn launchThread(self: *Windows, id: []u8) void {
		defer self.allocator.free(id);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();
		const app_id = if (std.mem.startsWith(u8, id, "app:")) id["app:".len..] else id;
		const desktop = self.desktopEntry(allocator, app_id) orelse return;

		var argv: std.ArrayListUnmanaged([]const u8) = .empty;

		if (desktop.terminal) {
			const terminal = self.terminalName(allocator) orelse return;
			const quoted = shellQuote(allocator, desktop.exec) catch return;
			const line = std.fmt.allocPrint(allocator, "{s} -e sh -c {s}", .{ terminal, quoted }) catch return;

			argv.appendSlice(allocator, &.{ "sh", "-c", line }) catch return;
		} else {
			argv.appendSlice(allocator, &.{ "sh", "-c", desktop.exec }) catch return;
		}

		var child = std.process.spawn(self.io, .{
			.argv = argv.items,
			.stdin = .ignore,
			.stdout = .ignore,
			.stderr = .ignore,
		}) catch return;

		_ = child.wait(self.io) catch {};
	}

	fn terminalName(self: *Windows, allocator: Allocator) ?[]const u8 {
		const path = std.fmt.allocPrint(allocator, "{s}/.config/hypr/programs.lua", .{proc.home(self.io, self.allocator)}) catch return null;
		const body = proc.readFile(self.io, allocator, path) catch return null;

		var name: ?[]const u8 = null;
		var lines = std.mem.splitScalar(u8, body, '\n');

		while (lines.next()) |raw| {
			const line = std.mem.trim(u8, raw, " \t\r");
			if (!std.mem.startsWith(u8, line, "terminal")) continue;

			const at = std.mem.indexOfScalar(u8, line, '=') orelse continue;

			const value = std.mem.trim(u8, line[at + 1 ..], " \t\r\"'");

			if (value.len > 0) name = value;
		}

		return name;
	}

	fn desktopEntry(self: *Windows, allocator: Allocator, id: []const u8) ?Desktop {
		const file = std.fmt.allocPrint(allocator, "{s}.desktop", .{id}) catch return null;
		const path = self.desktopPath(allocator, file) orelse return null;
		const body = proc.readFile(self.io, allocator, path) catch return null;

		var line_exec: []const u8 = "";
		var terminal = false;
		var in_entry = false;

		var lines = std.mem.splitScalar(u8, body, '\n');

		while (lines.next()) |raw| {
			const line = std.mem.trim(u8, raw, " \t\r");
			if (line.len == 0 or line[0] == '#') continue;

			if (line[0] == '[') {
				in_entry = std.mem.eql(u8, line, "[Desktop Entry]");
				continue;
			}

			if (!in_entry) continue;

			const at = std.mem.indexOfScalar(u8, line, '=') orelse continue;
			const key = std.mem.trim(u8, line[0..at], " \t");
			const value = std.mem.trim(u8, line[at + 1 ..], " \t");

			if (std.mem.eql(u8, key, "Exec")) line_exec = value;
			if (std.mem.eql(u8, key, "Terminal")) terminal = std.mem.eql(u8, value, "true");
		}

		if (line_exec.len == 0) return null;

		return .{ .exec = execLine(allocator, line_exec) catch return null, .terminal = terminal };
	}

	fn desktopPath(self: *Windows, allocator: Allocator, file: []const u8) ?[]const u8 {
		const home = proc.home(self.io, self.allocator);
		const user = std.fmt.allocPrint(allocator, "{s}/.local/share/applications", .{home}) catch return null;
		if (findFile(self.io, allocator, user, file, 0)) |path| return path;

		const flatpak_user = std.fmt.allocPrint(allocator, "{s}/.local/share/flatpak/exports/share/applications", .{home}) catch return null;
		if (findFile(self.io, allocator, flatpak_user, file, 0)) |path| return path;

		if (findFile(self.io, allocator, "/var/lib/flatpak/exports/share/applications", file, 0)) |path| return path;

		const data_dirs = proc.env(self.io, self.allocator, "XDG_DATA_DIRS") orelse "/usr/local/share:/usr/share";
		var dirs = std.mem.splitScalar(u8, data_dirs, ':');

		while (dirs.next()) |dir| {
			if (dir.len == 0) continue;

			const path = std.fmt.allocPrint(allocator, "{s}/applications", .{dir}) catch continue;
			if (findFile(self.io, allocator, path, file, 0)) |found| return found;
		}

		return null;
	}

	fn render(self: *Windows, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);
		const arena = self.scratch.allocator();

		var rows: std.ArrayListUnmanaged(Out) = .empty;

		for (self.list) |window| {
			if (!matches(window.title, self.query) and !matches(window.app_id, self.query)) continue;

			const name = if (window.title.len > 0) window.title else window.app_id;

			try rows.append(arena, .{
				.id = try std.fmt.allocPrint(arena, "win:{s}", .{window.address}),
				.kind = "window",
				.name = name,
				.title = window.title,
				.appId = window.app_id,
				.address = window.address,
				.workspace = window.workspace,
				.slot = window.slot,
				.version = window.version,
				.focus = window.focus,
			});
		}

		try writer.print("{f}", .{std.json.fmt(.{ .list = rows.items, .empty = "No windows open" }, .{})});
	}
};

fn matches(text: []const u8, needle: []const u8) bool {
	if (needle.len == 0) return true;
	if (needle.len > text.len) return false;

	var index: usize = 0;

	while (index + needle.len <= text.len) : (index += 1) {
		if (std.ascii.eqlIgnoreCase(text[index .. index + needle.len], needle)) return true;
	}

	return false;
}

fn findFile(io: Io, allocator: Allocator, dir_path: []const u8, file: []const u8, depth: usize) ?[]const u8 {
	var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch return null;
	defer dir.close(io);

	var it = dir.iterate();

	while (it.next(io) catch null) |item| {
		const child = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, item.name }) catch continue;

		if (item.kind == .directory) {
			if (depth < 4) {
				if (findFile(io, allocator, child, file, depth + 1)) |path| return path;
			}
			continue;
		}

		if (item.kind != .file and item.kind != .sym_link) continue;
		if (!std.mem.eql(u8, item.name, file)) continue;

		return child;
	}

	return null;
}

fn shellQuote(allocator: Allocator, text: []const u8) ![]const u8 {
	var out: std.ArrayList(u8) = .empty;

	try out.append(allocator, '\'');

	for (text) |byte| {
		if (byte == '\'') {
			try out.appendSlice(allocator, "'\\''");
			continue;
		}

		try out.append(allocator, byte);
	}

	try out.append(allocator, '\'');

	return out.toOwnedSlice(allocator);
}

fn execLine(allocator: Allocator, raw: []const u8) ![]const u8 {
	var out: std.ArrayList(u8) = .empty;
	var it = std.mem.tokenizeAny(u8, raw, " \t");
	var first = true;

	while (it.next()) |token| {
		if (token.len == 0) continue;

		const cleaned = stripFieldCodes(allocator, token) catch continue;
		if (cleaned.len == 0) continue;

		if (!first) try out.append(allocator, ' ');
		try out.appendSlice(allocator, cleaned);
		first = false;
	}

	return out.toOwnedSlice(allocator);
}

fn stripFieldCodes(allocator: Allocator, token: []const u8) ![]const u8 {
	var out: std.ArrayList(u8) = .empty;

	var index: usize = 0;
	while (index < token.len) : (index += 1) {
		if (token[index] == '%' and index + 1 < token.len) {
			if (token.len == 2) return out.toOwnedSlice(allocator);
			index += 1;
			continue;
		}

		try out.append(allocator, token[index]);
	}

	return out.toOwnedSlice(allocator);
}

pub fn commandWord(title: []const u8) []const u8 {
	const end = std.mem.indexOfScalar(u8, title, ' ') orelse title.len;
	var word = title[0..end];

	if (word.len > 0 and word[word.len - 1] == ':') word = word[0 .. word.len - 1];
	if (word.len == 0) return "";
	if (std.mem.indexOfAny(u8, word, "/~") != null) return "";

	return word;
}

fn isTerminal(class: []const u8) bool {
	for (terminals) |name| {
		if (std.ascii.eqlIgnoreCase(class, name)) return true;
	}

	return false;
}

fn appIdOf(class: []const u8, title: []const u8) []const u8 {
	if (!isTerminal(class)) return class;

	const word = commandWord(title);
	return if (word.len > 0) word else class;
}

const Slot = struct { slot: i64, version: i64 };

fn workspaceSlot(name: []const u8) ?Slot {
	var text = name;

	if (text.len > 0 and text[0] == 'v') text = text[1..];
	if (text.len == 0) return null;

	if (std.mem.indexOfScalar(u8, text, '.')) |dot| {
		const slot = std.fmt.parseInt(i64, text[0..dot], 10) catch return null;
		const version = std.fmt.parseInt(i64, text[dot + 1 ..], 10) catch return null;

		return .{ .slot = slot, .version = version };
	}

	const slot = std.fmt.parseInt(i64, text, 10) catch return null;

	return .{ .slot = slot, .version = 1 };
}

fn parseVersions(allocator: Allocator, body: []const u8) std.json.Value {
	if (body.len == 0) return .null;

	const parsed = json.parse(allocator, body) catch return .null;

	return parsed.value;
}

fn wantedVersion(versions: std.json.Value, slot: i64) i64 {
	var buffer: [24]u8 = undefined;
	const key = std.fmt.bufPrint(&buffer, "{d}", .{slot}) catch return 1;
	const found = json.integer(json.field(versions, key));

	return if (found < 1) 1 else found;
}

fn parseClients(allocator: Allocator, body: []const u8, versions: std.json.Value) ![]const Window {
	const trimmed = std.mem.trim(u8, body, " \t\r\n");
	if (trimmed.len == 0) return &.{};

	const parsed = try json.parse(allocator, trimmed);

	var found: std.ArrayListUnmanaged(Window) = .empty;

	for (json.list(parsed.value)) |client| {
		const workspace = json.textDeep(client, &.{ "workspace", "name" });
		const place = workspaceSlot(workspace) orelse continue;
		if (place.version != wantedVersion(versions, place.slot)) continue;

		const class = json.textAt(client, "class");
		const title = json.textAt(client, "title");

		try found.append(allocator, .{
			.address = try allocator.dupe(u8, json.textAt(client, "address")),
			.title = try allocator.dupe(u8, title),
			.app_id = try allocator.dupe(u8, appIdOf(class, title)),
			.workspace = try allocator.dupe(u8, workspace),
			.slot = place.slot,
			.version = place.version,
			.focus = blk: {
				const history = json.field(client, "focusHistoryID") orelse break :blk 999;
				break :blk if (json.integer(history) < 0) 999 else json.integer(history);
			},
		});
	}

	std.mem.sort(Window, found.items, {}, struct {
		fn older(_: void, a: Window, b: Window) bool {
			return a.focus < b.focus;
		}
	}.older);

	return found.items;
}

fn sameAs(current: []const Window, next: []const Window) bool {
	if (current.len != next.len) return false;

	for (current, next) |a, b| {
		if (a.slot != b.slot or a.version != b.version or a.focus != b.focus) return false;
		if (!std.mem.eql(u8, a.address, b.address)) return false;
		if (!std.mem.eql(u8, a.title, b.title)) return false;
		if (!std.mem.eql(u8, a.app_id, b.app_id)) return false;
		if (!std.mem.eql(u8, a.workspace, b.workspace)) return false;
	}

	return true;
}

fn cloneList(allocator: Allocator, next: []const Window) ![]Window {
	const out = try allocator.alloc(Window, next.len);
	errdefer allocator.free(out);

	var filled: usize = 0;
	errdefer for (out[0..filled]) |window| freeWindow(allocator, window);

	for (next, 0..) |window, index| {
		out[index] = .{
			.address = try allocator.dupe(u8, window.address),
			.title = try allocator.dupe(u8, window.title),
			.app_id = try allocator.dupe(u8, window.app_id),
			.workspace = try allocator.dupe(u8, window.workspace),
			.slot = window.slot,
			.version = window.version,
			.focus = window.focus,
		};
		filled = index + 1;
	}

	return out;
}

fn freeWindow(allocator: Allocator, window: Window) void {
	allocator.free(window.address);
	allocator.free(window.title);
	allocator.free(window.app_id);
	allocator.free(window.workspace);
}

fn freeList(allocator: Allocator, list: []Window) void {
	for (list) |window| freeWindow(allocator, window);
	if (list.len > 0) allocator.free(list);
}

test "the command word of a terminal title is the app" {
	try std.testing.expectEqualStrings("nvim", commandWord("nvim: src/main.zig"));
	try std.testing.expectEqualStrings("yazi", commandWord("yazi"));
	try std.testing.expectEqualStrings("", commandWord("~/src: file"));
	try std.testing.expectEqualStrings("", commandWord("/usr/bin/top"));
	try std.testing.expectEqualStrings("", commandWord(""));
}

test "terminal windows take the command word, everything else the class" {
	try std.testing.expectEqualStrings("btop", appIdOf("foot", "btop"));
	try std.testing.expectEqualStrings("foot", appIdOf("foot", "~/src"));
	try std.testing.expectEqualStrings("firefox", appIdOf("firefox", "Mozilla Firefox"));
	try std.testing.expectEqualStrings("ls", appIdOf("FootClient", "ls"));
}

test "a workspace name splits into slot and version" {
	const plain = workspaceSlot("3").?;
	try std.testing.expectEqual(@as(i64, 3), plain.slot);
	try std.testing.expectEqual(@as(i64, 1), plain.version);

	const named = workspaceSlot("v7.4").?;
	try std.testing.expectEqual(@as(i64, 7), named.slot);
	try std.testing.expectEqual(@as(i64, 4), named.version);

	try std.testing.expect(workspaceSlot("special:magic") == null);
	try std.testing.expect(workspaceSlot("") == null);
	try std.testing.expect(workspaceSlot("v") == null);
}

test "windows on another version of a slot are dropped" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();

	const versions = parseVersions(allocator, "{\"2\":3}");
	const body =
		\\[
		\\{"address":"0xaa","title":"foot","class":"firefox","workspace":{"id":2,"name":"v2.3"},"focusHistoryID":0},
		\\{"address":"0xbb","title":"btop","class":"foot","workspace":{"id":2,"name":"v2.1"},"focusHistoryID":1},
		\\{"address":"0xcc","title":"nvim: x","class":"foot","workspace":{"id":1,"name":"1"},"focusHistoryID":2}
		\\]
	;

	const list = try parseClients(allocator, body, versions);

	try std.testing.expectEqual(@as(usize, 2), list.len);
	try std.testing.expectEqualStrings("0xaa", list[0].address);
	try std.testing.expectEqualStrings("firefox", list[0].app_id);
	try std.testing.expectEqualStrings("nvim", list[1].app_id);
	try std.testing.expectEqual(@as(i64, 1), list[1].slot);
}

test "a shell word survives a single quote in the exec line" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const quoted = try shellQuote(arena.allocator(), "sh -c 'hi'");
	try std.testing.expectEqualStrings("'sh -c '\\''hi'\\'''", quoted);
}

test "the exec line loses its field codes" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const line = try execLine(arena.allocator(), "/usr/bin/app %U --flag %f");
	try std.testing.expectEqualStrings("/usr/bin/app --flag", line);
}

test "the change check notices a retitled window" {
	const before = [_]Window{.{ .address = "0xaa", .title = "a", .app_id = "a", .workspace = "1", .slot = 1, .version = 1, .focus = 0 }};
	var after = before;
	try std.testing.expect(sameAs(&before, &after));

	after[0].title = "b";
	try std.testing.expect(!sameAs(&before, &after));
}

test "the window query keeps only the matching rows" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();
	const io = std.testing.io;

	var hub: hubmod.Hub = .{ .allocator = allocator, .io = io };
	const self = try Windows.create(allocator, io, &hub);
	try hub.add(self.provider());

	self.list = try allocator.dupe(Window, &.{
		.{ .address = "0xaa", .title = "Mozilla Firefox", .app_id = "firefox", .workspace = "1", .slot = 1, .version = 1, .focus = 0 },
		.{ .address = "0xbb", .title = "foot", .app_id = "btop", .workspace = "1", .slot = 1, .version = 1, .focus = 1 },
	});
	self.query = try allocator.dupe(u8, "fire");

	const body = try hub.syncSnapshot(allocator);

	try std.testing.expect(std.mem.indexOf(u8, body, "0xaa") != null);
	try std.testing.expect(std.mem.indexOf(u8, body, "0xbb") == null);
	try std.testing.expect(std.mem.indexOf(u8, body, "\"kind\":\"window\"") != null);
	try std.testing.expect(std.mem.indexOf(u8, body, "No windows open") != null);
}
