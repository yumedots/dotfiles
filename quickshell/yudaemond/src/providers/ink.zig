const std = @import("std");
const hubmod = @import("../hub.zig");
const exec = @import("../primitives/exec.zig");
const json = @import("../primitives/json.zig");
const fmt = @import("../primitives/fmt.zig");
const proc = @import("../primitives/proc.zig");
const sleep = @import("../primitives/sleep.zig");
const wallpaper = @import("wallpaper.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const state_file = ".config/quickshell/cache/bar-ink.json";
const daemon_bin = "/usr/bin/awww-daemon";
const black_ink = "#101010";
const white_ink = "#ffffff";

const State = struct {
	bare: bool,
	band: i64,
};

const Reading = struct {
	output: []const u8,
	word: []const u8,
};

pub const Ink = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
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

		const keeper = try std.Thread.spawn(.{}, keepDaemon, .{self});
		keeper.detach();

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

		self.collect(band, generation);
	}

	fn collect(self: *Ink, band: i64, generation: u64) void {
		if (band <= 0) return;

		if (self.generation.load(.monotonic) != generation) return;

		const started2 = fmt.nowMs(self.io);
		const result = exec.run(self.io, self.allocator, &.{ "awww", "query" }) catch return;
		defer result.deinit(self.allocator);
		std.debug.print("DBG query ms={d}\n", .{fmt.nowMs(self.io) - started2});

		if (result.code != 0) return;

		if (self.generation.load(.monotonic) != generation) return;

		self.mutex.lockUncancelable(self.io);

		var old = self.inks.iterator();
		while (old.next()) |entry| {
			self.allocator.free(entry.key_ptr.*);
			self.allocator.free(entry.value_ptr.*);
		}
		self.inks.clearRetainingCapacity();

		var lines = std.mem.splitScalar(u8, result.out, '\n');
		while (lines.next()) |line| {
			const ink = reading(line) orelse continue;

			const colour = if (std.mem.eql(u8, ink.word, "black")) black_ink else white_ink;
			const key = self.allocator.dupe(u8, ink.output) catch continue;
			const value = self.allocator.dupe(u8, colour) catch {
				self.allocator.free(key);
				continue;
			};

			self.inks.put(self.allocator, key, value) catch {
				self.allocator.free(key);
				self.allocator.free(value);
			};
		}

		self.mutex.unlock(self.io);

		const started3 = fmt.nowMs(self.io);
		self.persist();
		const mid = fmt.nowMs(self.io);
		self.hub.publish();
		const done = fmt.nowMs(self.io);
		std.debug.print("DBG t={d} persist ms={d} publish ms={d}\n", .{ done, mid - started3, done - mid });
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

fn reading(line: []const u8) ?Reading {
	const marker = std.mem.indexOf(u8, line, ", ink: ") orelse return null;
	const rest = line[marker + ", ink: ".len ..];

	var end: usize = 0;
	while (end < rest.len and rest[end] != ' ' and rest[end] != '(') end += 1;
	if (end == 0) return null;

	const word = rest[0..end];
	if (!std.mem.eql(u8, word, "black") and !std.mem.eql(u8, word, "white")) return null;

	const name = std.mem.indexOf(u8, line, ": ") orelse return null;
	const start = name + 2;

	const colon = std.mem.indexOfScalarPos(u8, line, start, ':') orelse return null;
	return .{ .output = line[start..colon], .word = word };
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

test "the daemon query line gives the output and the ink word" {
	const line = ": DP-2: 1920x1080, scale: 1.3333334, currently displaying: image: /home/me/wall.png, ink: white (#d5cde8)";
	const ink = reading(line).?;

	try std.testing.expectEqualStrings("DP-2", ink.output);
	try std.testing.expectEqualStrings("white", ink.word);

	const named = reading("test: HDMI-A-1: 2560x1440, scale: 1.0, currently displaying: image: /w.jpg, ink: black (#101010)").?;
	try std.testing.expectEqualStrings("HDMI-A-1", named.output);
	try std.testing.expectEqualStrings("black", named.word);

	try std.testing.expect(reading(": DP-2: 1920x1080, scale: 1.0, currently displaying: image: /w.jpg") == null);
	try std.testing.expect(reading(": DP-2: 1920x1080, currently displaying: color: 000000, ink: purple (#101010)") == null);
}
