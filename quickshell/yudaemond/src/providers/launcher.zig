const std = @import("std");
const hubmod = @import("../hub.zig");
const appsmod = @import("apps.zig");
const sysmod = @import("system.zig");
const windowsmod = @import("windows.zig");
const calc = @import("../primitives/calc.zig");
const json = @import("../primitives/json.zig");
const exec = @import("../primitives/exec.zig");
const proc = @import("../primitives/proc.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const max_results = 60;
const usage_max = 10;
const preview_bytes = 20000;

const glyph_command = "\u{f018c}";
const glyph_calc = "\u{f00ec}";
const glyph_clip = "\u{f07f}";
const glyph_file = "\u{f0213}";
const glyph_apps = "\u{f0c9}";
const glyph_wallpaper = "\u{f0e09}";
const glyph_process = "\u{f0874}";
const glyph_power = "\u{f011}";
const glyph_prompt = "\u{ea6d}";

const Mode = struct {
	mode: []const u8,
	name: []const u8,
	mark: []const u8,
	glyph: []const u8,
	keywords: []const []const u8,
};

const modes = [_]Mode{
	.{ .mode = "clipboard", .name = "Clipboard", .mark = "", .glyph = glyph_clip, .keywords = &.{ "copy", "paste" } },
	.{ .mode = "wallpaper", .name = "Wallpaper", .mark = "~", .glyph = glyph_wallpaper, .keywords = &.{ "wallpaper", "background", "desktop" } },
	.{ .mode = "procs", .name = "Processes", .mark = "%", .glyph = glyph_process, .keywords = &.{ "top", "atop", "cpu", "processes", "monitor", "kill" } },
};

const Group = struct {
	id: []const u8,
	name: []const u8,
	glyph: []const u8,
	keywords: []const []const u8,
};

const groups = [_]Group{
	.{ .id = "apps", .name = "Apps", .glyph = glyph_apps, .keywords = &.{ "programs", "applications" } },
	.{ .id = "power", .name = "Power", .glyph = glyph_power, .keywords = &.{ "power", "session", "shutdown", "logout", "reboot", "suspend", "sleep" } },
};

const aliases = [_]struct { keep: []const u8, drop: []const []const u8 }{
	.{ .keep = "foot", .drop = &.{ "footclient", "foot-server" } },
};

const ignored = [_][]const u8{ "avahi-discover", "bssh", "bvnc" };

const Usage = struct {
	count: i64 = 0,
	last: i64 = 0,
};

const Saved = struct {
	name: []u8,
	command: []u8,
};

const Clip = struct {
	id: []u8,
	text: []u8,
	kind: []u8,
	format: []u8,
	app: []u8,
};

const Row = struct {
	id: []const u8,
	kind: []const u8,
	name: []const u8,
	glyph: []const u8,
	app_id: []const u8 = "",
	command: []const u8 = "",
	mode: []const u8 = "",
	group: []const u8 = "",
	clip_id: []const u8 = "",
	image: bool = false,
	pid: i32 = 0,
	value: f64 = 0,
	keywords: []const []const u8 = &.{},
	score: f64 = 0,
	pin: i64 = -1,
	count: i64 = 0,
	last: i64 = 0,
	power: i64 = 0,
};

const RowOut = struct {
	id: []const u8,
	kind: []const u8,
	name: []const u8,
	glyph: []const u8,
	appId: []const u8,
	command: []const u8,
	mode: []const u8,
	group: []const u8,
	clipId: []const u8,
	image: bool,
	pid: i32,
	detail: []const u8,
	pinned: bool,
};

const PreviewOut = struct {
	text: []const u8,
	path: []const u8,
};

const Out = struct {
	mode: []const u8,
	prompt: []const u8,
	query: []const u8,
	empty: []const u8,
	terminal: []const u8,
	pins: [][]const u8,
	results: []RowOut,
	clip: PreviewOut,
};

const View = struct {
	mode: []const u8,
	prompt: []const u8,
	search: []const u8,
	empty: []const u8,
};

pub const Launcher = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	apps: ?*appsmod.Apps = null,
	system: ?*sysmod.System = null,
	windows: ?*windowsmod.Windows = null,
	query: []u8 = &.{},
	forced: []u8 = &.{},
	group: []u8 = &.{},
	terminal: []u8 = &.{},
	clip_text: []u8 = &.{},
	clip_path: []u8 = &.{},
	clip_id: []u8 = &.{},
	pins: std.ArrayListUnmanaged([]u8) = .empty,
	saved: std.ArrayListUnmanaged(Saved) = .empty,
	clips: std.ArrayListUnmanaged(Clip) = .empty,
	usage: std.StringHashMapUnmanaged(Usage) = .empty,

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Launcher {
		const self = try allocator.create(Launcher);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.scratch = std.heap.ArenaAllocator.init(allocator),
		};

		return self;
	}

	pub fn attach(self: *Launcher, apps: *appsmod.Apps, system: *sysmod.System, windows: *windowsmod.Windows) void {
		self.apps = apps;
		self.system = system;
		self.windows = windows;
	}

	pub fn provider(self: *Launcher) hubmod.Provider {
		return .{ .key = "launcher", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Launcher = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn start(self: *Launcher) !void {
		self.load();
	}

	fn stateDir(self: *Launcher, allocator: Allocator) ![]u8 {
		return std.fmt.allocPrint(allocator, "{s}/.config/quickshell/cache/launcher", .{proc.home(self.io, self.allocator)});
	}

	fn statePath(self: *Launcher, allocator: Allocator, name: []const u8) ![]u8 {
		return std.fmt.allocPrint(allocator, "{s}/.config/quickshell/cache/launcher/{s}", .{ proc.home(self.io, self.allocator), name });
	}

	fn load(self: *Launcher) void {
		self.loadPins();
		self.loadUsage();
		self.loadSaved();
		self.loadTerminal();
		self.refreshClips();
	}

	fn setStr(self: *Launcher, slot: *[]u8, text: []const u8) void {
		const copy = self.allocator.dupe(u8, text) catch return;
		self.allocator.free(slot.*);
		slot.* = copy;
	}

	fn loadPins(self: *Launcher) void {
		const path = self.statePath(self.allocator, "pins.txt") catch return;
		defer self.allocator.free(path);

		const body = proc.readFile(self.io, self.allocator, path) catch "";
		defer if (body.len > 0) self.allocator.free(body);

		var next: std.ArrayListUnmanaged([]u8) = .empty;

		var lines = std.mem.splitScalar(u8, body, '\n');
		while (lines.next()) |raw| {
			const line = std.mem.trim(u8, raw, " \t\r");
			if (line.len == 0) continue;

			next.append(self.allocator, self.allocator.dupe(u8, line) catch continue) catch continue;
		}

		self.mutex.lockUncancelable(self.io);
		for (self.pins.items) |pin| self.allocator.free(pin);
		self.pins.deinit(self.allocator);
		self.pins = next;
		self.mutex.unlock(self.io);
	}

	fn loadUsage(self: *Launcher) void {
		const path = self.statePath(self.allocator, "usage.txt") catch return;
		defer self.allocator.free(path);

		const body = proc.readFile(self.io, self.allocator, path) catch "";
		defer if (body.len > 0) self.allocator.free(body);

		var next: std.StringHashMapUnmanaged(Usage) = .empty;

		var lines = std.mem.splitScalar(u8, body, '\n');
		while (lines.next()) |line| {
			var fields = std.mem.splitScalar(u8, line, '\t');
			const id = fields.next() orelse continue;
			if (id.len == 0) continue;

			const count = std.fmt.parseInt(i64, fields.next() orelse "0", 10) catch 0;
			const last = std.fmt.parseInt(i64, fields.next() orelse "0", 10) catch 0;

			next.put(self.allocator, self.allocator.dupe(u8, id) catch continue, .{ .count = count, .last = last }) catch continue;
		}

		self.mutex.lockUncancelable(self.io);
		self.clearUsage();
		self.usage = next;
		self.mutex.unlock(self.io);
	}

	fn clearUsage(self: *Launcher) void {
		var it = self.usage.iterator();

		while (it.next()) |entry| {
			self.allocator.free(entry.key_ptr.*);
		}

		self.usage.deinit(self.allocator);
	}

	fn loadSaved(self: *Launcher) void {
		const path = self.statePath(self.allocator, "entries.txt") catch return;
		defer self.allocator.free(path);

		const body = proc.readFile(self.io, self.allocator, path) catch "";
		defer if (body.len > 0) self.allocator.free(body);

		var next: std.ArrayListUnmanaged(Saved) = .empty;

		var lines = std.mem.splitScalar(u8, body, '\n');
		while (lines.next()) |line| {
			const at = std.mem.indexOfScalar(u8, line, '\t');
			const name = std.mem.trim(u8, if (at) |index| line[0..index] else line, " \t\r");
			if (name.len == 0) continue;

			const command = if (at) |index| line[index + 1 ..] else name;

			next.append(self.allocator, .{
				.name = self.allocator.dupe(u8, name) catch continue,
				.command = self.allocator.dupe(u8, std.mem.trim(u8, command, "\r")) catch continue,
			}) catch continue;
		}

		self.mutex.lockUncancelable(self.io);
		for (self.saved.items) |entry| {
			self.allocator.free(entry.name);
			self.allocator.free(entry.command);
		}
		self.saved.deinit(self.allocator);
		self.saved = next;
		self.mutex.unlock(self.io);
	}

	fn loadTerminal(self: *Launcher) void {
		const path = std.fmt.allocPrint(self.allocator, "{s}/.config/hypr/programs.lua", .{proc.home(self.io, self.allocator)}) catch return;
		defer self.allocator.free(path);

		const body = proc.readFile(self.io, self.allocator, path) catch "";
		defer if (body.len > 0) self.allocator.free(body);

		var name: []const u8 = "";

		var lines = std.mem.splitScalar(u8, body, '\n');
		while (lines.next()) |raw| {
			const line = std.mem.trim(u8, raw, " \t\r");

			if (!std.mem.startsWith(u8, line, "terminal")) continue;

			const at = std.mem.indexOfScalar(u8, line, '=') orelse continue;

			var value = std.mem.trim(u8, line[at + 1 ..], " \t");
			while (value.len > 0 and (value[0] == '"' or value[0] == '\'')) value = value[1..];

			const stop = std.mem.indexOfAny(u8, value, " \t\"'") orelse value.len;
			value = value[0..stop];

			if (value.len > 0) name = value;
		}

		self.mutex.lockUncancelable(self.io);
		self.setStr(&self.terminal, name);
		self.mutex.unlock(self.io);
	}

	pub fn refreshClips(self: *Launcher) void {
		const result = exec.run(self.io, self.allocator, &.{ "sh", "-c", "cliphist list 2>/dev/null | head -n 60" }) catch return;
		defer result.deinit(self.allocator);

		const sources_path = self.statePath(self.allocator, "clip-apps.txt") catch "";
		defer if (sources_path.len > 0) self.allocator.free(sources_path);

		const sources = if (sources_path.len > 0) blk: {
			const body = proc.readFile(self.io, self.allocator, sources_path) catch break :blk "";
			break :blk body;
		} else "";
		defer if (sources.len > 0) self.allocator.free(sources);

		var next: std.ArrayListUnmanaged(Clip) = .empty;
		var lines = std.mem.splitScalar(u8, result.out, '\n');

		while (lines.next()) |line| {
			const at = std.mem.indexOfScalar(u8, line, '\t') orelse continue;
			if (at == 0) continue;

			const id = std.mem.trim(u8, line[0..at], " \t\r");
			const preview = std.mem.trim(u8, line[at + 1 ..], " \t\r");

			if (id.len == 0 or preview.len == 0) continue;

			const format = imageFormat(preview);

			next.append(self.allocator, .{
				.id = self.allocator.dupe(u8, id) catch continue,
				.text = self.allocator.dupe(u8, preview) catch continue,
				.kind = self.allocator.dupe(u8, if (format.len > 0) "image" else "text") catch continue,
				.format = self.allocator.dupe(u8, format) catch continue,
				.app = self.allocator.dupe(u8, sourceOf(sources, id)) catch continue,
			}) catch continue;
		}

		self.mutex.lockUncancelable(self.io);
		for (self.clips.items) |entry| {
			self.allocator.free(entry.id);
			self.allocator.free(entry.text);
			self.allocator.free(entry.kind);
			self.allocator.free(entry.format);
			self.allocator.free(entry.app);
		}
		self.clips.deinit(self.allocator);
		self.clips = next;
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	pub fn setQuery(self: *Launcher, query: []const u8, forced: []const u8, group: []const u8) void {
		self.mutex.lockUncancelable(self.io);
		self.setStr(&self.query, query);
		self.setStr(&self.forced, forced);
		self.setStr(&self.group, group);
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	pub fn togglePin(self: *Launcher, id: []const u8) void {
		if (!rememberable(id)) return;

		self.mutex.lockUncancelable(self.io);

		var found: ?usize = null;
		for (self.pins.items, 0..) |pin, index| {
			if (std.mem.eql(u8, pin, id)) found = index;
		}

		if (found) |index| {
			self.allocator.free(self.pins.items[index]);
			_ = self.pins.orderedRemove(index);
		} else {
			self.pins.append(self.allocator, self.allocator.dupe(u8, id) catch &.{}) catch {};
		}

		self.mutex.unlock(self.io);

		self.savePins();
		self.hub.publish();
	}

	fn savePins(self: *Launcher) void {
		const path = self.statePath(self.allocator, "pins.txt") catch return;
		defer self.allocator.free(path);

		var out: std.ArrayList(u8) = .empty;
		defer out.deinit(self.allocator);

		self.mutex.lockUncancelable(self.io);
		for (self.pins.items, 0..) |pin, index| {
			if (index > 0) out.append(self.allocator, '\n') catch {};
			out.appendSlice(self.allocator, pin) catch {};
		}
		self.mutex.unlock(self.io);

		proc.writeFileAtomic(self.io, self.allocator, path, out.items) catch {};
	}

	pub fn remember(self: *Launcher, id: []const u8) void {
		if (!rememberable(id)) return;

		const now = std.Io.Clock.real.now(self.io).toMilliseconds();

		self.mutex.lockUncancelable(self.io);

		const entry = self.usage.getEntry(id);
		if (entry) |found| {
			found.value_ptr.count += 1;
			found.value_ptr.last = now;
		} else {
			const key = self.allocator.dupe(u8, id) catch {
				self.mutex.unlock(self.io);
				return;
			};

			self.usage.put(self.allocator, key, .{ .count = 1, .last = now }) catch {
				self.allocator.free(key);
			};
		}

		self.mutex.unlock(self.io);

		self.saveUsage();
	}

	fn saveUsage(self: *Launcher) void {
		const path = self.statePath(self.allocator, "usage.txt") catch return;
		defer self.allocator.free(path);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();

		var list: std.ArrayListUnmanaged(struct { id: []const u8, usage: Usage }) = .empty;

		self.mutex.lockUncancelable(self.io);
		var it = self.usage.iterator();
		while (it.next()) |entry| {
			list.append(allocator, .{ .id = entry.key_ptr.*, .usage = entry.value_ptr.* }) catch {};
		}
		self.mutex.unlock(self.io);

		if (list.items.len > usage_max) {
			std.mem.sort(@TypeOf(list.items[0]), list.items, {}, struct {
				fn newer(_: void, a: @TypeOf(list.items[0]), b: @TypeOf(list.items[0])) bool {
					if (a.usage.last != b.usage.last) return a.usage.last > b.usage.last;
					return a.usage.count > b.usage.count;
				}
			}.newer);

			list.shrinkRetainingCapacity(usage_max);
		}

		std.mem.sort(@TypeOf(list.items[0]), list.items, {}, struct {
			fn older(_: void, a: @TypeOf(list.items[0]), b: @TypeOf(list.items[0])) bool {
				return std.mem.lessThan(u8, a.id, b.id);
			}
		}.older);

		var out: std.ArrayList(u8) = .empty;
		defer out.deinit(self.allocator);

		for (list.items, 0..) |entry, index| {
			if (index > 0) out.append(self.allocator, '\n') catch {};
			const line = std.fmt.allocPrint(self.allocator, "{s}\t{d}\t{d}", .{ entry.id, entry.usage.count, entry.usage.last }) catch continue;
			defer self.allocator.free(line);
			out.appendSlice(self.allocator, line) catch {};
		}

		proc.writeFileAtomic(self.io, self.allocator, path, out.items) catch {};
	}

	pub fn saveQuery(self: *Launcher, query: []const u8) void {
		const name = std.mem.trim(u8, query, " \t");
		if (name.len == 0) return;

		self.mutex.lockUncancelable(self.io);

		var found = false;
		var index: usize = 0;

		while (index < self.saved.items.len) {
			const entry = self.saved.items[index];

			if (std.mem.eql(u8, entry.name, name)) {
				found = true;
				self.allocator.free(entry.name);
				self.allocator.free(entry.command);
				_ = self.saved.orderedRemove(index);
				continue;
			}

			index += 1;
		}

		if (!found) {
			self.saved.append(self.allocator, .{
				.name = self.allocator.dupe(u8, name) catch &.{},
				.command = self.allocator.dupe(u8, name) catch &.{},
			}) catch {};
		}

		self.mutex.unlock(self.io);

		self.saveSaved();
		self.hub.publish();
	}

	fn saveSaved(self: *Launcher) void {
		const path = self.statePath(self.allocator, "entries.txt") catch return;
		defer self.allocator.free(path);

		var out: std.ArrayList(u8) = .empty;
		defer out.deinit(self.allocator);

		self.mutex.lockUncancelable(self.io);
		for (self.saved.items, 0..) |entry, index| {
			if (index > 0) out.append(self.allocator, '\n') catch {};
			const line = std.fmt.allocPrint(self.allocator, "{s}\t{s}", .{ entry.name, entry.command }) catch continue;
			defer self.allocator.free(line);
			out.appendSlice(self.allocator, line) catch {};
		}
		self.mutex.unlock(self.io);

		proc.writeFileAtomic(self.io, self.allocator, path, out.items) catch {};
	}

	pub fn previewClip(self: *Launcher, id: []const u8) void {
		self.mutex.lockUncancelable(self.io);

		if (std.mem.eql(u8, self.clip_id, id)) {
			self.mutex.unlock(self.io);
			return;
		}

		self.setStr(&self.clip_id, id);
		self.mutex.unlock(self.io);

		if (id.len == 0) {
			self.mutex.lockUncancelable(self.io);
			self.setStr(&self.clip_text, "");
			self.setStr(&self.clip_path, "");
			self.mutex.unlock(self.io);
			self.hub.publish();
			return;
		}

		const script = std.fmt.allocPrint(self.allocator, "cliphist decode {s} 2>/dev/null", .{id}) catch return;
		defer self.allocator.free(script);

		const result = exec.run(self.io, self.allocator, &.{ "sh", "-c", script }) catch return;
		defer result.deinit(self.allocator);

		if (imageMagic(result.out)) |extension| {
			const path = std.fmt.allocPrint(self.allocator, "{s}/qs-clip-{s}.{s}", .{ proc.runtimeDir(self.io, self.allocator), id, extension }) catch return;
			defer self.allocator.free(path);

			if (std.Io.Dir.cwd().createFile(self.io, path, .{ .truncate = true })) |file| {
				file.writeStreamingAll(self.io, result.out) catch {};
				file.close(self.io);
			} else |_| {}

			self.mutex.lockUncancelable(self.io);
			self.setStr(&self.clip_text, "");
			self.setStr(&self.clip_path, path);
			self.mutex.unlock(self.io);

			self.hub.publish();
			return;
		}

		const text = result.out[0..@min(result.out.len, preview_bytes)];

		self.mutex.lockUncancelable(self.io);
		self.setStr(&self.clip_text, text);
		self.setStr(&self.clip_path, "");
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	pub fn copyClip(self: *Launcher, id: []const u8) void {
		if (id.len == 0) return;

		const script = std.fmt.allocPrint(self.allocator, "touch '{s}/qs-clip-self'; cliphist decode {s} | wl-copy", .{ proc.runtimeDir(self.io, self.allocator), id }) catch return;
		defer self.allocator.free(script);

		if (exec.run(self.io, self.allocator, &.{ "sh", "-c", script })) |result| {
			result.deinit(self.allocator);
		} else |_| {}
	}

	pub fn killProcess(self: *Launcher, pid: i32) void {
		_ = self;

		if (pid <= 0) return;

		_ = std.posix.kill(pid, std.posix.SIG.KILL) catch {};
	}

	pub fn activate(self: *Launcher, id: []const u8) void {
		if (id.len == 0) return;

		if (std.mem.startsWith(u8, id, "app:")) {
			if (self.windows) |windows| windows.launch(id);
			return;
		}

		if (std.mem.startsWith(u8, id, "win:")) {
			if (self.windows) |windows| windows.focus(id["win:".len..]);
			return;
		}

		if (std.mem.startsWith(u8, id, "clip:")) {
			self.copyClip(id["clip:".len..]);
			return;
		}

		if (std.mem.startsWith(u8, id, "saved:")) {
			self.runSaved(id["saved:".len..]);
			return;
		}

		if (std.mem.eql(u8, id, "calc")) self.copyCalc();
	}

	fn copyCalc(self: *Launcher) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();

		self.mutex.lockUncancelable(self.io);
		const view = self.effective(allocator, self.forced, self.group, self.query);
		self.mutex.unlock(self.io);

		const entry = calc.evaluate(allocator, view.search) orelse return;

		self.copyText(entry.value);
	}

	fn runSaved(self: *Launcher, name: []const u8) void {
		if (name.len == 0) return;

		var command: ?[]u8 = null;

		self.mutex.lockUncancelable(self.io);
		for (self.saved.items) |entry| {
			if (!std.mem.eql(u8, entry.name, name)) continue;
			command = self.allocator.dupe(u8, entry.command) catch null;
		}
		self.mutex.unlock(self.io);

		const line = command orelse return;

		const thread = std.Thread.spawn(.{}, runThread, .{ self, line }) catch {
			self.allocator.free(line);
			return;
		};
		thread.detach();
	}

	fn runThread(self: *Launcher, command: []u8) void {
		defer self.allocator.free(command);

		var child = std.process.spawn(self.io, .{
			.argv = &.{ "sh", "-c", command },
			.stdin = .ignore,
			.stdout = .ignore,
			.stderr = .ignore,
		}) catch return;

		_ = child.wait(self.io) catch {};
	}

	pub fn copyText(self: *Launcher, text: []const u8) void {
		const copy = self.allocator.dupe(u8, text) catch return;

		const thread = std.Thread.spawn(.{}, copyThread, .{ self, copy }) catch {
			self.allocator.free(copy);
			return;
		};
		thread.detach();
	}

	fn copyThread(self: *Launcher, text: []u8) void {
		defer self.allocator.free(text);

		const marker = std.fmt.allocPrint(self.allocator, "{s}/qs-clip-self", .{proc.runtimeDir(self.io, self.allocator)}) catch return;
		defer self.allocator.free(marker);

		if (std.Io.Dir.cwd().createFile(self.io, marker, .{ .truncate = true })) |file| {
			file.close(self.io);
		} else |_| {}

		var child = std.process.spawn(self.io, .{
			.argv = &.{ "wl-copy" },
			.stdin = .pipe,
			.stdout = .ignore,
			.stderr = .ignore,
		}) catch return;

		if (child.stdin) |stdin| {
			stdin.writeStreamingAll(self.io, text) catch {};
			stdin.close(self.io);
		}

		_ = child.wait(self.io) catch {};
	}

	fn effective(self: *Launcher, arena: Allocator, forced: []const u8, group: []const u8, query: []const u8) View {
		_ = self;

		if (modeOf(forced)) |entry| {
			return .{
				.mode = entry.mode,
				.prompt = entry.glyph,
				.search = query,
				.empty = emptyOf(entry.mode),
			};
		}

		if (groupOf(group) != null) {
			const mode = std.fmt.allocPrint(arena, "group:{s}", .{group}) catch "group:";

			return .{ .mode = mode, .prompt = glyph_prompt, .search = query, .empty = "Nothing here" };
		}

		const prefix = detectPrefix(query);

		if (prefix.mode.len > 0) {
			return .{
				.mode = prefix.mode,
				.prompt = promptOf(modeOf(prefix.mode)),
				.search = prefix.text,
				.empty = emptyOf(prefix.mode),
			};
		}

		return .{ .mode = "", .prompt = glyph_prompt, .search = query, .empty = "Nothing matches" };
	}

	fn build(self: *Launcher, arena: Allocator, mode: []const u8, search: []const u8) ![]Row {
		var rows: std.ArrayListUnmanaged(Row) = .empty;

		if (std.mem.eql(u8, mode, "procs")) {
			try self.buildProcs(arena, search, &rows);
			return rows.items;
		}

		if (std.mem.eql(u8, mode, "clipboard")) {
			try self.buildClips(arena, search, &rows);
			return rows.items;
		}

		if (std.mem.eql(u8, mode, "wallpaper")) return rows.items;

		if (std.mem.startsWith(u8, mode, "group:")) {
			const id = mode["group:".len..];

			if (std.mem.eql(u8, id, "apps")) {
				self.appsView(arena, search, &rows) catch {};
			}

			return self.rank(arena, rows.items, search, false);
		}

		if (mode.len > 0) return rows.items;

		self.modeRows(arena, mode, search, &rows) catch {};
		self.savedRows(arena, &rows) catch {};
		self.appsView(arena, search, &rows) catch {};

		return self.rank(arena, rows.items, search, true);
	}

	fn modeRows(self: *Launcher, arena: Allocator, mode: []const u8, search: []const u8, rows: *std.ArrayListUnmanaged(Row)) !void {
		_ = self;
		_ = mode;
		_ = search;

		for (modes) |entry| {
			if (entry.mode.len == 0) continue;

			try rows.append(arena, .{
				.id = try std.fmt.allocPrint(arena, "mode:{s}", .{entry.mode}),
				.kind = "mode",
				.name = entry.name,
				.glyph = entry.glyph,
				.mode = entry.mode,
				.keywords = entry.keywords,
			});
		}

		for (groups) |entry| {
			try rows.append(arena, .{
				.id = try std.fmt.allocPrint(arena, "group:{s}", .{entry.id}),
				.kind = "group",
				.name = entry.name,
				.glyph = entry.glyph,
				.group = entry.id,
				.keywords = entry.keywords,
			});
		}
	}

	fn savedRows(self: *Launcher, arena: Allocator, rows: *std.ArrayListUnmanaged(Row)) !void {
		for (self.saved.items) |entry| {
			try rows.append(arena, .{
				.id = try std.fmt.allocPrint(arena, "saved:{s}", .{entry.name}),
				.kind = "saved",
				.name = try arena.dupe(u8, entry.name),
				.glyph = glyph_command,
				.command = try arena.dupe(u8, entry.command),
			});
		}
	}

	fn appsView(self: *Launcher, arena: Allocator, search: []const u8, rows: *std.ArrayListUnmanaged(Row)) !void {
		const apps = self.apps orelse return;

		const ctx = struct {
			arena: Allocator,
			rows: *std.ArrayListUnmanaged(Row),

			fn run(state: @This(), entries: []const appsmod.Entry) void {
				for (entries) |entry| {
					if (isIgnored(entry.id)) continue;
					if (isDropped(entry.id)) continue;

					const id = state.arena.dupe(u8, entry.id) catch continue;
					const keywords = state.arena.alloc([]const u8, 1) catch continue;
					keywords[0] = id;

					state.rows.append(state.arena, .{
						.id = std.fmt.allocPrint(state.arena, "app:{s}", .{id}) catch continue,
						.kind = "app",
						.name = state.arena.dupe(u8, nameAlias(entry.id, entry.name)) catch continue,
						.glyph = "",
						.app_id = id,
						.command = state.arena.dupe(u8, entry.command) catch continue,
						.keywords = keywords,
					}) catch continue;
				}
			}
		}{ .arena = arena, .rows = rows };

		_ = search;
		apps.view(ctx, @TypeOf(ctx).run);
	}

	fn buildProcs(self: *Launcher, arena: Allocator, search: []const u8, rows: *std.ArrayListUnmanaged(Row)) !void {
		const system = self.system orelse return;

		const all = try system.allRows(arena);

		for (all) |*entry| {
			const name = entry.getName();

			if (!containsIgnoreCase(name, search)) continue;

			const copy = try arena.dupe(u8, name);

			try rows.append(arena, .{
				.id = try std.fmt.allocPrint(arena, "proc:{d}", .{entry.pid}),
				.kind = "proc",
				.name = copy,
				.glyph = glyph_process,
				.app_id = copy,
				.pid = entry.pid,
				.value = entry.cpu,
			});
		}

		std.mem.sort(Row, rows.items, {}, struct {
			fn less(_: void, a: Row, b: Row) bool {
				return a.value > b.value;
			}
		}.less);
	}

	fn buildClips(self: *Launcher, arena: Allocator, search: []const u8, rows: *std.ArrayListUnmanaged(Row)) !void {
		for (self.clips.items) |entry| {
			const name = if (std.mem.eql(u8, entry.kind, "image")) "Image" else entry.text;

			if (!containsIgnoreCase(name, search)) continue;

			const id = try arena.dupe(u8, entry.id);

			try rows.append(arena, .{
				.id = try std.fmt.allocPrint(arena, "clip:{s}", .{id}),
				.kind = "clip",
				.name = try arena.dupe(u8, name),
				.glyph = glyph_clip,
				.app_id = try arena.dupe(u8, entry.app),
				.clip_id = id,
				.image = std.mem.eql(u8, entry.kind, "image"),
			});
		}
	}

	fn rank(self: *Launcher, arena: Allocator, rows: []Row, search: []const u8, home: bool) []Row {
		var kept: std.ArrayListUnmanaged(Row) = .empty;

		for (rows) |row| {
			if (search.len == 0 and home) {
				if (std.mem.eql(u8, row.kind, "app") and self.pinIndex(row.id) < 0) continue;

				kept.append(arena, row) catch continue;
				continue;
			}

			const score = rowScore(arena, row, search) orelse continue;

			var next = row;
			next.score = score;

			kept.append(arena, next) catch continue;
		}

		for (kept.items) |*row| {
			row.pin = self.pinIndex(row.id);

			if (self.usage.get(row.id)) |entry| {
				row.count = entry.count;
				row.last = entry.last;
			}

			row.power = if (std.mem.eql(u8, row.kind, "action")) 1 else 0;
		}

		if (search.len > 0) {
			std.mem.sort(Row, kept.items, {}, struct {
				fn less(_: void, a: Row, b: Row) bool {
					if (a.power != b.power) return a.power < b.power;

					const unpinned_a = a.pin < 0;
					const unpinned_b = b.pin < 0;

					if (unpinned_a != unpinned_b) return unpinned_b;
					if (a.pin != b.pin) return a.pin < b.pin;
					if (a.score != b.score) return a.score > b.score;
					if (a.count != b.count) return a.count > b.count;
					if (a.last != b.last) return a.last > b.last;

					return std.mem.lessThan(u8, a.name, b.name);
				}
			}.less);
		}

		var out = kept.items;
		const wants_calc = search.len > 0 and
			!std.mem.startsWith(u8, search, "%") and
			!std.mem.startsWith(u8, search, "~");

		if (wants_calc) {
			if (calc.evaluate(arena, search)) |entry| {
				if (arena.alloc(Row, kept.items.len + 1)) |with_calc| {
					with_calc[0] = .{
						.id = "calc",
						.kind = "calc",
						.name = entry.text,
						.glyph = glyph_calc,
						.command = entry.value,
					};

					@memcpy(with_calc[1..], kept.items);
					out = with_calc;
				} else |_| {}
			}
		}

		if (out.len > max_results) out = out[0..max_results];

		return out;
	}

	fn pinIndex(self: *Launcher, id: []const u8) i64 {
		for (self.pins.items, 0..) |pin, index| {
			if (std.mem.eql(u8, pin, id)) return @intCast(index);
		}

		return -1;
	}

	fn render(self: *Launcher, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);
		const arena = self.scratch.allocator();

		const state = self.effective(arena, self.forced, self.group, self.query);
		const rows = self.build(arena, state.mode, state.search) catch &.{};

		var results: std.ArrayListUnmanaged(RowOut) = .empty;

		for (rows) |row| {
			try results.append(arena, .{
				.id = row.id,
				.kind = row.kind,
				.name = row.name,
				.glyph = row.glyph,
				.appId = row.app_id,
				.command = row.command,
				.mode = row.mode,
				.group = row.group,
				.clipId = row.clip_id,
				.image = row.image,
				.pid = row.pid,
				.detail = detailOf(arena, row) catch "",
				.pinned = self.pinIndex(row.id) >= 0,
			});
		}

		var pins: std.ArrayListUnmanaged([]const u8) = .empty;
		for (self.pins.items) |pin| try pins.append(arena, pin);

		try writer.print("{f}", .{std.json.fmt(Out{
			.mode = displayMode(state.mode),
			.prompt = state.prompt,
			.query = state.search,
			.empty = state.empty,
			.terminal = self.terminal,
			.pins = pins.items,
			.results = results.items,
			.clip = .{ .text = self.clip_text, .path = self.clip_path },
		}, .{})});
	}
};

fn promptOf(mode: ?Mode) []const u8 {
	const entry = mode orelse return glyph_prompt;
	return entry.glyph;
}

fn modeOf(mode: []const u8) ?Mode {
	for (modes) |entry| {
		if (std.mem.eql(u8, entry.mode, mode)) return entry;
	}

	return null;
}

fn groupOf(id: []const u8) ?Group {
	if (id.len == 0) return null;

	for (groups) |entry| {
		if (std.mem.eql(u8, entry.id, id)) return entry;
	}

	return null;
}

fn emptyOf(mode: []const u8) []const u8 {
	if (std.mem.eql(u8, mode, "clipboard")) return "Nothing copied yet";

	return "Nothing matches";
}

fn rememberable(id: []const u8) bool {
	return std.mem.startsWith(u8, id, "app:") or
		std.mem.startsWith(u8, id, "saved:") or
		std.mem.startsWith(u8, id, "cmd:") or
		std.mem.startsWith(u8, id, "wall:");
}

fn detailOf(arena: Allocator, row: Row) ![]const u8 {
	if (!std.mem.eql(u8, row.kind, "proc")) return "";

	return std.fmt.allocPrint(arena, "{d:.1}%", .{row.value});
}

fn displayMode(mode: []const u8) []const u8 {
	if (mode.len == 0) return "apps";
	return mode;
}

fn detectPrefix(query: []const u8) struct { mode: []const u8, text: []const u8 } {
	for (modes) |entry| {
		if (entry.mark.len == 0) continue;
		if (!std.mem.startsWith(u8, query, entry.mark)) continue;

		return .{ .mode = entry.mode, .text = query[entry.mark.len..] };
	}

	return .{ .mode = "", .text = query };
}

fn isIgnored(id: []const u8) bool {
	for (ignored) |name| {
		if (std.mem.eql(u8, id, name)) return true;
	}

	return false;
}

fn isDropped(id: []const u8) bool {
	for (aliases) |alias| {
		for (alias.drop) |name| {
			if (std.mem.eql(u8, id, name)) return true;
		}
	}

	return false;
}

fn nameAlias(id: []const u8, name: []const u8) []const u8 {
	for (aliases) |alias| {
		if (std.mem.eql(u8, id, alias.keep)) return alias.keep;
	}

	return name;
}

fn containsIgnoreCase(text: []const u8, needle: []const u8) bool {
	if (needle.len == 0) return true;
	if (needle.len > text.len) return false;

	var index: usize = 0;

	while (index + needle.len <= text.len) : (index += 1) {
		if (std.ascii.eqlIgnoreCase(text[index .. index + needle.len], needle)) return true;
	}

	return false;
}

fn rowScore(arena: Allocator, row: Row, search: []const u8) ?f64 {
	var best: ?f64 = fuzzyScore(arena, row.name, search);

	for (row.keywords) |keyword| {
		const score = fuzzyScore(arena, keyword, search) orelse continue;

		best = if (best) |value| @max(value, score) else score;
	}

	return best;
}

fn fuzzyScore(arena: Allocator, text: []const u8, search: []const u8) ?f64 {
	const target = lowerAlloc(arena, text) catch return null;
	const needle = lowerAlloc(arena, search) catch return null;

	if (needle.len == 0) return 0;
	if (std.mem.eql(u8, target, needle)) return 1000;

	var score: f64 = 0;
	var at: usize = 0;
	var streak: i64 = 0;

	for (needle) |ch| {
		const found = std.mem.indexOfScalarPos(u8, target, at, ch) orelse return null;

		streak = if (found == at) streak + 1 else 0;
		score += 10 + @as(f64, @floatFromInt(streak)) * 6;

		if (found == 0) {
			score += 30;
		} else if (std.mem.indexOfScalar(u8, " -_/.", target[found - 1]) != null) {
			score += 20;
		}

		at = found + 1;
	}

	const slack = @as(f64, @floatFromInt(target.len - needle.len));

	return score - @max(0, slack) * 0.2;
}

fn lowerAlloc(arena: Allocator, text: []const u8) ![]const u8 {
	const out = try arena.alloc(u8, text.len);

	for (text, 0..) |ch, index| {
		out[index] = std.ascii.toLower(ch);
	}

	return out;
}

fn imageMagic(body: []const u8) ?[]const u8 {
	if (body.len > 8 and std.mem.eql(u8, body[0..8], &[_]u8{ 0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a })) return "png";
	if (body.len > 3 and body[0] == 0xff and body[1] == 0xd8 and body[2] == 0xff) return "jpg";
	if (body.len > 6 and (std.mem.startsWith(u8, body, "GIF87a") or std.mem.startsWith(u8, body, "GIF89a"))) return "gif";
	if (body.len > 12 and std.mem.startsWith(u8, body, "RIFF") and std.mem.eql(u8, body[8..12], "WEBP")) return "webp";
	if (body.len > 2 and body[0] == 'B' and body[1] == 'M') return "bmp";

	return null;
}

fn imageFormat(preview: []const u8) []const u8 {
	if (!std.mem.startsWith(u8, preview, "[[")) return "";
	if (std.mem.indexOf(u8, preview, "binary data") == null) return "";

	const formats = [_][]const u8{ "png", "jpeg", "jpg", "gif", "webp", "bmp", "ico", "tiff", "tif" };

	for (formats) |format| {
		if (containsIgnoreCase(preview, format)) return format;
	}

	return "";
}

fn sourceOf(sources: []const u8, id: []const u8) []const u8 {
	var lines = std.mem.splitScalar(u8, sources, '\n');

	while (lines.next()) |line| {
		const at = std.mem.indexOfScalar(u8, line, ' ') orelse continue;
		if (!std.mem.eql(u8, std.mem.trim(u8, line[0..at], " \t"), id)) continue;

		return std.mem.trim(u8, line[at + 1 ..], " \t\r");
	}

	return "";
}

test "pins toggle and keep their order" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	try std.testing.expect(fuzzyScore(arena.allocator(), "Firefox", "fire") != null);
	try std.testing.expect(fuzzyScore(arena.allocator(), "Firefox", "zzz") == null);
	try std.testing.expect(fuzzyScore(arena.allocator(), "foot", "foot").? > fuzzyScore(arena.allocator(), "footclient", "foot").?);
}

test "the query prefix picks the mode and strips its mark" {
	const prefix = detectPrefix("%firefox");
	try std.testing.expectEqualStrings("procs", prefix.mode);
	try std.testing.expectEqualStrings("firefox", prefix.text);

	const plain = detectPrefix("firefox");
	try std.testing.expectEqualStrings("", plain.mode);
	try std.testing.expectEqualStrings("firefox", plain.text);
}

test "clipboard previews know images from text" {
	try std.testing.expectEqualStrings("png", imageFormat("[[ binary data 100x100 png 4.2 KiB ]]"));
	try std.testing.expectEqualStrings("", imageFormat("just some text"));
	try std.testing.expectEqualStrings("helium", sourceOf("1622 Alacritty\n1625 helium\n", "1625"));
	try std.testing.expectEqualStrings("Alacritty", sourceOf("1622 Alacritty\n1625 helium\n", "1622"));
	try std.testing.expectEqualStrings("", sourceOf("1622 Alacritty\n", "9"));
}

test "process rows keep every process, hottest first" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();
	const io = std.testing.io;

	var hub: hubmod.Hub = .{ .allocator = allocator, .io = io };
	const system = try sysmod.System.create(allocator, io, &hub);
	const self = try Launcher.create(allocator, io, &hub);
	self.system = system;

	try system.all.append(allocator, .{ .pid = 7, .cpu = 0 });
	try system.all.append(allocator, .{ .pid = 8, .cpu = 9 });
	try system.all.append(allocator, .{ .pid = 9, .cpu = 3 });

	var rows: std.ArrayListUnmanaged(Row) = .empty;

	try self.buildProcs(allocator, "", &rows);

	try std.testing.expectEqual(3, rows.items.len);
	try std.testing.expectEqual(@as(i32, 8), rows.items[0].pid);
	try std.testing.expectEqual(@as(i32, 9), rows.items[1].pid);
	try std.testing.expectEqual(@as(i32, 7), rows.items[2].pid);
}

test "every mode id renders rows of its own kind" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();
	const io = std.testing.io;

	var hub: hubmod.Hub = .{ .allocator = allocator, .io = io };
	const system = try sysmod.System.create(allocator, io, &hub);
	const self = try Launcher.create(allocator, io, &hub);
	self.system = system;

	try system.all.append(allocator, .{ .pid = 7, .cpu = 4 });
	try self.clips.append(allocator, .{
		.id = try allocator.dupe(u8, "9"),
		.text = try allocator.dupe(u8, "hello"),
		.kind = try allocator.dupe(u8, "text"),
		.format = try allocator.dupe(u8, ""),
		.app = try allocator.dupe(u8, ""),
	});

	for (modes) |mode| {
		const view = self.effective(allocator, mode.mode, "", "");
		try std.testing.expectEqualStrings(mode.mode, view.mode);

		const rows = try self.build(allocator, view.mode, view.search);

		for (rows) |row| {
			const own = if (std.mem.eql(u8, mode.mode, "clipboard"))
				std.mem.eql(u8, row.kind, "clip")
			else if (std.mem.eql(u8, mode.mode, "procs"))
				std.mem.eql(u8, row.kind, "proc")
			else
				false;

			try std.testing.expect(own);
		}

		if (std.mem.eql(u8, mode.mode, "clipboard")) try std.testing.expectEqual(@as(usize, 1), rows.len);
		if (std.mem.eql(u8, mode.mode, "procs")) try std.testing.expectEqual(@as(usize, 1), rows.len);
		if (std.mem.eql(u8, mode.mode, "wallpaper")) try std.testing.expectEqual(@as(usize, 0), rows.len);
	}
}

test "the forced mode wins and an unknown token is home" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();
	const io = std.testing.io;

	var hub: hubmod.Hub = .{ .allocator = allocator, .io = io };
	const self = try Launcher.create(allocator, io, &hub);

	const clip = self.effective(allocator, "clipboard", "apps", "");
	try std.testing.expectEqualStrings("clipboard", clip.mode);
	try std.testing.expectEqualStrings("Nothing copied yet", clip.empty);

	const junk = self.effective(allocator, "apps", "", "dol");
	try std.testing.expectEqualStrings("", junk.mode);
	try std.testing.expectEqualStrings("apps", displayMode(junk.mode));
	try std.testing.expectEqualStrings("dol", junk.search);

	const group = self.effective(allocator, "", "apps", "");
	try std.testing.expectEqualStrings("group:apps", group.mode);

	const unknown_group = self.effective(allocator, "", "nope", "");
	try std.testing.expectEqualStrings("", unknown_group.mode);

	const prefix = self.effective(allocator, "", "", "%x");
	try std.testing.expectEqualStrings("procs", prefix.mode);
	try std.testing.expectEqualStrings("x", prefix.search);
}

test "a pinned row sorts ahead of a better match and usage breaks the tie" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();
	const io = std.testing.io;

	var hub: hubmod.Hub = .{ .allocator = allocator, .io = io };
	const self = try Launcher.create(allocator, io, &hub);

	try self.pins.append(allocator, try allocator.dupe(u8, "app:pin"));
	try self.usage.put(allocator, try allocator.dupe(u8, "app:used"), .{ .count = 9, .last = 99 });

	var rows = [_]Row{
		.{ .id = "app:pin", .kind = "app", .name = "Pine", .glyph = "", .keywords = &.{"pine"} },
		.{ .id = "app:plain", .kind = "app", .name = "Plum", .glyph = "", .keywords = &.{"plum"} },
		.{ .id = "app:used", .kind = "app", .name = "Puma", .glyph = "", .keywords = &.{"puma"} },
	};

	const ranked = self.rank(allocator, &rows, "p", true);

	try std.testing.expectEqualStrings("app:pin", ranked[0].id);
	try std.testing.expectEqualStrings("app:used", ranked[1].id);
}

test "only launcher entries are remembered or pinned" {
	try std.testing.expect(rememberable("app:firefox"));
	try std.testing.expect(rememberable("saved:term"));
	try std.testing.expect(!rememberable("proc:12"));
	try std.testing.expect(!rememberable("clip:9"));
	try std.testing.expect(!rememberable("mode:clipboard"));
	try std.testing.expect(!rememberable("group:apps"));
	try std.testing.expect(!rememberable("win:0xaa"));
	try std.testing.expect(!rememberable("calc"));
	try std.testing.expect(!rememberable(""));
}
