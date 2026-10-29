const std = @import("std");
const hubmod = @import("hub.zig");
const http = @import("primitives/http.zig");
const json = @import("primitives/json.zig");
const proc = @import("primitives/proc.zig");
const sock = @import("primitives/sock.zig");
const opencode = @import("providers/opencode.zig");

const gpa = std.heap.smp_allocator;
const Io = std.Io;

var failures: usize = 0;

pub fn run(io: Io, args: []const []const u8) !void {
	_ = args;

	var buffer: [16384]u8 = undefined;
	var file_writer = std.Io.File.stdout().writer(io, &buffer);
	const w = &file_writer.interface;

	try w.writeAll("state machine\n");
	try machine(io, w);

	try w.writeAll("live\n");
	try live(io, w);

	try w.flush();

	if (failures > 0) {
		try w.print("{d} failures\n", .{failures});
		std.process.exit(1);
	}

	try w.writeAll("parity ok\n");
	try w.flush();
}

fn machine(io: Io, w: *std.Io.Writer) !void {
	var hub: hubmod.Hub = .{ .allocator = gpa, .io = io };
	var client = http.Client.init(gpa, io);
	const provider = try opencode.Opencode.create(gpa, io, &hub, &client);

	// The url is empty on purpose: no network is touched, only events are fed.
	try expect(w, "empty is idle", provider.faceState(), "idle");

	provider.handleEvent("{\"type\":\"session.execution.started\",\"data\":{\"sessionID\":\"a\"}}");
	try expect(w, "started is working", provider.faceState(), "working");

	provider.handleEvent("{\"type\":\"session.execution.failed\",\"data\":{\"sessionID\":\"a\",\"error\":{\"message\":\"boom\"}}}");
	try expect(w, "failed is error", provider.faceState(), "error");
	try expect(w, "failure text", provider.detail(), "boom");

	provider.handleEvent("{\"type\":\"permission.asked\",\"data\":{\"sessionID\":\"a\",\"message\":\"allow?\"}}");
	try expect(w, "permission blocks", provider.faceState(), "blocked");
	try expect(w, "permission text", provider.detail(), "allow?");

	provider.handleEvent("{\"type\":\"permission.replied\",\"data\":{\"sessionID\":\"a\"}}");
	try expect(w, "reply clears block", provider.faceState(), "error");

	provider.handleEvent("{\"type\":\"session.execution.started\",\"data\":{\"sessionID\":\"a\"}}");
	try expect(w, "restart is working", provider.faceState(), "working");

	provider.handleEvent("{\"type\":\"session.execution.succeeded\",\"data\":{\"sessionID\":\"a\"}}");
	try expect(w, "success returns to idle", provider.faceState(), "idle");

	provider.handleEvent("{\"type\":\"form.created\",\"data\":{\"sessionID\":\"b\",\"title\":\"pick\"}}");
	try expect(w, "form blocks", provider.faceState(), "blocked");
	try expect(w, "form text", provider.detail(), "pick");

	provider.handleEvent("{\"type\":\"form.cancelled\",\"data\":{\"sessionID\":\"b\"}}");
	try expect(w, "cancel clears block", provider.faceState(), "idle");

	provider.handleEvent("{\"type\":\"session.status\",\"data\":{\"sessionID\":\"c\",\"status\":{\"type\":\"busy\"}}}");
	try expect(w, "status busy is working", provider.faceState(), "working");

	provider.handleEvent("{\"type\":\"session.idle\",\"data\":{\"sessionID\":\"c\"}}");
	try expect(w, "idle event settles", provider.faceState(), "idle");

	provider.handleEvent("not json at all");
	try expect(w, "garbage keeps state", provider.faceState(), "idle");
}

fn live(io: Io, w: *std.Io.Writer) !void {
	const state = fetch(io) orelse {
		try w.writeAll("  daemon down, skipped\n");
		return;
	};

	const open = json.field(state, "opencode") orelse {
		try fail(w, "opencode section missing", "");
		return;
	};

	const face = json.textAt(open, "state");
	const allowed = std.mem.eql(u8, face, "idle") or std.mem.eql(u8, face, "working") or
		std.mem.eql(u8, face, "blocked") or std.mem.eql(u8, face, "error");

	if (allowed) {
		try pass(w, "face state is known");
	} else {
		try fail(w, "face state is known", face);
	}

	const blocked = json.textAt(open, "detail");
	if (std.mem.eql(u8, face, "blocked")) {
		if (blocked.len > 0) try pass(w, "blocked has a reason") else try fail(w, "blocked has a reason", "");
	}

	var seen = std.StringHashMap(void).init(gpa);
	defer seen.deinit();

	var duplicate = false;
	for (json.listAt(open, "sessions")) |entry| {
		const id = json.textAt(entry, "id");
		if (seen.contains(id)) duplicate = true;
		seen.put(id, {}) catch {};
	}

	if (duplicate) try fail(w, "session ids are unique", "") else try pass(w, "session ids are unique");

	var bad_percent = false;
	if (json.field(open, "plan")) |plan| {
		for (json.listAt(plan, "limits")) |limit| {
			const percent = json.numberAt(limit, "percent");
			if (percent < 0 or percent > 100) bad_percent = true;
		}
	}

	if (bad_percent) try fail(w, "limit percentages in range", "") else try pass(w, "limit percentages in range");

	var undescribed = false;
	if (json.field(state, "weather")) |weather| {
		for (json.listAt(weather, "slots")) |slot| {
			if (json.textAt(slot, "temp").len == 0) continue;
			if (json.textAt(slot, "text").len == 0 or json.textAt(slot, "glyph").len == 0) undescribed = true;

			for (json.listAt(slot, "days")) |day| {
				if (json.textAt(day, "text").len == 0 or json.textAt(day, "glyph").len == 0) undescribed = true;
			}
		}
	}

	if (undescribed) try fail(w, "weather rows carry text and glyph", "") else try pass(w, "weather rows carry text and glyph");
}

fn fetch(io: Io) ?json.Value {
	const path = proc.socketPath(io, gpa) catch return null;
	var buffer: [1048576]u8 = undefined;
	var connection = sock.Connection.connect(path, &buffer) catch return null;
	defer connection.close();

	connection.writeLine(sock.sync) catch return null;

	const line = connection.readLine() catch return null;
	const body = line orelse return null;

	const parsed = json.parse(gpa, body) catch return null;
	return parsed.value;
}

fn expect(w: *std.Io.Writer, name: []const u8, got: []const u8, want: []const u8) !void {
	if (std.mem.eql(u8, got, want)) return pass(w, name);
	return fail(w, name, got);
}

fn pass(w: *std.Io.Writer, name: []const u8) !void {
	try w.print("  ok    {s}\n", .{name});
}

fn fail(w: *std.Io.Writer, name: []const u8, got: []const u8) !void {
	failures += 1;
	try w.print("  FAIL  {s} (got {s})\n", .{ name, got });
}
