const std = @import("std");
const ipc = @import("ipc.zig");
const fmt = @import("primitives/fmt.zig");

pub const Io = std.Io;
pub const Allocator = std.mem.Allocator;
pub const Writer = std.Io.Writer;

pub const Provider = struct {
	key: []const u8,
	ctx: *anyopaque,
	render: *const fn (ctx: *anyopaque, writer: *Writer) anyerror!void,
};

pub const Hub = struct {
	allocator: Allocator,
	io: Io,
	providers: std.ArrayList(Provider) = .empty,
	revision: std.atomic.Value(u64) = .init(0),
	ipc: ?*ipc.Ipc = null,

	pub fn add(self: *Hub, provider: Provider) !void {
		try self.providers.append(self.allocator, provider);
	}

	pub fn snapshot(self: *Hub, allocator: Allocator) ![]u8 {
		var out: Writer.Allocating = .init(allocator);
		errdefer out.deinit();

		const rev = self.revision.load(.monotonic);
		try out.writer.print("{{\"rev\":{d},\"ts\":{d}", .{ rev, fmt.nowMs(self.io) });

		for (self.providers.items) |provider| {
			try out.writer.print(",\"{s}\":", .{provider.key});
			provider.render(provider.ctx, &out.writer) catch try out.writer.writeAll("{}");
		}

		try out.writer.writeAll("}");
		return out.toOwnedSlice();
	}

	pub fn syncSnapshot(self: *Hub, allocator: Allocator) ![]u8 {
		_ = self.revision.fetchAdd(1, .monotonic);
		return self.snapshot(allocator);
	}

	pub fn publish(self: *Hub) void {
		_ = self.revision.fetchAdd(1, .monotonic);

		const t0 = fmt.nowMs(self.io);
		const body = self.snapshot(self.allocator) catch return;
		defer self.allocator.free(body);
		const t1 = fmt.nowMs(self.io);

		if (self.ipc) |server| server.broadcast(body);
		const t2 = fmt.nowMs(self.io);
		if (t2 - t0 > 100) std.debug.print("DBG publish snapshot={d} broadcast={d} rev={d}\n", .{ t1 - t0, t2 - t1, self.revision.load(.monotonic) });
	}

	pub fn publishGaze(self: *Hub, x: f64, y: f64) void {
		const server = self.ipc orelse return;
		server.broadcastGaze(x, y);
	}

	pub fn gazeWanted(self: *Hub) bool {
		const server = self.ipc orelse return false;
		return server.gazeSubscribers() > 0;
	}
};
