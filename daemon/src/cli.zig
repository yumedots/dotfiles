const std = @import("std");
const json = @import("primitives/json.zig");
const proc = @import("primitives/proc.zig");
const sock = @import("primitives/sock.zig");
const benchmod = @import("bench.zig");
const bench_widgets = @import("bench_widgets.zig");
const paritymod = @import("parity.zig");
const mcpmod = @import("mcp.zig");
const sleep = @import("primitives/sleep.zig");
const environ = @import("primitives/environ.zig");
const exec = @import("primitives/exec.zig");
const hypr = @import("primitives/hypr.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn state(io: Io, args: []const []const u8) !void {
	const body = try fetch(io);
	defer std.heap.smp_allocator.free(body);

	var buffer: [8192]u8 = undefined;
	var writer = std.Io.File.stdout().writer(io, &buffer);
	try writer.interface.writeAll(body);
	try writer.interface.writeAll("\n");
	try writer.interface.flush();

	_ = args;
}

pub fn fetch(io: Io) ![]u8 {
	const path = try proc.socketPath(io, std.heap.smp_allocator);
	defer std.heap.smp_allocator.free(path);

	var read_buffer: [1048576]u8 = undefined;
	var connection = sock.Connection.connect(path, &read_buffer) catch {
		std.debug.print("yudaemond is not running\n", .{});
		std.process.exit(2);
	};
	defer connection.close();

	try connection.writeLine(sock.sync);

	const message = try connection.readLine() orelse {
		std.debug.print("yudaemond sent no state\n", .{});
		std.process.exit(2);
	};

	return std.heap.smp_allocator.dupe(u8, message);
}

pub fn logout(io: Io) !void {
	const path = try proc.socketPath(io, std.heap.smp_allocator);
	defer std.heap.smp_allocator.free(path);

	var read_buffer: [4096]u8 = undefined;
	var connection = sock.Connection.connect(path, &read_buffer) catch {
		std.debug.print("yudaemond is not running\n", .{});
		std.process.exit(2);
	};
	defer connection.close();

	try connection.writeLine("{\"cmd\":{\"system\":{\"logout\":true}}}");
}

pub fn doctor(io: Io) !void {
	const body = try fetch(io);
	defer std.heap.smp_allocator.free(body);

	var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
	defer arena.deinit();

	const parsed = json.parse(arena.allocator(), body) catch {
		std.debug.print("state unreadable\n", .{});
		std.process.exit(2);
	};

	var buffer: [8192]u8 = undefined;
	var writer = std.Io.File.stdout().writer(io, &buffer);
	const w = &writer.interface;

	const open = json.field(parsed.value, "opencode") orelse null;
	if (open) |provider| {
		const connected = json.flag(provider, "connected");
		const state_text = json.textAt(provider, "state");
		const usage = json.textAt(provider, "usageError");

		try w.print("opencode  {s}  state={s}{s}\n", .{
			if (connected) "up  " else "down",
			state_text,
			if (usage.len > 0) usage else "",
		});
	} else {
		try w.writeAll("opencode  missing\n");
	}

	if (json.field(parsed.value, "codex")) |provider| {
		try w.print("codex     {s}\n", .{if (json.flag(provider, "signedIn")) "up  " else "down"});
	}

	if (json.field(parsed.value, "weather")) |provider| {
		try w.print("weather   {s}\n", .{if (json.integer(json.field(provider, "fetched")) > 0) "up  " else "down"});
	}

	if (json.field(parsed.value, "github")) |provider| {
		try w.print("github    {s}\n", .{if (json.textAt(provider, "login").len > 0) "up  " else "down"});
	}

	if (json.field(parsed.value, "cursor")) |provider| {
		try w.print("cursor    {s}\n", .{if (json.flag(provider, "valid")) "up  " else "down"});
	}

	try w.flush();
}

pub fn bench(io: Io, args: []const []const u8) !void {
	if (args.len > 2 and std.mem.eql(u8, args[2], "widgets")) return bench_widgets.run(io, args);

	return benchmod.run(io, args);
}

pub fn parity(io: Io, args: []const []const u8) !void {
	return paritymod.run(io, args);
}

pub fn mcp(io: Io, args: []const []const u8) !void {
	return mcpmod.run(io, args);
}

pub fn call(io: Io, args: []const []const u8) !void {
	var quiet = false;
	var index: usize = 2;

	while (index < args.len and args[index].len > 0 and args[index][0] == '-') {
		if (std.mem.eql(u8, args[index], "-q")) quiet = true;
		index += 1;
	}

	if (index + 1 >= args.len) {
		std.debug.print("usage: yudae call [-q] <target> <method> [args...]\n", .{});
		std.process.exit(2);
	}

	const target = args[index];
	const method = args[index + 1];
	const rest = args[index + 2 ..];

	var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
	defer arena.deinit();
	const allocator = arena.allocator();

	var out: std.Io.Writer.Allocating = .init(allocator);
	const writer = &out.writer;

	try writer.writeAll("{\"call\":{\"target\":");
	try std.json.Stringify.encodeJsonString(target, .{}, writer);
	try writer.writeAll(",\"method\":");
	try std.json.Stringify.encodeJsonString(method, .{}, writer);
	try writer.writeAll(",\"args\":");

	if (rest.len == 0) {
		try writer.writeAll("{}");
	} else if (rest.len == 1) {
		try writeArg(allocator, writer, rest[0]);
	} else {
		try writer.writeAll("[");

		for (rest, 0..) |arg, position| {
			if (position > 0) try writer.writeAll(",");
			try writeArg(allocator, writer, arg);
		}

		try writer.writeAll("]");
	}

	try writer.writeAll("}}");

	const result = roundTrip(io, allocator, out.written(), quiet) catch {
		if (quiet) return;
		std.process.exit(1);
	};

	if (!quiet and result.len > 0 and !std.mem.eql(u8, result, "{}")) printResult(io, result);
}

pub fn ui(io: Io, args: []const []const u8) !void {
	if (args.len < 3 or !std.mem.eql(u8, args[2], "tree")) {
		std.debug.print("usage: yudae ui tree\n", .{});
		std.process.exit(2);
	}

	var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
	defer arena.deinit();

	const result = roundTrip(io, arena.allocator(), "{\"call\":{\"target\":\"ui\",\"method\":\"tree\",\"args\":{}}}", false) catch std.process.exit(1);
	printResult(io, result);
}

pub fn virtualMachines(io: Io, args: []const []const u8) !void {
	if (args.len < 3) {
		std.debug.print("usage: yudae vm <create|list|start|stop|exec|screenshot|key|type|click|move|wait|sleep|wake|destroy|snapshot|restore|fork|state|view|scenario> [args...]\n", .{});
		std.process.exit(2);
	}

	const method = args[2];
	const rest = args[3..];

	if (std.mem.eql(u8, method, "view")) {
		if (rest.len == 0) {
			std.debug.print("usage: yudae vm view <name>\n", .{});
			std.process.exit(2);
		}

		var view_arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
		defer view_arena.deinit();
		const view_allocator = view_arena.allocator();

		const start = try std.fmt.allocPrint(view_allocator, "{{\"call\":{{\"target\":\"vms\",\"method\":\"start\",\"args\":{{\"name\":\"{s}\"}}}}}}", .{rest[0]});
		_ = roundTrip(io, view_allocator, start, true) catch {};

		const message = try std.fmt.allocPrint(view_allocator, "{{\"call\":{{\"target\":\"vms\",\"method\":\"view\",\"args\":{{\"name\":\"{s}\"}}}}}}", .{rest[0]});
		const result = roundTrip(io, view_allocator, message, false) catch std.process.exit(1);

		focusVmWindow(io, view_allocator, rest[0]);

		printResult(io, result);
		return;
	}

	var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
	defer arena.deinit();
	const allocator = arena.allocator();

	var out: std.Io.Writer.Allocating = .init(allocator);
	const writer = &out.writer;

	try writer.writeAll("{\"call\":{\"target\":\"vms\",\"method\":");
	try std.json.Stringify.encodeJsonString(method, .{}, writer);
	try writer.writeAll(",\"args\":{");

	var wrote = false;
	var index: usize = 0;
	var name: []const u8 = "";
	var positional: std.ArrayList([]const u8) = .empty;

	while (index < rest.len) : (index += 1) {
		const arg = rest[index];

		if (std.mem.eql(u8, arg, "--cores") and index + 1 < rest.len) {
			index += 1;
			try writeRawField(writer, &wrote, "cores", rest[index]);
		} else if (std.mem.eql(u8, arg, "--mem") and index + 1 < rest.len) {
			index += 1;
			try writeRawField(writer, &wrote, "mem", rest[index]);
		} else if (std.mem.eql(u8, arg, "--from") and index + 1 < rest.len) {
			index += 1;
			try writeField(allocator, writer, &wrote, "from", rest[index]);
		} else if (std.mem.eql(u8, arg, "--agent") and index + 1 < rest.len) {
			index += 1;
			try writeField(allocator, writer, &wrote, "agent", rest[index]);
		} else if (std.mem.eql(u8, arg, "--tag") and index + 1 < rest.len) {
			index += 1;
			try writeField(allocator, writer, &wrote, "tag", rest[index]);
		} else if (std.mem.eql(u8, arg, "--until") and index + 1 < rest.len) {
			index += 1;
			try writeField(allocator, writer, &wrote, "until", rest[index]);
		} else if (std.mem.eql(u8, arg, "--timeout") and index + 1 < rest.len) {
			index += 1;
			try writeField(allocator, writer, &wrote, "timeout", rest[index]);
		} else if (std.mem.eql(u8, arg, "--gl")) {
			try writeRawField(writer, &wrote, "gl", "true");
		} else if (std.mem.eql(u8, arg, "--human")) {
			try writeRawField(writer, &wrote, "human", "true");
		} else if (name.len == 0) {
			name = arg;
		} else {
			try positional.append(allocator, arg);
		}
	}

	if (name.len > 0) try writeField(allocator, writer, &wrote, "name", name);

	if (std.mem.eql(u8, method, "exec")) {
		try writeField(allocator, writer, &wrote, "cmd", try std.mem.join(allocator, " ", positional.items));
	} else if (std.mem.eql(u8, method, "type")) {
		try writeField(allocator, writer, &wrote, "text", try std.mem.join(allocator, " ", positional.items));
	} else if (std.mem.eql(u8, method, "key")) {
		try writeArrayField(allocator, writer, &wrote, "keys", positional.items);
	} else if (std.mem.eql(u8, method, "click") or std.mem.eql(u8, method, "move")) {
		if (positional.items.len >= 1) try writeRawField(writer, &wrote, "x", positional.items[0]);
		if (positional.items.len >= 2) try writeRawField(writer, &wrote, "y", positional.items[1]);
	} else if (std.mem.eql(u8, method, "run_scenario")) {
		if (positional.items.len >= 1) {
			try writeField(allocator, writer, &wrote, "scenario", positional.items[0]);
		} else if (name.len > 0) {
			try writeField(allocator, writer, &wrote, "scenario", name);
		}
	} else if (std.mem.eql(u8, method, "screenshot")) {
		if (positional.items.len >= 1) try writeField(allocator, writer, &wrote, "path", positional.items[0]);
	} else if (std.mem.eql(u8, method, "snapshot") or std.mem.eql(u8, method, "restore")) {
		if (positional.items.len >= 1) try writeField(allocator, writer, &wrote, "tag", positional.items[0]);
	} else if (std.mem.eql(u8, method, "fork")) {
		if (positional.items.len >= 1) try writeField(allocator, writer, &wrote, "from", positional.items[0]);
	}

	try writer.writeAll("}}}");

	const result = roundTrip(io, allocator, out.written(), false) catch std.process.exit(1);
	printResult(io, result);

	if (std.mem.eql(u8, method, "run_scenario") and std.mem.indexOf(u8, result, "\"ok\":false") != null) std.process.exit(1);
}

fn writeField(allocator: Allocator, writer: *std.Io.Writer, wrote: *bool, key: []const u8, value: []const u8) !void {
	if (value.len == 0) return;
	if (wrote.*) try writer.writeAll(",");
	wrote.* = true;
	try std.json.Stringify.encodeJsonString(key, .{}, writer);
	try writer.writeAll(":");
	try std.json.Stringify.encodeJsonString(value, .{}, writer);
	_ = allocator;
}

fn writeRawField(writer: *std.Io.Writer, wrote: *bool, key: []const u8, value: []const u8) !void {
	if (wrote.*) try writer.writeAll(",");
	wrote.* = true;
	try std.json.Stringify.encodeJsonString(key, .{}, writer);
	try writer.writeAll(":");
	try writer.writeAll(value);
}

fn writeArrayField(allocator: Allocator, writer: *std.Io.Writer, wrote: *bool, key: []const u8, values: []const []const u8) !void {
	if (wrote.*) try writer.writeAll(",");
	wrote.* = true;
	try std.json.Stringify.encodeJsonString(key, .{}, writer);
	try writer.writeAll(":[");

	for (values, 0..) |value, index| {
		if (index > 0) try writer.writeAll(",");
		try std.json.Stringify.encodeJsonString(value, .{}, writer);
	}

	try writer.writeAll("]");
	_ = allocator;
}

fn roundTrip(io: Io, allocator: Allocator, message: []const u8, quiet: bool) ![]u8 {
	const path = try proc.socketPath(io, allocator);

	var read_buffer: [1024 * 1024]u8 = undefined;
	var connection = sock.Connection.connect(path, &read_buffer) catch {
		if (quiet) return "";
		std.debug.print("yudaemond is not running\n", .{});
		return error.NotRunning;
	};
	defer connection.close();

	try connection.writeLine(message);

	var attempts: usize = 0;
	while (attempts < 20) : (attempts += 1) {
		const line = try connection.readLine() orelse {
			std.debug.print("yudaemond sent no reply\n", .{});
			return error.NoReply;
		};

		const parsed = try json.parse(allocator, line);

		if (json.field(parsed.value, "ok") == null) continue;

		if (!json.flag(parsed.value, "ok")) {
			std.debug.print("yudae: {s}\n", .{json.textAt(parsed.value, "error")});
			return error.CallFailed;
		}

		const result = json.field(parsed.value, "result") orelse json.Value{ .null = {} };

		switch (result) {
			.null => return allocator.dupe(u8, "{}"),
			else => {},
		}

		var out: std.Io.Writer.Allocating = .init(allocator);
		try out.writer.print("{f}", .{std.json.fmt(result, .{})});
		return out.written();
	}

	return error.NoReply;
}

fn printResult(io: Io, body: []const u8) void {
	var buffer: [8192]u8 = undefined;
	var writer = std.Io.File.stdout().writer(io, &buffer);
	writer.interface.writeAll(body) catch {};
	writer.interface.writeAll("\n") catch {};
	writer.interface.flush() catch {};
}

fn writeArg(allocator: Allocator, writer: *std.Io.Writer, arg: []const u8) !void {
	if (json.parse(allocator, arg)) |_| {
		try writer.writeAll(arg);
	} else |_| {
		try std.json.Stringify.encodeJsonString(arg, .{}, writer);
	}
}

pub fn spawnCheck(io: Io, args: []const []const u8) !void {
	var seconds: u64 = 5;
	var index: usize = 2;

	while (index < args.len) : (index += 1) {
		if (std.mem.eql(u8, args[index], "--seconds") and index + 1 < args.len) {
			index += 1;
			seconds = std.fmt.parseInt(u64, args[index], 10) catch 5;
		}
	}

	const before = try spawns(io);
	sleep.ms(seconds * 1000);
	const after = try spawns(io);

	if (before != after) {
		std.debug.print("idle spawns {d} -> {d} over {d}s\n", .{ before, after, seconds });
		std.process.exit(1);
	}

	var buffer: [8192]u8 = undefined;
	var writer = std.Io.File.stdout().writer(io, &buffer);
	try writer.interface.print("idle spawns {d} -> {d} over {d}s\n", .{ before, after, seconds });
	try writer.interface.flush();
}

fn spawns(io: Io) !u64 {
	const body = try fetch(io);
	defer std.heap.smp_allocator.free(body);

	var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
	defer arena.deinit();

	const parsed = json.parse(arena.allocator(), body) catch return error.StateUnreadable;
	const value = json.integer(json.deep(parsed.value, &.{ "daemon", "spawns" }));

	return @intCast(@max(value, 0));
}

pub fn print(io: Io, comptime message: []const u8) void {
	var buffer: [1024]u8 = undefined;
	var writer = std.Io.File.stdout().writer(io, &buffer);
	writer.interface.writeAll(message) catch {};
	writer.interface.flush() catch {};
}

test "cli module compiles" {
	try std.testing.expect(true);
}

fn focusVmWindow(io: Io, allocator: Allocator, name: []const u8) void {
	const body = hypr.request(io, allocator, "j/clients") catch return;
	defer allocator.free(body);

	const parsed = json.parse(allocator, body) catch return;
	const clients = if (parsed.value == .array) parsed.value.array.items else return;

	const needle = std.fmt.allocPrint(allocator, "(yudae-{s})", .{name}) catch return;

	for (clients) |client| {
		if (std.mem.indexOf(u8, json.textAt(client, "title"), needle) == null) continue;

		const workspace = json.field(client, "workspace") orelse return;
		const id = json.integer(json.field(workspace, "id"));

		const command = std.fmt.allocPrint(allocator, "dispatch hl.dsp.focus({{workspace={d}}})", .{id}) catch return;
		const reply = hypr.request(io, allocator, command) catch return;
		allocator.free(reply);
		return;
	}
}
