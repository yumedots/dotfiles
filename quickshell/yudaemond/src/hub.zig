const std = @import("std");
const ipc = @import("ipc.zig");
const fmt = @import("primitives/fmt.zig");
const sleep = @import("primitives/sleep.zig");

/// Snapshots are full renders, so a burst of provider events only needs one of them: the last
/// one wins. Everything queued behind a render collapses into the next pass.
const publish_gap_ms: i64 = 16;

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
	publish_mutex: std.Io.Mutex = .init,
	dirty: std.atomic.Value(bool) = .init(false),
	last_publish_ms: i64 = 0,

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
		self.dirty.store(true, .release);

		self.publish_mutex.lockUncancelable(self.io);
		defer self.publish_mutex.unlock(self.io);

		while (self.dirty.swap(false, .acq_rel)) {
			const now = fmt.nowMs(self.io);

			if (self.last_publish_ms > 0 and now - self.last_publish_ms < publish_gap_ms) {
				sleep.ms(@intCast(publish_gap_ms - (now - self.last_publish_ms)));
			}

			self.publishOnce();
		}
	}

	fn publishOnce(self: *Hub) void {
		_ = self.revision.fetchAdd(1, .monotonic);

		const t0 = fmt.nowMs(self.io);
		self.last_publish_ms = t0;

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

const Probe = struct {
	mutex: std.Io.Mutex = .init,
	stamps: [64]i64 = @splat(0),
	count: usize = 0,

	fn render(self: *Probe, writer: *Writer) !void {
		self.mutex.lockUncancelable(std.testing.io);
		defer self.mutex.unlock(std.testing.io);

		if (self.count < self.stamps.len) {
			self.stamps[self.count] = fmt.nowMs(std.testing.io);
			self.count += 1;
		}

		try writer.writeAll("{}");
	}
};

fn probeThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
	const probe: *Probe = @ptrCast(@alignCast(ctx));
	try probe.render(writer);
}

test "a burst of publishes never renders faster than the gap" {
	const io = std.testing.io;
	var hub: Hub = .{ .allocator = std.heap.smp_allocator, .io = io };

	var probe: Probe = .{};
	try hub.add(.{ .key = "t", .ctx = &probe, .render = probeThunk });

	const burst = struct {
		fn run(target: *Hub) void {
			for (0..8) |_| target.publish();
		}
	};

	var threads: [4]std.Thread = undefined;
	for (&threads) |*thread| thread.* = try std.Thread.spawn(.{}, burst.run, .{&hub});
	for (&threads) |thread| thread.join();

	probe.mutex.lockUncancelable(io);
	defer probe.mutex.unlock(io);

	try std.testing.expect(probe.count > 0);
	try std.testing.expect(probe.count <= 32);

	var index: usize = 1;
	while (index < probe.count) : (index += 1) {
		try std.testing.expect(probe.stamps[index] - probe.stamps[index - 1] >= publish_gap_ms - 1);
	}
}
