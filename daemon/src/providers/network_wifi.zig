const std = @import("std");
const json = @import("../primitives/json.zig");
const exec = @import("../primitives/exec.zig");
const views = @import("network_out.zig");
const net = @import("network.zig");
const sleep = @import("../primitives/sleep.zig");

const Allocator = std.mem.Allocator;
const Network = net.Network;

pub const Wifi = struct {
	ssid: []u8,
	security: []u8,
	signal: i64,
	channel: i64,
	frequency: i64,
	in_use: bool,
	saved: bool,
};

pub const Adapter = struct {
	kind: []u8,
	iface: []u8,
	state: []u8,
	connection: []u8,
};

const Job = struct {
	net: *Network,
	ssid: []u8,
	password: []u8,
};

pub fn freeNetworks(allocator: Allocator, list: *std.ArrayListUnmanaged(Wifi)) void {
	for (list.items) |entry| {
		allocator.free(entry.ssid);
		allocator.free(entry.security);
	}

	list.deinit(allocator);
}

fn freeAdapters(allocator: Allocator, list: *std.ArrayListUnmanaged(Adapter)) void {
	for (list.items) |entry| {
		allocator.free(entry.kind);
		allocator.free(entry.iface);
		allocator.free(entry.state);
		allocator.free(entry.connection);
	}

	list.deinit(allocator);
}

fn savedNames(self: *Network, arena: Allocator) []const []const u8 {
	const result = exec.run(self.io, self.allocator, &.{ "nmcli", "-t", "-f", "NAME,TYPE", "connection", "show" }) catch return &.{};
	defer result.deinit(self.allocator);

	var out: std.ArrayListUnmanaged([]const u8) = .empty;
	var lines = std.mem.splitScalar(u8, result.out, '\n');

	while (lines.next()) |line| {
		var at: usize = 0;
		const name = terseField(line, &at) orelse continue;
		const kind = terseField(line, &at) orelse continue;

		if (!std.mem.eql(u8, kind, "802-11-wireless")) continue;

		const text = unescapeTerse(arena, name) catch continue;
		out.append(arena, text) catch continue;
	}

	return out.items;
}

fn clientIface(self: *Network) ?[]u8 {
	self.mutex.lockUncancelable(self.io);
	defer self.mutex.unlock(self.io);

	for (self.adapters.items) |entry| {
		if (std.mem.eql(u8, entry.kind, "wifi")) return self.allocator.dupe(u8, entry.iface) catch null;
	}

	return null;
}

pub fn scan(self: *Network, rescan: bool) void {
	if (self.hold.load(.monotonic)) return;

	if (rescan) refreshAdapters(self);

	var arena = std.heap.ArenaAllocator.init(self.allocator);
	defer arena.deinit();
	const scratch = arena.allocator();

	var next: std.ArrayListUnmanaged(Wifi) = .empty;

	self.mutex.lockUncancelable(self.io);
	const radio = self.radio;
	self.mutex.unlock(self.io);

	const client = clientIface(self);
	defer if (client) |name| self.allocator.free(name);

	if (client != null and radio) {
		var argv: std.ArrayList([]const u8) = .empty;
		defer argv.deinit(self.allocator);

		const base = [_][]const u8{ "nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,CHAN,FREQ,SECURITY", "device", "wifi", "list", "ifname", client.? };
		for (base) |arg| argv.append(self.allocator, arg) catch return;
		if (rescan) argv.append(self.allocator, "--rescan") catch {};
		if (rescan) argv.append(self.allocator, "yes") catch {};

		const saved = savedNames(self, scratch);

		if (exec.run(self.io, self.allocator, argv.items)) |result| {
			defer result.deinit(self.allocator);
			collect(self, &next, result.out, saved);
		} else |_| {}
	}

	self.mutex.lockUncancelable(self.io);

	var up = false;
	for (self.adapters.items) |entry| {
		if (std.mem.eql(u8, entry.kind, "wifi") and std.mem.startsWith(u8, entry.state, "connected")) up = true;
	}

	if (!up) {
		for (next.items) |*entry| entry.in_use = false;
	}

	freeNetworks(self.allocator, &self.networks);
	self.networks = next;

	var ssid: []const u8 = "";
	var signal: i64 = 0;

	if (std.mem.eql(u8, self.kind, "wifi")) {
		for (self.networks.items) |entry| {
			if (!entry.in_use) continue;
			ssid = entry.ssid;
			signal = entry.signal;
			break;
		}
	}

	self.setStr(&self.ssid, ssid);
	self.signal = signal;
	self.mutex.unlock(self.io);

	self.hub.publish();
}

fn collect(self: *Network, next: *std.ArrayListUnmanaged(Wifi), body: []const u8, saved: []const []const u8) void {
	var lines = std.mem.splitScalar(u8, body, '\n');

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

		var known = false;
		for (saved) |name| {
			if (std.mem.eql(u8, name, ssid)) known = true;
		}

		var duplicate = false;
		for (next.items) |*entry| {
			if (!std.mem.eql(u8, entry.ssid, ssid)) continue;

			duplicate = true;
			if (std.mem.eql(u8, std.mem.trim(u8, in_use, " "), "*")) entry.in_use = true;

			const signal = std.fmt.parseInt(i64, signal_text, 10) catch 0;
			if (signal > entry.signal) entry.signal = signal;
		}

		if (duplicate) {
			self.allocator.free(ssid);
			self.allocator.free(security);
			continue;
		}

		next.append(self.allocator, .{
			.ssid = ssid,
			.security = security,
			.signal = std.fmt.parseInt(i64, signal_text, 10) catch 0,
			.channel = std.fmt.parseInt(i64, channel_text, 10) catch 0,
			.frequency = frequencyOf(freq_text),
			.in_use = std.mem.eql(u8, std.mem.trim(u8, in_use, " "), "*"),
			.saved = known,
		}) catch {
			self.allocator.free(ssid);
			self.allocator.free(security);
		};
	}
}

fn hostsAccessPoint(self: *Network, name: []const u8) bool {
	const result = exec.run(self.io, self.allocator, &.{ "nmcli", "-g", "802-11-wireless.mode", "connection", "show", "id", name }) catch return false;
	defer result.deinit(self.allocator);

	return std.mem.startsWith(u8, result.out, "ap");
}

pub fn refreshAdapters(self: *Network) void {
	const devices = exec.run(self.io, self.allocator, &.{ "nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device" }) catch return;
	defer devices.deinit(self.allocator);

	var next: std.ArrayListUnmanaged(Adapter) = .empty;
	var lines = std.mem.splitScalar(u8, devices.out, '\n');

	while (lines.next()) |line| {
		var at: usize = 0;
		const iface = terseField(line, &at) orelse continue;
		const kind = terseField(line, &at) orelse continue;
		const state = terseField(line, &at) orelse "";
		const connection = terseField(line, &at) orelse "";

		if (!std.mem.eql(u8, kind, "wifi") and !std.mem.eql(u8, kind, "ethernet")) continue;
		if (std.mem.eql(u8, kind, "wifi") and std.mem.startsWith(u8, state, "connected") and hostsAccessPoint(self, connection)) continue;

		const entry = Adapter{
			.kind = self.allocator.dupe(u8, kind) catch continue,
			.iface = self.allocator.dupe(u8, iface) catch continue,
			.state = self.allocator.dupe(u8, state) catch continue,
			.connection = unescapeTerse(self.allocator, connection) catch continue,
		};

		next.append(self.allocator, entry) catch continue;
	}

	const radio = exec.run(self.io, self.allocator, &.{ "nmcli", "radio", "wifi" }) catch null;
	defer if (radio) |item| item.deinit(self.allocator);

	self.mutex.lockUncancelable(self.io);
	freeAdapters(self.allocator, &self.adapters);
	self.adapters = next;
	if (radio) |item| self.radio = std.mem.startsWith(u8, std.mem.trim(u8, item.out, " \r\n"), "enabled");
	self.mutex.unlock(self.io);
}

pub fn setRadio(self: *Network, on: bool) void {
	const result = exec.run(self.io, self.allocator, &.{ "nmcli", "radio", "wifi", if (on) "on" else "off" }) catch return;
	result.deinit(self.allocator);

	self.setNote(&self.wifi_error, "");
	self.setNote(&self.wifi_ask, "");

	self.mutex.lockUncancelable(self.io);
	self.radio = on;
	if (!on) freeNetworks(self.allocator, &self.networks);
	if (!on) self.networks = .empty;
	self.mutex.unlock(self.io);
	self.hub.publish();

	refreshAdapters(self);
	scan(self, false);

	if (!on) return;

	var tries: usize = 0;
	while (tries < 10) : (tries += 1) {
		self.mutex.lockUncancelable(self.io);
		const found = self.networks.items.len > 0;
		self.mutex.unlock(self.io);

		if (found) break;

		sleep.ms(400);
		refreshAdapters(self);
		scan(self, false);
	}

	scan(self, true);
}

pub fn useKind(self: *Network, kind: []const u8) void {
	refreshAdapters(self);

	if (std.mem.eql(u8, kind, "wifi")) {
		self.mutex.lockUncancelable(self.io);
		const radio = self.radio;
		self.mutex.unlock(self.io);

		if (!radio) setRadio(self, true);
	}

	var target: []u8 = &.{};
	var others: std.ArrayListUnmanaged([]u8) = .empty;

	self.mutex.lockUncancelable(self.io);
	for (self.adapters.items) |entry| {
		if (std.mem.eql(u8, entry.kind, kind)) {
			if (target.len == 0) {
				if (self.allocator.dupe(u8, entry.iface)) |copy| target = copy else |_| {}
			}
		} else if (std.mem.startsWith(u8, entry.state, "connected")) {
			const copy = self.allocator.dupe(u8, entry.iface) catch continue;
			others.append(self.allocator, copy) catch self.allocator.free(copy);
		}
	}
	self.mutex.unlock(self.io);

	defer {
		for (others.items) |item| self.allocator.free(item);
		others.deinit(self.allocator);
		if (target.len > 0) self.allocator.free(target);
	}

	if (target.len == 0) return;

	const up = exec.run(self.io, self.allocator, &.{ "nmcli", "device", "connect", target }) catch return;
	defer up.deinit(self.allocator);

	if (up.code != 0) {
		self.setNote(&self.wifi_error, failureText(&up));
		self.hub.publish();
		return;
	}

	self.setNote(&self.wifi_error, "");

	for (others.items) |iface| {
		const down = exec.run(self.io, self.allocator, &.{ "nmcli", "device", "disconnect", iface }) catch continue;
		down.deinit(self.allocator);
	}

	refreshAdapters(self);
	self.describe();
}

pub fn connect(self: *Network, ssid: []const u8, password: []const u8) void {
	const job = self.allocator.create(Job) catch return;
	job.* = .{
		.net = self,
		.ssid = self.allocator.dupe(u8, ssid) catch {
			self.allocator.destroy(job);
			return;
		},
		.password = self.allocator.dupe(u8, password) catch {
			self.allocator.free(job.ssid);
			self.allocator.destroy(job);
			return;
		},
	};

	const thread = std.Thread.spawn(.{}, connectRun, .{job}) catch {
		release(job);
		return;
	};
	thread.detach();
}

fn release(job: *Job) void {
	const allocator = job.net.allocator;
	allocator.free(job.ssid);
	allocator.free(job.password);
	allocator.destroy(job);
}

fn connectRun(job: *Job) void {
	defer release(job);

	const self = job.net;

	var saved = false;
	var locked = false;

	self.mutex.lockUncancelable(self.io);
	for (self.networks.items) |entry| {
		if (!std.mem.eql(u8, entry.ssid, job.ssid)) continue;

		saved = entry.saved;
		locked = views.locked(entry.security);
		break;
	}
	self.mutex.unlock(self.io);

	self.setNote(&self.wifi_pending, job.ssid);
	self.setNote(&self.wifi_error, "");
	self.setNote(&self.wifi_ask, "");
	self.hub.publish();

	var argv: std.ArrayList([]const u8) = .empty;
	defer argv.deinit(self.allocator);

	const client = clientIface(self);
	defer if (client) |name| self.allocator.free(name);

	const fresh = job.password.len > 0 or !saved;

	const head: []const []const u8 = if (fresh) &.{ "nmcli", "device", "wifi", "connect", job.ssid } else &.{ "nmcli", "connection", "up", "id", job.ssid };

	for (head) |arg| argv.append(self.allocator, arg) catch return;
	if (job.password.len > 0) {
		argv.append(self.allocator, "password") catch return;
		argv.append(self.allocator, job.password) catch return;
	}

	if (client) |name| {
		argv.append(self.allocator, "ifname") catch return;
		argv.append(self.allocator, name) catch return;
	}

	const result = exec.run(self.io, self.allocator, argv.items) catch {
		self.setNote(&self.wifi_pending, "");
		self.setNote(&self.wifi_error, "nmcli did not run");
		self.hub.publish();
		return;
	};
	defer result.deinit(self.allocator);

	self.setNote(&self.wifi_pending, "");

	if (result.code != 0) {
		self.setNote(&self.wifi_error, failureText(&result));
		if (locked) self.setNote(&self.wifi_ask, job.ssid);
	}

	refreshAdapters(self);
	self.describe();
	self.hub.publish();
}

pub fn failureText(result: *const exec.Result) []const u8 {
	return summary(result.err);
}

fn summary(text: []const u8) []const u8 {
	if (std.mem.indexOf(u8, text, "Secrets were required") != null) return "Wrong password";

	const prefixes = [_][]const u8{ "Error: ", "Connection activation failed: ", "Failed to add/activate new connection: " };
	var last: []const u8 = "";
	var lines = std.mem.splitScalar(u8, text, '\n');

	while (lines.next()) |raw| {
		const line = std.mem.trim(u8, raw, " \t\r");

		if (line.len > 0) last = line;
	}

	var again = true;
	while (again) {
		again = false;

		for (prefixes) |prefix| {
			if (std.mem.startsWith(u8, last, prefix)) {
				last = last[prefix.len..];
				again = true;
			}
		}
	}

	return if (last.len > 0) last else "nmcli failed";
}

pub fn seed(self: *Network, items: []const json.Value) void {
	if (items.len == 0) return;

	var next: std.ArrayListUnmanaged(Wifi) = .empty;

	freeNetworks(self.allocator, &self.networks);

	for (items) |item| {
		const ssid = self.allocator.dupe(u8, json.textAt(item, "ssid")) catch continue;
		const security = self.allocator.dupe(u8, json.textAt(item, "security")) catch {
			self.allocator.free(ssid);
			continue;
		};

		next.append(self.allocator, .{
			.ssid = ssid,
			.security = security,
			.signal = json.integer(json.field(item, "signal")),
			.channel = 0,
			.frequency = 0,
			.in_use = json.flag(item, "inUse"),
			.saved = json.flag(item, "saved"),
		}) catch continue;
	}

	self.networks = next;
}

pub fn wifiOut(arena: Allocator, self: *Network) ![]views.WifiOut {
	var out: std.ArrayListUnmanaged(views.WifiOut) = .empty;

	for (self.networks.items) |entry| {
		try out.append(arena, .{
			.ssid = entry.ssid,
			.security = entry.security,
			.locked = views.locked(entry.security),
			.saved = entry.saved,
			.signal = entry.signal,
			.signalText = try views.signalText(arena, entry.signal),
			.bars = views.signalBars(entry.signal),
			.channel = entry.channel,
			.frequency = entry.frequency,
			.inUse = entry.in_use,
		});
	}

	return out.items;
}

pub fn adaptersOut(arena: Allocator, self: *Network) ![]views.AdapterOut {
	var out: std.ArrayListUnmanaged(views.AdapterOut) = .empty;

	for (self.adapters.items) |entry| {
		try out.append(arena, .{
			.kind = entry.kind,
			.iface = entry.iface,
			.state = entry.state,
			.connection = entry.connection,
			.connected = std.mem.startsWith(u8, entry.state, "connected"),
			.active = self.iface.len > 0 and std.mem.eql(u8, entry.iface, self.iface),
		});
	}

	return out.items;
}

fn frequencyOf(text: []const u8) i64 {
	var parts = std.mem.tokenizeScalar(u8, text, ' ');

	return std.fmt.parseInt(i64, parts.next() orelse "", 10) catch 0;
}

pub fn terseField(line: []const u8, at: *usize) ?[]const u8 {
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

pub fn unescapeTerse(allocator: Allocator, line: []const u8) ![]u8 {
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

test "device lines split into iface type state and connection" {
	const line = "wlan0:wifi:connected:Home\\:5G";
	var at: usize = 0;

	try std.testing.expectEqualStrings("wlan0", terseField(line, &at).?);
	try std.testing.expectEqualStrings("wifi", terseField(line, &at).?);
	try std.testing.expectEqualStrings("connected", terseField(line, &at).?);
	try std.testing.expectEqualStrings("Home\\:5G", terseField(line, &at).?);
}

test "failure summary keeps the last line without nmcli prefixes" {
	try std.testing.expectEqualStrings("Wrong password", summary("Warning: password for 'x' invalid\nError: Connection activation failed: (7) Secrets were required, but not provided.\n"));
	try std.testing.expectEqualStrings("No suitable device", summary("Error: Connection activation failed: No suitable device\n"));
	try std.testing.expectEqualStrings("nmcli failed", summary("  \n"));
}

test "frequency drops the unit" {
	try std.testing.expectEqual(@as(i64, 2437), frequencyOf("2437 MHz"));
	try std.testing.expectEqual(@as(i64, 0), frequencyOf(""));
}

test "wifi security decides whether a network is locked" {
	try std.testing.expect(views.locked("WPA2"));
	try std.testing.expect(views.locked("WPA1 WPA2 802.1X"));
	try std.testing.expect(!views.locked(""));
	try std.testing.expect(!views.locked("--"));
}
