const std = @import("std");
const json = @import("primitives/json.zig");
const proc = @import("primitives/proc.zig");
const sock = @import("primitives/sock.zig");
const benchmod = @import("bench.zig");
const bench_widgets = @import("bench_widgets.zig");
const paritymod = @import("parity.zig");
const mcpmod = @import("mcp.zig");
const configmod = @import("primitives/config.zig");
const config_provider = @import("providers/config.zig");

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

pub fn doctor(io: Io, args: []const []const u8) !void {
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

	try reportConfig(io, w, arena.allocator(), parsed.value, args);

	try w.flush();
}

fn reportConfig(io: Io, w: *std.Io.Writer, allocator: Allocator, snapshot: json.Value, args: []const []const u8) !void {
	var consumed: std.ArrayListUnmanaged([]const u8) = .empty;

	if (json.field(snapshot, "config")) |section| {
		for (json.listAt(section, "used")) |item| try consumed.append(allocator, json.text(item));
	}

	const shell = config_provider.shellKeys(io, allocator) catch &.{};
	try consumed.appendSlice(allocator, shell);

	const file = if (args.len > 2) args[2] else try std.fmt.allocPrint(allocator, "{s}/.config/quickshell/config.toml", .{proc.home(io, allocator)});

	const cfg = configmod.Config.loadPath(io, allocator, file) catch {
		try w.writeAll("config    unreadable\n");
		return;
	};
	defer cfg.deinit();

	const unknown = try cfg.unknown(allocator, consumed.items);

	if (unknown.len == 0) {
		try w.writeAll("config    ok\n");
		return;
	}

	try w.print("config    {d} unknown:", .{unknown.len});
	for (unknown) |name| try w.print(" {s}", .{name});
	try w.writeAll("\n");
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

pub fn print(io: Io, comptime message: []const u8) void {
	var buffer: [1024]u8 = undefined;
	var writer = std.Io.File.stdout().writer(io, &buffer);
	writer.interface.writeAll(message) catch {};
	writer.interface.flush() catch {};
}

test "cli module compiles" {
	try std.testing.expect(true);
}
