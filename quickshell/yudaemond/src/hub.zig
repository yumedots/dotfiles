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
	last_body: ?[]u8 = null,

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
		self.publish_mutex.lockUncancelable(self.io);
		defer self.publish_mutex.unlock(self.io);

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
		self.last_publish_ms = fmt.nowMs(self.io);

		const body = self.snapshot(self.allocator) catch return;
		defer self.allocator.free(body);

		// A provider tick that worked out to the same state as the last one
		// has nothing to say. The header carries a fresh revision and stamp
		// every time, so only the providers are compared. Revisions skip the
		// passes that are dropped.
		const current = providerBody(body);

		if (self.last_body) |previous| {
			if (std.mem.eql(u8, providerBody(previous), current)) return;
		}

		const kept = self.allocator.dupe(u8, body) catch null;

		if (kept) |copy| {
			if (self.last_body) |previous| self.allocator.free(previous);
			self.last_body = copy;
		}

		if (self.ipc) |server| server.broadcast(body);
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

/// The providers of a snapshot, without the revision and stamp that lead it.
/// Those two move on every render, so a comparison that kept them would never
/// find two snapshots alike.
fn providerBody(body: []const u8) []const u8 {
	const marker = "\"ts\":";
	const at = std.mem.indexOf(u8, body, marker) orelse return body;

	var i = at + marker.len;
	while (i < body.len and std.ascii.isDigit(body[i])) i += 1;

	return body[i..];
}

test "providerBody drops the header and keeps the providers" {
	const a = "{\"rev\":7,\"ts\":1700000000000,\"system\":{\"cpu\":1}}";
	const b = "{\"rev\":8,\"ts\":1700000000999,\"system\":{\"cpu\":1}}";
	const c = "{\"rev\":9,\"ts\":1700000001000,\"system\":{\"cpu\":2}}";

	try std.testing.expectEqualStrings(",\"system\":{\"cpu\":1}}", providerBody(a));
	try std.testing.expect(std.mem.eql(u8, providerBody(a), providerBody(b)));
	try std.testing.expect(!std.mem.eql(u8, providerBody(a), providerBody(c)));
}

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
