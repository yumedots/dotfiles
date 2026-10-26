const std = @import("std");
const hubmod = @import("../hub.zig");
const exec = @import("../primitives/exec.zig");
const hypr = @import("../primitives/hypr.zig");
const json = @import("../primitives/json.zig");
const proc = @import("../primitives/proc.zig");
const sleep = @import("../primitives/sleep.zig");
const wallpaper = @import("wallpaper.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const state_file = ".config/quickshell/cache/bar-ink.json";
const sample_bin = "/usr/bin/ffmpeg";
const daemon_bin = "/usr/bin/awww-daemon";
const transition = "fade";
const transition_ms = 400;
const transition_fps = 60;

const State = struct {
	bare: bool,
	band: i64,
};

pub const Ink = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	bare: bool = false,
	band: i64 = 0,
	inks: std.StringHashMapUnmanaged([]u8) = .empty,
	wallpaper: ?*wallpaper.Wallpaper = null,
	sampled: []u8 = &.{},
	sampled_band: i64 = -1,
	wake: std.Io.Semaphore = .{},

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Ink {
		const self = try allocator.create(Ink);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.scratch = std.heap.ArenaAllocator.init(allocator),
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

		const sampler = try std.Thread.spawn(.{}, loop, .{self});
		sampler.detach();

		const keeper = try std.Thread.spawn(.{}, keepDaemon, .{self});
		keeper.detach();

		self.wake.post(self.io);
	}

	fn loop(self: *Ink) void {
		while (true) {
			self.wake.waitUncancelable(self.io);

			var tries: usize = 0;
			while (tries < 20) : (tries += 1) {
				if (self.refresh()) break;
				sleep.ms(1000);
			}
		}
	}

	pub fn set(self: *Ink, band: i64, bare: ?bool) void {
		self.mutex.lockUncancelable(self.io);
		if (band > 0) self.band = band;
		if (bare) |flag| self.bare = flag;
		self.mutex.unlock(self.io);

		self.persist();
		self.wake.post(self.io);
		self.hub.publish();
	}

	pub fn apply(self: *Ink, path: []const u8, band: i64) void {
		if (path.len == 0) return;

		if (band > 0) {
			self.mutex.lockUncancelable(self.io);
			const changed = self.band != band;
			self.band = band;
			self.mutex.unlock(self.io);

			if (changed) self.persist();
		}

		self.wake.post(self.io);

		const copy = self.allocator.dupe(u8, path) catch return;
		const thread = std.Thread.spawn(.{}, show, .{ self, copy }) catch {
			self.allocator.free(copy);
			return;
		};

		thread.detach();
	}

	fn show(self: *Ink, path: []u8) void {
		defer self.allocator.free(path);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();

		const duration = std.fmt.allocPrint(allocator, "{d:.3}", .{@as(f64, @floatFromInt(transition_ms)) / 1000.0}) catch return;
		const fps = std.fmt.allocPrint(allocator, "{d}", .{transition_fps}) catch return;

		const argv = [_][]const u8{
			"awww", "img",       "--transition-type", transition,
			"--transition-duration", duration, "--transition-fps", fps,
			path,
		};

		const result = exec.run(self.io, self.allocator, &argv) catch return;
		result.deinit(self.allocator);
	}

	fn refresh(self: *Ink) bool {
		const source = self.wallpaper orelse return true;

		self.mutex.lockUncancelable(self.io);
		const band = self.band;
		self.mutex.unlock(self.io);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();

		const path = source.activePath(allocator) orelse return true;
		if (path.len == 0) return true;

		const preview = source.previewFor(allocator, path) orelse return false;
		if (std.mem.eql(u8, preview, self.sampled) and band == self.sampled_band) return true;

		var names: std.ArrayListUnmanaged([]u8) = .empty;
		defer {
			for (names.items) |name| self.allocator.free(name);
			names.deinit(self.allocator);
		}

		self.screens(&names);
		if (names.items.len == 0) return false;

		const rgb = self.sample(preview, band) orelse return false;

		self.store(preview, band, names.items, rgb);
		return true;
	}

	fn screens(self: *Ink, out: *std.ArrayListUnmanaged([]u8)) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();

		const body = hypr.request(self.io, allocator, "j/monitors") catch return;
		const parsed = json.parse(allocator, body) catch return;

		for (json.list(parsed.value)) |entry| {
			const name = json.textAt(entry, "name");
			if (name.len == 0 or json.flag(entry, "disabled")) continue;

			out.append(self.allocator, self.allocator.dupe(u8, name) catch continue) catch {};
		}
	}

	fn sample(self: *Ink, preview: []const u8, band: i64) ?[3]u8 {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const strip = if (band > 0)
			std.fmt.allocPrint(arena.allocator(), "min(ih\\,max(1\\,{d}))", .{@min(band, 512)}) catch return null
		else
			"ih*5/100";

		const filter = std.fmt.allocPrint(arena.allocator(), "crop=iw:{s}:0:0,scale=1:1", .{strip}) catch return null;

		const argv = [_][]const u8{
			sample_bin, "-v", "error", "-i", preview, "-vf", filter,
			"-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgb24", "-",
		};

		const result = exec.run(self.io, self.allocator, &argv) catch return null;
		defer result.deinit(self.allocator);

		if (result.code != 0 or result.out.len < 3) return null;
		return .{ result.out[0], result.out[1], result.out[2] };
	}

	fn store(self: *Ink, preview: []const u8, band: i64, names: []const []u8, rgb: [3]u8) void {
		const colour = inkColor(rgb);

		self.mutex.lockUncancelable(self.io);

		var it = self.inks.iterator();
		while (it.next()) |entry| {
			self.allocator.free(entry.key_ptr.*);
			self.allocator.free(entry.value_ptr.*);
		}
		self.inks.clearRetainingCapacity();

		for (names) |name| {
			const key = self.allocator.dupe(u8, name) catch continue;
			const value = self.allocator.dupe(u8, &colour) catch {
				self.allocator.free(key);
				continue;
			};
			self.inks.put(self.allocator, key, value) catch {
				self.allocator.free(key);
				self.allocator.free(value);
			};
		}

		self.sampled_band = band;
		const copy = self.allocator.dupe(u8, preview) catch null;
		if (copy) |path| {
			self.allocator.free(self.sampled);
			self.sampled = path;
		}

		self.mutex.unlock(self.io);

		self.persist();
		self.hub.publish();
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
		try writer.writeAll("\"inks\":{");

		var keys: std.ArrayListUnmanaged([]const u8) = .empty;
		defer keys.deinit(allocator);

		var it = self.inks.iterator();
		while (it.next()) |entry| keys.append(allocator, entry.key_ptr.*) catch {};

		std.mem.sort([]const u8, keys.items, {}, lessThan);

		for (keys.items, 0..) |key, index| {
			const value = self.inks.get(key) orelse continue;

			if (index > 0) try writer.writeAll(",");

			try json.write(writer, key);
			try writer.writeAll(":");
			try json.write(writer, value);
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

fn inkColor(rgb: [3]u8) [7]u8 {
	const r: f64 = @floatFromInt(rgb[0]);
	const g: f64 = @floatFromInt(rgb[1]);
	const b: f64 = @floatFromInt(rgb[2]);

	const luma = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
	const target: f64 = if (luma < 0.5) 255 else 0;

	var out: [7]u8 = .{ '#', '0', '0', '0', '0', '0', '0' };
	const hex = "0123456789abcdef";

	for ([_]u8{ rgb[0], rgb[1], rgb[2] }, 0..) |value, index| {
		const mixed = @round(@as(f64, @floatFromInt(value)) * 0.25 + target * 0.75);
		const clamped: u8 = @intFromFloat(@min(255.0, @max(0.0, mixed)));

		out[1 + index * 2] = hex[clamped >> 4];
		out[2 + index * 2] = hex[clamped & 0xf];
	}

	return out;
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

test "the ink keeps the band hue and flips with its luminance" {
	try std.testing.expectEqualStrings("#bfbfbf", &inkColor(.{ 0, 0, 0 }));
	try std.testing.expectEqualStrings("#404040", &inkColor(.{ 255, 255, 255 }));
	try std.testing.expectEqualStrings("#f1c4c4", &inkColor(.{ 200, 20, 20 }));
}
