const std = @import("std");
const linux = std.os.linux;

pub const Allocator = std.mem.Allocator;

pub fn failed(result: usize) bool {
	return @as(isize, @bitCast(result)) < 0;
}

pub const Server = struct {
	fd: i32,
	path: []const u8,

	pub fn init(path: []const u8) !Server {
		const result = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0);
		if (failed(result)) return error.SocketFailed;

		const fd: i32 = @intCast(result);

		var address: linux.sockaddr.un = .{ .path = undefined };
		@memset(&address.path, 0);

		if (path.len >= address.path.len) return error.PathTooLong;
		@memcpy(address.path[0..path.len], path);

		const terminated = try std.heap.smp_allocator.allocSentinel(u8, path.len, 0);
		@memcpy(terminated, path);
		defer std.heap.smp_allocator.free(terminated);
		_ = linux.unlink(terminated);

		if (failed(linux.bind(fd, @ptrCast(&address), @sizeOf(linux.sockaddr.un)))) return error.BindFailed;
		if (failed(linux.listen(fd, 128))) return error.ListenFailed;

		return .{ .fd = fd, .path = path };
	}

	pub fn accept(self: Server) !i32 {
		const result = linux.accept4(self.fd, null, null, linux.SOCK.CLOEXEC);
		if (failed(result)) return error.AcceptFailed;

		return @intCast(result);
	}

	pub fn close(self: Server) void {
		_ = linux.close(self.fd);
	}
};

pub const Connection = struct {
	fd: i32,
	buffer: []u8,
	start: usize = 0,
	length: usize = 0,

	pub fn connect(path: []const u8, buffer: []u8) !Connection {
		const result = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0);
		if (failed(result)) return error.SocketFailed;

		const fd: i32 = @intCast(result);

		var address: linux.sockaddr.un = .{ .path = undefined };
		@memset(&address.path, 0);

		if (path.len >= address.path.len) return error.PathTooLong;
		@memcpy(address.path[0..path.len], path);

		if (failed(linux.connect(fd, @ptrCast(&address), @sizeOf(linux.sockaddr.un)))) return error.ConnectFailed;

		return .{ .fd = fd, .buffer = buffer };
	}

	pub fn close(self: Connection) void {
		_ = linux.close(self.fd);
	}

	pub fn writeLine(self: *Connection, line: []const u8) !void {
		try writeAll(self.fd, line);
		try writeAll(self.fd, "\n");
	}

	pub fn readLine(self: *Connection) !?[]const u8 {
		while (true) {
			if (std.mem.indexOfScalar(u8, self.buffer[self.start..self.length], '\n')) |offset| {
				const cut = self.start + offset;
				const line = self.buffer[self.start..cut];
				self.start = cut + 1;

				return line;
			}

			if (self.start > 0) {
				const remaining = self.length - self.start;
				std.mem.copyForwards(u8, self.buffer[0..remaining], self.buffer[self.start..self.length]);
				self.length = remaining;
				self.start = 0;
				continue;
			}

			if (self.length == self.buffer.len) return error.LineTooLong;

			const count = linux.read(self.fd, self.buffer[self.length..].ptr, self.buffer.len - self.length);
			if (failed(count)) return error.ReadFailed;
			if (count == 0) return null;

			self.length += count;
		}
	}
};

pub fn writeAll(fd: i32, bytes: []const u8) !void {
	var written: usize = 0;

	while (written < bytes.len) {
		const count = linux.write(fd, bytes[written..].ptr, bytes.len - written);
		if (failed(count)) return error.WriteFailed;
		if (count == 0) return error.WriteFailed;

		written += count;
	}
}

test "line framing keeps the remainder" {
	var buffer: [64]u8 = undefined;
	var connection: Connection = .{ .fd = -1, .buffer = &buffer };
	@memcpy(connection.buffer[0..6], "a\nbb\nc");
	connection.length = 6;

	try std.testing.expectEqualStrings("a", (try connection.readLine()).?);
	try std.testing.expectEqualStrings("bb", (try connection.readLine()).?);
	try std.testing.expectEqualStrings("c", connection.buffer[connection.start..connection.length]);
}
