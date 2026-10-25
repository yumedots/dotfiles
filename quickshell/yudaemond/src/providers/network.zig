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

const Hist = struct {
	down: f64,
	up: f64,
};

const HistOut = struct {
	down: f64,
	up: f64,
};

const history_len = 60;
const speed_seconds_text = "10";
const speed_sample_ms = 200;
const speed_down_url = "https://speed.cloudflare.com/__down";
const speed_down_bytes: u64 = 90_000_000;
const speed_up_url = "https://speed.cloudflare.com/__up";
const speed_up_bytes: u64 = 25_000_000;

const Wifi = struct {
	ssid: []u8,
	security: []u8,
	signal: i64,
	channel: i64,
	frequency: i64,
	in_use: bool,
};

const WifiOut = struct {
	ssid: []const u8,
	security: []const u8,
	signal: i64,
	channel: i64,
	frequency: i64,
	inUse: bool,
};

const Stage = enum { none, down, up };

const SpeedOut = struct {
	stage: []const u8,
	live: f64,
	best: f64,
	down: f64,
	up: f64,
};

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
	peak: f64,
	history: []HistOut,
	ip: []const u8,
	gateway: []const u8,
	dns: []const u8,
	wifi: []WifiOut,
	speed: SpeedOut,
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
	peak: f64 = 1,
	history: [history_len]Hist = @splat(.{ .down = 0, .up = 0 }),
	history_count: usize = 0,
	history_start: usize = 0,
	networks: std.ArrayListUnmanaged(Wifi) = .empty,
	ip: []u8 = &.{},
	gateway: []u8 = &.{},
	dns: []u8 = &.{},
	speed_stage: Stage = .none,
	speed_live: f64 = 0,
	speed_best: f64 = 0,
	speed_down: f64 = 0,
	speed_up: f64 = 0,
	speed_cancel: std.atomic.Value(bool) = .init(false),
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

			if (tick % 15 == 0) self.describe();

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

		self.history[self.history_start] = .{ .down = self.down, .up = self.up };
		self.history_start = (self.history_start + 1) % history_len;
		if (self.history_count < history_len) self.history_count += 1;

		self.peak = @max(1, @max(self.down, @max(self.up, self.peak * 0.98)));
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

		if (iface.len > 0) self.sampleAddresses(iface);

		if (!wifi or iface.len == 0) {
			self.mutex.lockUncancelable(self.io);
			self.setStr(&self.ssid, "");
			self.signal = 0;
			self.mutex.unlock(self.io);
			self.hub.publish();
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

		self.scan(false);

		self.hub.publish();
	}

	fn sampleAddresses(self: *Network, iface: []const u8) void {
		const result = exec.run(self.io, self.allocator, &.{ "nmcli", "-t", "-f", "IP4.ADDRESS,IP4.GATEWAY,IP4.DNS", "device", "show", iface }) catch return;
		defer result.deinit(self.allocator);

		var ip: []const u8 = "";
		var gateway: []const u8 = "";
		var dns: []const u8 = "";

		var lines = std.mem.splitScalar(u8, result.out, '\n');
		while (lines.next()) |line| {
			if (std.mem.startsWith(u8, line, "IP4.ADDRESS")) ip = afterColon(line);
			if (std.mem.startsWith(u8, line, "IP4.GATEWAY")) gateway = afterColon(line);
			if (std.mem.startsWith(u8, line, "IP4.DNS")) dns = afterColon(line);
		}

		self.mutex.lockUncancelable(self.io);
		self.setStr(&self.ip, ip);
		self.setStr(&self.gateway, gateway);
		self.setStr(&self.dns, dns);
		self.mutex.unlock(self.io);
	}

	pub fn scan(self: *Network, rescan: bool) void {
		var argv: std.ArrayList([]const u8) = .empty;
		defer argv.deinit(self.allocator);

		const base = [_][]const u8{ "nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,CHAN,FREQ,SECURITY", "device", "wifi", "list" };
		for (base) |arg| argv.append(self.allocator, arg) catch return;
		if (rescan) argv.append(self.allocator, "--rescan") catch {};
		if (rescan) argv.append(self.allocator, "yes") catch {};

		const result = exec.run(self.io, self.allocator, argv.items) catch return;
		defer result.deinit(self.allocator);

		var next: std.ArrayListUnmanaged(Wifi) = .empty;
		var lines = std.mem.splitScalar(u8, result.out, '\n');

		while (lines.next()) |line| {
			if (line.len == 0) continue;

			var at: usize = 0;
			const in_use = terseField(line, &at) orelse continue;
			const ssid_raw = terseField(line, &at) orelse continue;
			if (ssid_raw.len == 0) continue;

			const signal_text = terseField(line, &at) orelse "0";
			const channel_text = terseField(line, &at) orelse "0";
			const freq_text = terseField(line, &at) orelse "0";
			const security_raw = terseField(line, &at) orelse "";

			const ssid = unescapeTerse(self.allocator, ssid_raw) catch continue;
			const security = unescapeTerse(self.allocator, security_raw) catch {
				self.allocator.free(ssid);
				continue;
			};

			next.append(self.allocator, .{
				.ssid = ssid,
				.security = security,
				.signal = std.fmt.parseInt(i64, signal_text, 10) catch 0,
				.channel = std.fmt.parseInt(i64, channel_text, 10) catch 0,
				.frequency = std.fmt.parseInt(i64, std.mem.trimEnd(u8, freq_text, " "), 10) catch 0,
				.in_use = std.mem.eql(u8, std.mem.trim(u8, in_use, " "), "*"),
			}) catch continue;
		}

		self.mutex.lockUncancelable(self.io);
		for (self.networks.items) |entry| {
			self.allocator.free(entry.ssid);
			self.allocator.free(entry.security);
		}
		self.networks.deinit(self.allocator);
		self.networks = next;
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	pub fn setDns(self: *Network, connection: []const u8, servers: []const u8) void {
		var argv: std.ArrayList([]const u8) = .empty;
		defer argv.deinit(self.allocator);

		for ([_][]const u8{ "nmcli", "connection", "modify", "id", connection, "ipv4.dns", servers, "ipv4.ignore-auto-dns", "yes" }) |arg|
			argv.append(self.allocator, arg) catch return;

		const result = exec.run(self.io, self.allocator, argv.items) catch return;
		result.deinit(self.allocator);

		const up = exec.run(self.io, self.allocator, &.{ "nmcli", "connection", "up", "id", connection }) catch return;
		up.deinit(self.allocator);

		self.sampleAddresses(connection);
		self.hub.publish();
	}

	pub fn speedTest(self: *Network) void {
		self.mutex.lockUncancelable(self.io);
		const busy = self.speed_stage != .none;
		if (!busy) {
			self.speed_stage = .down;
			self.speed_live = 0;
			self.speed_best = 0;
			self.speed_down = 0;
			self.speed_up = 0;
			self.speed_cancel.store(false, .monotonic);
		}
		self.mutex.unlock(self.io);

		if (busy) return;

		self.hub.publish();

		const thread = std.Thread.spawn(.{}, speedRun, .{self}) catch return;
		thread.detach();
	}

	pub fn speedCancel(self: *Network) void {
		self.speed_cancel.store(true, .monotonic);
	}

	fn speedRun(self: *Network) void {
		const down = self.speedPhase(true);
		self.mutex.lockUncancelable(self.io);
		const cancelled = self.speed_cancel.load(.monotonic);
		self.speed_down = down;
		self.speed_stage = if (cancelled) .none else .up;
		self.speed_live = 0;
		self.speed_best = 0;
		self.mutex.unlock(self.io);
		self.hub.publish();

		if (cancelled) return;

		const up = self.speedPhase(false);
		self.mutex.lockUncancelable(self.io);
		self.speed_up = up;
		self.speed_stage = .none;
		self.speed_live = 0;
		self.speed_best = 0;
		self.mutex.unlock(self.io);
		self.hub.publish();
	}

	fn speedPhase(self: *Network, download: bool) f64 {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();

		var stop = std.atomic.Value(bool).init(false);
		const sampler = std.Thread.spawn(.{}, speedSample, .{ self, &stop, download }) catch return 0;

		const url = if (download) speed_down_url else speed_up_url;
		const bytes = if (download) speed_down_bytes else speed_up_bytes;

		var argv: std.ArrayList([]const u8) = .empty;

		if (download) {
			const target = std.fmt.allocPrint(allocator, "{s}?bytes={d}", .{ url, bytes }) catch return 0;

			for ([_][]const u8{ "curl", "-s", "-m", speed_seconds_text, "-o", "/dev/null", target }) |arg|
				argv.append(allocator, arg) catch return 0;
		} else {
			const script = std.fmt.allocPrint(allocator, "head -c {d} /dev/zero | curl -s -m {s} -o /dev/null -X POST --data-binary @- '{s}'", .{ bytes, speed_seconds_text, url }) catch return 0;

			for ([_][]const u8{ "sh", "-c", script }) |arg| argv.append(allocator, arg) catch return 0;
		}

		if (exec.run(self.io, self.allocator, argv.items)) |result| {
			result.deinit(self.allocator);
		} else |_| {}

		stop.store(true, .monotonic);
		sampler.join();

		self.mutex.lockUncancelable(self.io);
		const best = self.speed_best;
		self.mutex.unlock(self.io);

		return best;
	}

	fn speedSample(self: *Network, stop: *std.atomic.Value(bool), download: bool) void {
		var prev: u64 = 0;
		var prev_at: i64 = 0;

		while (!stop.load(.monotonic) and !self.speed_cancel.load(.monotonic)) {
			const bytes = self.counter(download);
			const now = std.Io.Clock.real.now(self.io).toMilliseconds();

			if (prev_at > 0 and now > prev_at and bytes >= prev) {
				const seconds = @as(f64, @floatFromInt(now - prev_at)) / 1000.0;
				const inst = @as(f64, @floatFromInt(bytes - prev)) / seconds;

				if (inst > 0) {
					self.mutex.lockUncancelable(self.io);
					self.speed_live = if (self.speed_live > 0) self.speed_live + (inst - self.speed_live) * 0.15 else inst;
					self.speed_best = @max(self.speed_best, self.speed_live);
					self.mutex.unlock(self.io);

					self.hub.publish();
				}
			}

			prev = bytes;
			prev_at = now;
			sleep.ms(speed_sample_ms);
		}
	}

	fn counter(self: *Network, download: bool) u64 {
		self.mutex.lockUncancelable(self.io);
		const iface = self.allocator.dupe(u8, self.iface) catch {
			self.mutex.unlock(self.io);
			return 0;
		};
		self.mutex.unlock(self.io);
		defer self.allocator.free(iface);

		const body = proc.readFile(self.io, self.allocator, "/proc/net/dev") catch return 0;
		defer self.allocator.free(body);

		var lines = std.mem.splitScalar(u8, body, '\n');

		while (lines.next()) |raw| {
			const line = std.mem.trim(u8, raw, " \t\r");
			const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
			const name = std.mem.trim(u8, line[0..colon], " \t");

			if (iface.len > 0 and !std.mem.eql(u8, name, iface)) continue;
			if (iface.len == 0 and (std.mem.eql(u8, name, "lo") or std.mem.startsWith(u8, name, "veth"))) continue;

			var fields = std.mem.tokenizeAny(u8, line[colon + 1 ..], " \t");
			var index: usize = 0;

			while (fields.next()) |field| : (index += 1) {
				const wanted: usize = if (download) 0 else 8;
				if (index == wanted) return std.fmt.parseInt(u64, field, 10) catch 0;
			}
		}

		return 0;
	}

	pub fn connect(self: *Network, ssid: []const u8, password: []const u8) void {
		var argv: std.ArrayList([]const u8) = .empty;
		defer argv.deinit(self.allocator);

		for ([_][]const u8{ "nmcli", "device", "wifi", "connect", ssid }) |arg| argv.append(self.allocator, arg) catch return;
		if (password.len > 0) {
			argv.append(self.allocator, "password") catch {};
			argv.append(self.allocator, password) catch {};
		}

		const result = exec.run(self.io, self.allocator, argv.items) catch return;
		result.deinit(self.allocator);

		self.describe();
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
			.peak = @round(self.peak),
			.history = try historyOut(arena, self),
			.ip = self.ip,
			.gateway = self.gateway,
			.dns = self.dns,
			.wifi = try wifiOut(arena, self),
			.speed = .{
				.stage = if (self.speed_stage == .none) "" else @tagName(self.speed_stage),
				.live = @round(self.speed_live),
				.best = @round(self.speed_best),
				.down = @round(self.speed_down),
				.up = @round(self.speed_up),
			},
		};

		try writer.print("{f}", .{std.json.fmt(out, .{})});
	}
};

fn historyOut(arena: Allocator, self: *Network) ![]HistOut {
	var out: std.ArrayListUnmanaged(HistOut) = .empty;
	const start = (self.history_start + history_len - self.history_count) % history_len;

	for (0..self.history_count) |index| {
		const entry = self.history[(start + index) % history_len];
		try out.append(arena, .{ .down = @round(entry.down), .up = @round(entry.up) });
	}

	return out.items;
}

fn terseField(line: []const u8, at: *usize) ?[]const u8 {
	if (at.* >= line.len) return null;

	const start = at.*;
	var index = start;

	while (index < line.len) {
		if (line[index] == '\\' and index + 1 < line.len) {
			index += 2;
			continue;
		}

		if (line[index] == ':') break;
		index += 1;
	}

	at.* = index + 1;
	return line[start..index];
}

fn unescapeTerse(allocator: Allocator, line: []const u8) ![]u8 {
	var out: std.ArrayList(u8) = .empty;
	errdefer out.deinit(allocator);

	var index: usize = 0;
	while (index < line.len) : (index += 1) {
		if (line[index] == '\\' and index + 1 < line.len) {
			index += 1;
			try out.append(allocator, line[index]);
			continue;
		}

		try out.append(allocator, line[index]);
	}

	return out.toOwnedSlice(allocator);
}

fn afterColon(line: []const u8) []const u8 {
	const at = std.mem.indexOfScalar(u8, line, ':') orelse return "";
	return std.mem.trim(u8, line[at + 1 ..], " \t\r");
}

fn wifiOut(arena: Allocator, self: *Network) ![]WifiOut {
	var out: std.ArrayListUnmanaged(WifiOut) = .empty;

	for (self.networks.items) |entry| {
		try out.append(arena, .{
			.ssid = entry.ssid,
			.security = entry.security,
			.signal = entry.signal,
			.channel = entry.channel,
			.frequency = entry.frequency,
			.inUse = entry.in_use,
		});
	}

	return out.items;
}

fn rateText(allocator: Allocator, rate: f64) ![]u8 {
	if (rate < 1024) return std.fmt.allocPrint(allocator, "{d} B/s", .{@as(i64, @intFromFloat(rate))});
	if (rate < 1024 * 1024) return std.fmt.allocPrint(allocator, "{d:.1} KiB/s", .{rate / 1024});
	if (rate < 1024 * 1024 * 1024) return std.fmt.allocPrint(allocator, "{d:.1} MiB/s", .{rate / (1024 * 1024)});

	return std.fmt.allocPrint(allocator, "{d:.1} GiB/s", .{rate / (1024 * 1024 * 1024)});
}

test "nmcli terse lines keep escaped colons inside the ssid" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const line = "*:My\\:Net:80:6:2437:WPA2";
	var at: usize = 0;

	try std.testing.expectEqualStrings("*", terseField(line, &at).?);
	const ssid = try unescapeTerse(arena.allocator(), terseField(line, &at).?);
	try std.testing.expectEqualStrings("My:Net", ssid);
	try std.testing.expectEqualStrings("80", terseField(line, &at).?);
	try std.testing.expectEqualStrings("6", terseField(line, &at).?);
	try std.testing.expectEqualStrings("2437", terseField(line, &at).?);
	try std.testing.expectEqualStrings("WPA2", terseField(line, &at).?);
	try std.testing.expect(terseField(line, &at) == null);
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
