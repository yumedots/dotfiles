const std = @import("std");
const hubmod = @import("../hub.zig");
const proc = @import("../primitives/proc.zig");
const exec = @import("../primitives/exec.zig");
const sleep = @import("../primitives/sleep.zig");
const sleep_unused = sleep;

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const Out = struct {
	iface: []const u8,
	kind: []const u8,
	connected: bool,
	ssid: []const u8,
	signal: i64,
	down: f64,
	up: f64,
	downText: []const u8,
	upText: []const u8,
	linkSpeed: i64,
};

pub const Network = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	iface: []u8 = &.{},
	kind: []u8 = &.{},
	ssid: []u8 = &.{},
	signal: i64 = 0,
	down: f64 = 0,
	up: f64 = 0,
	connected: bool = false,
	link_speed: i64 = 0,
	last_rx: u64 = 0,
	last_tx: u64 = 0,
	last_at: i64 = 0,
	tick: usize = 0,

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Network {
		const self = try allocator.create(Network);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.scratch = std.heap.ArenaAllocator.init(allocator),
		};

		return self;
	}

	pub fn provider(self: *Network) hubmod.Provider {
		return .{ .key = "network", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Network = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn start(self: *Network) !void {
		const thread = try std.Thread.spawn(.{}, loop, .{self});
		thread.detach();
	}

	fn loop(self: *Network) void {
		var tick: usize = 0;

		while (true) {
			self.sample();

			if (tick % 5 == 0) self.describe();

			tick += 1;
			sleep_unused.ms(1000);
		}
	}

	fn sample(self: *Network) void {
		self.refreshIface();

		const body = proc.readFile(self.io, self.allocator, "/proc/net/dev") catch return;
		defer self.allocator.free(body);

		self.mutex.lockUncancelable(self.io);
		const iface = self.allocator.dupe(u8, self.iface) catch {
			self.mutex.unlock(self.io);
			return;
		};
		self.mutex.unlock(self.io);
		defer self.allocator.free(iface);

		var lines = std.mem.splitScalar(u8, body, '\n');
		var rx: u64 = 0;
		var tx: u64 = 0;

		while (lines.next()) |raw| {
			const line = std.mem.trim(u8, raw, " \t\r");
			const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
			const name = std.mem.trim(u8, line[0..colon], " \t");

			if (iface.len > 0 and !std.mem.eql(u8, name, iface)) continue;
			if (iface.len == 0 and (std.mem.eql(u8, name, "lo") or std.mem.startsWith(u8, name, "veth"))) continue;

			var fields = std.mem.tokenizeAny(u8, line[colon + 1 ..], " \t");
			var index: usize = 0;

			while (fields.next()) |field| : (index += 1) {
				if (index == 0) rx += std.fmt.parseInt(u64, field, 10) catch 0;
				if (index == 8) tx += std.fmt.parseInt(u64, field, 10) catch 0;
			}
		}

		const now = std.Io.Clock.real.now(self.io).toMilliseconds();

		self.mutex.lockUncancelable(self.io);
		if (self.last_at > 0 and now > self.last_at) {
			const seconds = @as(f64, @floatFromInt(now - self.last_at)) / 1000.0;
			self.down = if (rx >= self.last_rx) @as(f64, @floatFromInt(rx - self.last_rx)) / seconds else 0;
			self.up = if (tx >= self.last_tx) @as(f64, @floatFromInt(tx - self.last_tx)) / seconds else 0;
		}

		self.last_rx = rx;
		self.last_tx = tx;
		self.last_at = now;
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn refreshIface(self: *Network) void {
		const body = proc.readFile(self.io, self.allocator, "/proc/net/route") catch return;
		defer self.allocator.free(body);

		var best_iface: []const u8 = "";
		var best_metric: i64 = std.math.maxInt(i64);

		var lines = std.mem.splitScalar(u8, body, '\n');
		_ = lines.next();

		while (lines.next()) |raw| {
			var fields = std.mem.tokenizeAny(u8, raw, " \t");

			const name = fields.next() orelse continue;
			const dest = fields.next() orelse continue;
			if (!std.mem.eql(u8, dest, "00000000")) continue;

			_ = fields.next() orelse continue;
			_ = fields.next() orelse continue;
			_ = fields.next() orelse continue;
			_ = fields.next() orelse continue;

			const metric_text = fields.next() orelse "0";
			const metric = std.fmt.parseInt(i64, metric_text, 10) catch 0;

			if (metric < best_metric) {
				best_metric = metric;
				best_iface = name;
			}
		}

		if (best_iface.len == 0) return;

		const wireless_path = std.fmt.allocPrint(self.allocator, "/sys/class/net/{s}/wireless", .{best_iface}) catch return;
		defer self.allocator.free(wireless_path);

		const kind: []const u8 = if (proc.exists(self.io, wireless_path)) "wifi" else "ethernet";

		const state_path = std.fmt.allocPrint(self.allocator, "/sys/class/net/{s}/operstate", .{best_iface}) catch return;
		defer self.allocator.free(state_path);

		const state_body = proc.readFile(self.io, self.allocator, state_path) catch "";
		defer if (state_body.len > 0) self.allocator.free(state_body);

		const up = std.mem.startsWith(u8, state_body, "up");

		const speed_path = std.fmt.allocPrint(self.allocator, "/sys/class/net/{s}/speed", .{best_iface}) catch return;
		defer self.allocator.free(speed_path);

		const speed_body = proc.readFile(self.io, self.allocator, speed_path) catch "";
		defer if (speed_body.len > 0) self.allocator.free(speed_body);

		const speed = std.fmt.parseInt(i64, std.mem.trim(u8, speed_body, " \n\r"), 10) catch 0;

		self.mutex.lockUncancelable(self.io);
		self.setStr(&self.iface, best_iface);
		self.setStr(&self.kind, kind);
		self.connected = up;
		self.link_speed = speed;
		self.mutex.unlock(self.io);
	}

	fn describe(self: *Network) void {
		self.mutex.lockUncancelable(self.io);
		const iface = self.allocator.dupe(u8, self.iface) catch {
			self.mutex.unlock(self.io);
			return;
		};
		const wifi = std.mem.eql(u8, self.kind, "wifi");
		self.mutex.unlock(self.io);
		defer self.allocator.free(iface);

		if (!wifi or iface.len == 0) {
			self.mutex.lockUncancelable(self.io);
			self.setStr(&self.ssid, "");
			self.signal = 0;
			self.mutex.unlock(self.io);
			return;
		}

		const result = exec.run(self.io, self.allocator, &.{ "iw", "dev", iface, "link" }) catch return;
		defer result.deinit(self.allocator);

		var ssid: []const u8 = "";
		var signal: i64 = 0;

		var lines = std.mem.splitScalar(u8, result.out, '\n');
		while (lines.next()) |raw| {
			const line = std.mem.trim(u8, raw, " \t\r");

			if (std.mem.startsWith(u8, line, "SSID:")) ssid = std.mem.trim(u8, line["SSID:".len..], " \t");
			if (std.mem.startsWith(u8, line, "signal:")) {
				const text = std.mem.trim(u8, line["signal:".len..], " \tdBm");
				signal = std.fmt.parseInt(i64, text, 10) catch 0;
			}
		}

		const percent: i64 = if (signal == 0) 0 else std.math.clamp(2 * (signal + 100), 0, 100);

		self.mutex.lockUncancelable(self.io);
		self.setStr(&self.ssid, ssid);
		self.signal = percent;
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn setStr(self: *Network, slot: *[]u8, value: []const u8) void {
		const copy = self.allocator.dupe(u8, value) catch return;
		self.allocator.free(slot.*);
		slot.* = copy;
	}

	fn render(self: *Network, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);
		const arena = self.scratch.allocator();

		const out = Out{
			.iface = self.iface,
			.kind = self.kind,
			.connected = self.connected,
			.ssid = self.ssid,
			.signal = self.signal,
			.down = @round(self.down),
			.up = @round(self.up),
			.downText = try rateText(arena, self.down),
			.upText = try rateText(arena, self.up),
			.linkSpeed = self.link_speed,
		};

		try writer.print("{f}", .{std.json.fmt(out, .{})});
	}
};

fn rateText(allocator: Allocator, rate: f64) ![]u8 {
	if (rate < 1024) return std.fmt.allocPrint(allocator, "{d} B/s", .{@as(i64, @intFromFloat(rate))});
	if (rate < 1024 * 1024) return std.fmt.allocPrint(allocator, "{d:.1} KiB/s", .{rate / 1024});
	if (rate < 1024 * 1024 * 1024) return std.fmt.allocPrint(allocator, "{d:.1} MiB/s", .{rate / (1024 * 1024)});

	return std.fmt.allocPrint(allocator, "{d:.1} GiB/s", .{rate / (1024 * 1024 * 1024)});
}

test "rates format" {
	const allocator = std.testing.allocator;

	const bytes = try rateText(allocator, 512);
	defer allocator.free(bytes);
	try std.testing.expectEqualStrings("512 B/s", bytes);

	const mib = try rateText(allocator, 14_000_000);
	defer allocator.free(mib);
	try std.testing.expectEqualStrings("13.4 MiB/s", mib);
}
