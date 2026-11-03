const std = @import("std");
const proc = @import("proc.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn request(io: Io, allocator: Allocator, command: []const u8) ![]u8 {
	const signature = proc.env(io, allocator, "HYPRLAND_INSTANCE_SIGNATURE") orelse return error.NoHyprland;

	return requestSigned(io, allocator, signature, command);
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
	const signature = proc.env(io, allocator, "HYPRLAND_INSTANCE_SIGNATURE") orelse return null;

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
