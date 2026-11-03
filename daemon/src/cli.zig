const std = @import("std");
const json = @import("primitives/json.zig");
const proc = @import("primitives/proc.zig");
const sock = @import("primitives/sock.zig");
const benchmod = @import("bench.zig");
const bench_widgets = @import("bench_widgets.zig");
const paritymod = @import("parity.zig");
const mcpmod = @import("mcp.zig");
const sleep = @import("primitives/sleep.zig");

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

	try writer.writeAll("{\"cmd\":{");
	try std.json.Stringify.encodeJsonString(target, .{}, writer);
	try writer.writeAll(":{");
	try std.json.Stringify.encodeJsonString(method, .{}, writer);
	try writer.writeAll(":");

	if (rest.len == 0) {
		try writer.writeAll("true");
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

	try writer.writeAll("}}}");

	const path = try proc.socketPath(io, allocator);

	var read_buffer: [1048576]u8 = undefined;
	var connection = sock.Connection.connect(path, &read_buffer) catch {
		if (quiet) return;
		std.debug.print("yudaemond is not running\n", .{});
		std.process.exit(2);
	};
	defer connection.close();

	try connection.writeLine(out.written());
	try connection.writeLine(sock.sync);
	_ = connection.readLine() catch {};
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
