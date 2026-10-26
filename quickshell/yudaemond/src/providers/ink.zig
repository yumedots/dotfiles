const std = @import("std");
const hubmod = @import("../hub.zig");
const exec = @import("../primitives/exec.zig");
const json = @import("../primitives/json.zig");
const fmt = @import("../primitives/fmt.zig");
const proc = @import("../primitives/proc.zig");
const sleep = @import("../primitives/sleep.zig");
const watch = @import("../primitives/watch.zig");
const wallpaper = @import("wallpaper.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const state_file = ".config/quickshell/cache/bar-ink.json";
const daemon_bin = "/usr/bin/awww-daemon";
const ink_prefix = "awww-ink-";
const black_ink = "#000000";
const white_ink = "#ffffff";

const State = struct {
	bare: bool,
	band: i64,
};

pub const Ink = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	show_mutex: std.Io.Mutex = .init,
	bare: bool = false,
	band: i64 = 0,
	inks: std.StringHashMapUnmanaged([]u8) = .empty,
	wallpaper: ?*wallpaper.Wallpaper = null,
	generation: std.atomic.Value(u64) = .init(0),

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Ink {
		const self = try allocator.create(Ink);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
		};

		return self;
	}

	pub fn provider(self: *Ink) hubmod.Provider {
		return .{ .key = "ink", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Ink = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn attach(self: *Ink, source: *wallpaper.Wallpaper) void {
		self.wallpaper = source;
	}

	pub fn start(self: *Ink) !void {
		self.load();
		_ = self.refresh(null);

		const keeper = try std.Thread.spawn(.{}, keepDaemon, .{self});
		keeper.detach();

		const watcher = try std.Thread.spawn(.{}, watchLoop, .{self});
		watcher.detach();

		if (self.bare) self.reapply();
	}

	pub fn set(self: *Ink, band: i64, bare: ?bool) void {
		self.mutex.lockUncancelable(self.io);
		const changed = band > 0 and self.band != band;
		if (band > 0) self.band = band;
		if (bare) |flag| self.bare = flag;
		self.mutex.unlock(self.io);

		self.persist();
		self.hub.publish();

		if (changed) self.reapply();
	}

	pub fn apply(self: *Ink, path: []const u8, band: i64) void {
		if (path.len == 0) return;

		self.mutex.lockUncancelable(self.io);
		const changed = band > 0 and self.band != band;
		if (band > 0) self.band = band;
		self.mutex.unlock(self.io);

		if (changed) self.persist();

		self.sync(path);
	}

	fn reapply(self: *Ink) void {
		const source = self.wallpaper orelse return;

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const path = source.activePath(arena.allocator()) orelse return;
		self.sync(path);
	}

	fn sync(self: *Ink, path: []const u8) void {
		const copy = self.allocator.dupe(u8, path) catch return;
		const generation = self.generation.fetchAdd(1, .monotonic) + 1;

		const thread = std.Thread.spawn(.{}, show, .{ self, copy, generation }) catch {
			self.allocator.free(copy);
			return;
		};

		thread.detach();
	}

	fn show(self: *Ink, path: []u8, generation: u64) void {
		defer self.allocator.free(path);

		// one wallpaper transition at a time: overlapping `awww img` runs finish out of order
		// and leave whichever drew last on screen
		self.show_mutex.lockUncancelable(self.io);
		defer self.show_mutex.unlock(self.io);

		if (self.generation.load(.monotonic) != generation) return;

		self.mutex.lockUncancelable(self.io);
		const band = self.band;
		self.mutex.unlock(self.io);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();

		var argv: std.ArrayListUnmanaged([]const u8) = .empty;

		argv.appendSlice(allocator, &.{ "awww", "img", "--transition-type", "fade", "--transition-duration", "0.4", "--transition-fps", "60" }) catch return;

		if (band > 0) {
			const rows = std.fmt.allocPrint(allocator, "{d}", .{band}) catch return;
			argv.appendSlice(allocator, &.{ "--ink-band", rows }) catch return;
		}

		argv.append(allocator, path) catch return;

		const started = fmt.nowMs(self.io);
		const result = exec.run(self.io, self.allocator, argv.items) catch return;
		defer result.deinit(self.allocator);
		std.debug.print("DBG t={d} img code={d} ms={d}\n", .{ fmt.nowMs(self.io), result.code, fmt.nowMs(self.io) - started });

		if (result.code != 0) return;

		// awww measured the band of the frame it just drew and published the verdict; read it
		// back rather than leaning on the fade timer
		_ = self.refresh(generation);
	}

	fn refresh(self: *Ink, generation: ?u64) bool {
		if (generation) |wanted| {
			if (self.generation.load(.monotonic) != wanted) return false;
		}

		if (!self.readInks()) return false;

		self.persist();
		self.hub.publish();

		return true;
	}

	/// Rebuilds the per-output ink map from the `awww-ink-<output>` files the wallpaper daemon
	/// writes when it measures a frame. Each file holds `black` or `white`; the bar paints the
	/// pure colour, exactly like the QML singleton did before the port.
	fn readInks(self: *Ink) bool {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();
		const dir_path = proc.runtimeDir(self.io, allocator);

		var dir = std.Io.Dir.cwd().openDir(self.io, dir_path, .{ .iterate = true }) catch return false;
		defer dir.close(self.io);

		var next: std.StringHashMapUnmanaged([]u8) = .empty;

		var it = dir.iterate();
		while (it.next(self.io) catch null) |item| {
			if (item.kind != .file) continue;
			if (!std.mem.startsWith(u8, item.name, ink_prefix)) continue;

			const path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, item.name }) catch continue;
			const raw = proc.readFile(self.io, allocator, path) catch continue;
			const colour = colourOf(raw) orelse continue;

			const key = self.allocator.dupe(u8, item.name[ink_prefix.len..]) catch continue;
			const value = self.allocator.dupe(u8, colour) catch {
				self.allocator.free(key);
				continue;
			};

			next.put(self.allocator, key, value) catch {
				self.allocator.free(key);
				self.allocator.free(value);
			};
		}

		self.mutex.lockUncancelable(self.io);

		const same = sameInks(&self.inks, &next);

		if (!same) {
			var old = self.inks.iterator();
			while (old.next()) |entry| {
				self.allocator.free(entry.key_ptr.*);
				self.allocator.free(entry.value_ptr.*);
			}
			self.inks.deinit(self.allocator);
			self.inks = next;
		}

		self.mutex.unlock(self.io);

		if (same) {
			var stale = next.iterator();
			while (stale.next()) |entry| {
				self.allocator.free(entry.key_ptr.*);
				self.allocator.free(entry.value_ptr.*);
			}
			next.deinit(self.allocator);
		}

		return !same;
	}

	fn watchLoop(self: *Ink) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();
		const dir_path = proc.runtimeDir(self.io, allocator);
		const dir = allocator.allocSentinel(u8, dir_path.len, 0) catch return;
		@memcpy(dir, dir_path);

		var watcher = watch.Watcher.init() catch return;
		defer watcher.close();

		watcher.add(dir) catch return;

		while (true) {
			const name = watcher.next() catch {
				sleep.ms(1000);
				continue;
			};

			if (!std.mem.startsWith(u8, name, ink_prefix)) continue;

			// awww writes once per drawn frame through the fade; let the burst settle, then read
			// whatever the file holds now
			sleep.ms(80);
			_ = self.refresh(null);
		}
	}

	fn persist(self: *Ink) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();
		const path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ proc.home(self.io, self.allocator), state_file }) catch return;

		const body = self.stateBody(allocator) orelse return;
		proc.writeFileAtomic(self.io, self.allocator, path, body) catch return;
	}

	fn stateBody(self: *Ink, allocator: Allocator) ?[]const u8 {
		var buffer: Writer.Allocating = .init(allocator);

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		buffer.writer.print("{{\"bare\":{s},\"band\":{d},", .{
			if (self.bare) "true" else "false",
			self.band,
		}) catch return null;

		self.writeInks(&buffer.writer, allocator) catch return null;
		buffer.writer.writeAll("}") catch return null;

		return buffer.toOwnedSlice() catch null;
	}

	fn writeInks(self: *Ink, writer: *Writer, allocator: Allocator) !void {
		var keys: std.ArrayListUnmanaged([]const u8) = .empty;
		defer keys.deinit(allocator);

		var it = self.inks.iterator();
		while (it.next()) |entry| keys.append(allocator, entry.key_ptr.*) catch {};

		std.mem.sort([]const u8, keys.items, {}, lessThan);

		try writer.writeAll("\"inks\":{");

		for (keys.items, 0..) |key, index| {
			const value = self.inks.get(key) orelse continue;

			if (index > 0) try writer.writeAll(",");

			try json.write(writer, key);
			try writer.writeAll(":");
			try json.write(writer, value);
		}

		try writer.writeAll("},\"verdicts\":{");

		for (keys.items, 0..) |key, index| {
			const value = self.inks.get(key) orelse continue;

			if (index > 0) try writer.writeAll(",");

			try json.write(writer, key);
			try writer.writeAll(":");
			try json.write(writer, if (std.mem.eql(u8, value, black_ink)) "black" else "white");
		}

		try writer.writeAll("}");
	}

	fn load(self: *Ink) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();
		const path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ proc.home(self.io, self.allocator), state_file }) catch return;

		const raw = proc.readFile(self.io, allocator, path) catch return;
		const parsed = json.parse(allocator, raw) catch return;
		const state = stateOf(parsed.value);

		self.mutex.lockUncancelable(self.io);
		self.bare = state.bare;
		self.band = state.band;

		if (json.field(parsed.value, "inks")) |inks| {
			if (inks == .object) {
				var it = inks.object.iterator();
				while (it.next()) |entry| {
					const key = self.allocator.dupe(u8, entry.key_ptr.*) catch continue;
					const value = self.allocator.dupe(u8, json.text(entry.value_ptr.*)) catch {
						self.allocator.free(key);
						continue;
					};
					self.inks.put(self.allocator, key, value) catch {
						self.allocator.free(key);
						self.allocator.free(value);
					};
				}
			}
		}

		self.mutex.unlock(self.io);
	}

	fn keepDaemon(self: *Ink) void {
		while (true) {
			if (self.daemonAlive()) {
				sleep.ms(5000);
				continue;
			}

			self.runDaemon();
			sleep.ms(1000);
		}
	}

	fn daemonAlive(self: *Ink) bool {
		const display = proc.env(self.io, self.allocator, "WAYLAND_DISPLAY") orelse return true;

		const path = std.fmt.allocPrint(self.allocator, "{s}/{s}-awww-daemon.sock", .{ proc.runtimeDir(self.io, self.allocator), display }) catch return true;
		defer self.allocator.free(path);

		return proc.exists(self.io, path);
	}

	fn runDaemon(self: *Ink) void {
		var child = std.process.spawn(self.io, .{
			.argv = &.{daemon_bin},
			.stdin = .ignore,
			.stdout = .ignore,
			.stderr = .ignore,
		}) catch {
			sleep.ms(5000);
			return;
		};

		_ = child.wait(self.io) catch {};
	}

	fn render(self: *Ink, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		try writer.print("{{\"bare\":{s},\"band\":{d},", .{
			if (self.bare) "true" else "false",
			self.band,
		});

		try self.writeInks(writer, self.allocator);
		try writer.writeAll("}");
	}
};

fn stateOf(root: json.Value) State {
	return .{
		.bare = json.flag(root, "bare"),
		.band = json.integer(json.field(root, "band")),
	};
}

/// The runtime file awww writes holds `black` or `white`; the bar paints that colour purely,
/// with no tint of its own.
fn colourOf(raw: []const u8) ?[]const u8 {
	const text_ = std.mem.trim(u8, raw, " \t\r\n");

	if (std.mem.eql(u8, text_, "black")) return black_ink;
	if (std.mem.eql(u8, text_, "white")) return white_ink;

	return null;
}

fn sameInks(a: *const std.StringHashMapUnmanaged([]u8), b: *const std.StringHashMapUnmanaged([]u8)) bool {
	if (a.count() != b.count()) return false;

	var it = a.iterator();
	while (it.next()) |entry| {
		const other = b.get(entry.key_ptr.*) orelse return false;
		if (!std.mem.eql(u8, entry.value_ptr.*, other)) return false;
	}

	return true;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
	return std.mem.lessThan(u8, a, b);
}

test "the stored state keeps the band and the bare flag" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const parsed = try json.parse(arena.allocator(), "{\"bare\":true,\"band\":33}");
	const state = stateOf(parsed.value);

	try std.testing.expect(state.bare);
	try std.testing.expectEqual(@as(i64, 33), state.band);

	const empty = try json.parse(arena.allocator(), "{}");
	try std.testing.expect(!stateOf(empty.value).bare);
}

test "the awww ink file maps to the pure colour the bar paints" {
	try std.testing.expectEqualStrings("#000000", colourOf("black\n").?);
	try std.testing.expectEqualStrings("#ffffff", colourOf(" white ").?);

	try std.testing.expect(colourOf("purple") == null);
	try std.testing.expect(colourOf("") == null);
}

test "the ink map keeps every output" {
	var a: std.StringHashMapUnmanaged([]u8) = .empty;
	defer a.deinit(std.testing.allocator);
	var b: std.StringHashMapUnmanaged([]u8) = .empty;
	defer b.deinit(std.testing.allocator);

	const key = try std.testing.allocator.dupe(u8, "DP-2");
	const value = try std.testing.allocator.dupe(u8, "#ffffff");
	defer std.testing.allocator.free(key);
	defer std.testing.allocator.free(value);
	try a.put(std.testing.allocator, key, value);

	try std.testing.expectEqual(false, sameInks(&a, &b));

	const key2 = try std.testing.allocator.dupe(u8, "DP-2");
	const value2 = try std.testing.allocator.dupe(u8, "#ffffff");
	defer std.testing.allocator.free(key2);
	defer std.testing.allocator.free(value2);
	try b.put(std.testing.allocator, key2, value2);

	try std.testing.expect(sameInks(&a, &b));
}
