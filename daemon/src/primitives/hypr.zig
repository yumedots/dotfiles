const std = @import("std");
const proc = @import("proc.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn request(io: Io, allocator: Allocator, command: []const u8) ![]u8 {
	const signature = try findSignature(io, allocator);

	return requestSigned(io, allocator, signature, command);
}

pub fn findSignature(io: Io, allocator: Allocator) ![]const u8 {
	if (proc.env(io, allocator, "HYPRLAND_INSTANCE_SIGNATURE")) |value| {
		if (socketLive(io, allocator, value)) return value;
	}

	const runtime = proc.runtimeDir(io, allocator);
	const dir_path = try std.fmt.allocPrint(allocator, "{s}/hypr", .{runtime});
	defer allocator.free(dir_path);

	return newestSignature(io, allocator, dir_path);
}

fn socketLive(io: Io, allocator: Allocator, signature: []const u8) bool {
	const runtime = proc.runtimeDir(io, allocator);
	const path = std.fmt.allocPrint(allocator, "{s}/hypr/{s}/.socket.sock", .{ runtime, signature }) catch return false;
	defer allocator.free(path);

	return connects(io, path);
}

fn connects(io: Io, path: []const u8) bool {
	const address = std.Io.net.UnixAddress.init(path) catch return false;
	const stream = address.connect(io) catch return false;
	stream.close(io);

	return true;
}

fn newestSignature(io: Io, allocator: Allocator, base: []const u8) ![]const u8 {
	var dir = std.Io.Dir.cwd().openDir(io, base, .{ .iterate = true }) catch return error.NoHyprland;
	defer dir.close(io);

	var iterator = dir.iterate();
	var live: ?[]u8 = null;
	var live_time: i96 = std.math.minInt(i96);
	var any: ?[]u8 = null;
	var any_time: i96 = std.math.minInt(i96);
	errdefer {
		if (live) |value| allocator.free(value);
		if (any) |value| allocator.free(value);
	}

	while (iterator.next(io) catch null) |entry| {
		if (entry.kind != .directory) continue;

		const socket = try std.fmt.allocPrint(allocator, "{s}/{s}/.socket.sock", .{ base, entry.name });
		const stat = std.Io.Dir.cwd().statFile(io, socket, .{}) catch {
			allocator.free(socket);
			continue;
		};
		const alive = connects(io, socket);
		allocator.free(socket);

		if (alive and stat.mtime.nanoseconds > live_time) {
			if (live) |value| allocator.free(value);
			live = try allocator.dupe(u8, entry.name);
			live_time = stat.mtime.nanoseconds;
		}

		if (any == null or stat.mtime.nanoseconds > any_time) {
			if (any) |value| allocator.free(value);
			any = try allocator.dupe(u8, entry.name);
			any_time = stat.mtime.nanoseconds;
		}
	}

	if (live) |value| {
		if (any) |other| allocator.free(other);
		return value;
	}

	return any orelse error.NoHyprland;
}

test "the newest live instance wins over a stale one" {
	const io = std.testing.io;

	var tmp = std.testing.tmpDir(.{});
	defer tmp.cleanup();

	const base = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/hypr", .{tmp.sub_path});
	defer std.testing.allocator.free(base);

	var live_server: ?std.Io.net.Server = null;
	defer if (live_server) |*server| server.deinit(io);

	for ([_][]const u8{ "stale", "live", "quiet" }, 0..) |name, at| {
		const dir_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/{s}", .{ base, name });
		defer std.testing.allocator.free(dir_path);
		try std.Io.Dir.cwd().createDirPath(io, dir_path);

		if (at == 2) continue;

		const socket = try std.fmt.allocPrint(std.testing.allocator, "{s}/.socket.sock", .{dir_path});
		defer std.testing.allocator.free(socket);

		if (at == 1) {
			const address = try std.Io.net.UnixAddress.init(socket);
			live_server = try address.listen(io, .{});
			continue;
		}

		var file = try std.Io.Dir.cwd().createFile(io, socket, .{});
		try file.setTimestamps(io, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = std.math.maxInt(i64) } } });
		file.close(io);
	}

	const picked = try newestSignature(io, std.testing.allocator, base);
	defer std.testing.allocator.free(picked);

	try std.testing.expectEqualStrings("live", picked);
}

pub fn requestSigned(io: Io, allocator: Allocator, signature: []const u8, command: []const u8) ![]u8 {
	const runtime = proc.runtimeDir(io, allocator);
	const path = try std.fmt.allocPrint(allocator, "{s}/hypr/{s}/.socket.sock", .{ runtime, signature });
	defer allocator.free(path);

	const address = try std.Io.net.UnixAddress.init(path);
	const stream = try address.connect(io);
	defer stream.close(io);

	var write_buffer: [256]u8 = undefined;
	var writer = std.Io.net.Stream.Writer.init(stream, io, &write_buffer);
	try writer.interface.writeAll(command);
	try writer.interface.flush();

	var read_buffer: [8192]u8 = undefined;
	var reader = std.Io.net.Stream.Reader.init(stream, io, &read_buffer);

	var out: std.ArrayList(u8) = .empty;
	errdefer out.deinit(allocator);

	var chunk: [8192]u8 = undefined;
	while (true) {
		const count = reader.interface.readSliceShort(&chunk) catch break;
		if (count == 0) break;
		if (out.items.len + count > 1024 * 1024) break;
		try out.appendSlice(allocator, chunk[0..count]);
	}

	return out.toOwnedSlice(allocator);
}

pub fn monitorPath(io: Io, allocator: Allocator) ?[]u8 {
	const signature = findSignature(io, allocator) catch return null;
	defer allocator.free(signature);

	const runtime = proc.runtimeDir(io, allocator);
	return std.fmt.allocPrint(allocator, "{s}/hypr/{s}/.socket2.sock", .{ runtime, signature }) catch null;
}

pub fn usingLua(io: Io, allocator: Allocator) bool {
	const override = proc.env(io, allocator, "XDG_CONFIG_HOME");

	const base = override orelse
		(std.fmt.allocPrint(allocator, "{s}/.config", .{proc.home(io, allocator)}) catch return false);
	defer if (override == null) allocator.free(base);

	const path = std.fmt.allocPrint(allocator, "{s}/hypr/hyprland.lua", .{base}) catch return false;
	defer allocator.free(path);

	return proc.exists(io, path);
}
