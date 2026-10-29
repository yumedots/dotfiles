const std = @import("std");
const hubmod = @import("../hub.zig");
const limits = @import("../primitives/limits.zig");
const opencodemod = @import("opencode.zig");
const codexmod = @import("codex.zig");
const sleep = @import("../primitives/sleep.zig");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const interval_ms = 300_000;

const Item = struct {
	id: []const u8,
	title: []const u8,
	plan: limits.Plan,
};

const ItemOut = struct {
	id: []const u8,
	title: []const u8,
	plan: []const u8,
	limits: []const limits.Limit,
	failure: []const u8,
};

const Out = struct {
	list: []ItemOut,
};

pub const Subscriptions = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	opencode: *opencodemod.Opencode,
	codex: *codexmod.Codex,
	last: []u8 = &.{},

	pub fn create(allocator: Allocator, io: Io, hub: *Hub, opencode: *opencodemod.Opencode, codex: *codexmod.Codex) !*Subscriptions {
		const self = try allocator.create(Subscriptions);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.scratch = std.heap.ArenaAllocator.init(allocator),
			.opencode = opencode,
			.codex = codex,
		};

		return self;
	}

	pub fn provider(self: *Subscriptions) hubmod.Provider {
		return .{ .key = "subscriptions", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Subscriptions = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn start(self: *Subscriptions) !void {
		const thread = try std.Thread.spawn(.{}, loop, .{self});
		thread.detach();
	}

	fn loop(self: *Subscriptions) void {
		var waited: usize = 0;

		while (waited < 40) : (waited += 1) sleep.ms(250);

		while (true) {
			self.refresh();
			sleep.ms(interval_ms);
		}
	}

	pub fn refresh(self: *Subscriptions) void {
		self.opencode.refreshPlan();
		self.codex.refreshPlan();
		self.publishIfChanged();
	}

	fn publishIfChanged(self: *Subscriptions) void {
		var out: Writer.Allocating = .init(self.allocator);
		defer out.deinit();

		self.render(&out.writer) catch return;

		self.mutex.lockUncancelable(self.io);
		const same = std.mem.eql(u8, self.last, out.written());
		self.mutex.unlock(self.io);

		if (same) return;

		const copy = self.allocator.dupe(u8, out.written()) catch return;

		self.mutex.lockUncancelable(self.io);
		if (self.last.len > 0) self.allocator.free(self.last);
		self.last = copy;
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn render(self: *Subscriptions, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);
		const arena = self.scratch.allocator();

		const items = [_]Item{
			.{ .id = "opencode", .title = "OpenCode", .plan = self.opencode.planOut(arena) },
			.{ .id = "codex", .title = "ChatGPT", .plan = self.codex.planOut(arena) },
		};

		var list: std.ArrayListUnmanaged(ItemOut) = .empty;

		for (items) |entry| {
			try list.append(arena, .{
				.id = entry.id,
				.title = entry.title,
				.plan = entry.plan.title,
				.limits = entry.plan.limits,
				.failure = entry.plan.failure,
			});
		}

		try writer.print("{f}", .{std.json.fmt(Out{ .list = list.items }, .{})});
	}
};
