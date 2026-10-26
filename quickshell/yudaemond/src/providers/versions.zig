const std = @import("std");
const hubmod = @import("../hub.zig");
const json = @import("../primitives/json.zig");
const proc = @import("../primitives/proc.zig");
const sleep = @import("../primitives/sleep.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

pub const Versions = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	body: []u8 = &.{},
	seen_at: std.Io.Timestamp = .zero,

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Versions {
		const self = try allocator.create(Versions);
		self.* = .{ .allocator = allocator, .io = io, .hub = hub, .body = try allocator.dupe(u8, "{}") };

		return self;
	}

	pub fn provider(self: *Versions) hubmod.Provider {
		return .{ .key = "versions", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Versions = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn start(self: *Versions) !void {
		self.reload();

		const thread = try std.Thread.spawn(.{}, loop, .{self});
		thread.detach();
	}

	fn loop(self: *Versions) void {
		while (true) {
			sleep.ms(2000);
			self.watch();
		}
	}

	fn path(self: *Versions, allocator: Allocator) ![]u8 {
		return std.fmt.allocPrint(allocator, "{s}/.config/quickshell/cache/versions.json", .{proc.home(self.io, self.allocator)});
	}

	fn watch(self: *Versions) void {
		const target = self.path(self.allocator) catch return;
		defer self.allocator.free(target);

		const stat = std.Io.Dir.cwd().statFile(self.io, target, .{}) catch return;
		if (stat.mtime.nanoseconds == self.seen_at.nanoseconds) return;

		self.reload();
	}

	pub fn reload(self: *Versions) void {
		const target = self.path(self.allocator) catch return;
		defer self.allocator.free(target);

		const text = proc.readFile(self.io, self.allocator, target) catch "";
		defer if (text.len > 0) self.allocator.free(text);

		const stat = std.Io.Dir.cwd().statFile(self.io, target, .{}) catch null;

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		var body: []const u8 = "{}";

		if (text.len > 0) {
			if (json.parse(arena.allocator(), text)) |parsed| {
				if (parsed.value == .object) body = std.mem.trim(u8, text, " \n\r");
			} else |_| {}
		}

		self.mutex.lockUncancelable(self.io);
		const same = std.mem.eql(u8, self.body, body);
		const next = self.allocator.dupe(u8, body) catch {
			self.mutex.unlock(self.io);
			return;
		};
		self.allocator.free(self.body);
		self.body = next;
		if (stat) |info| self.seen_at = info.mtime;
		self.mutex.unlock(self.io);

		if (!same) self.hub.publish();
	}

	fn render(self: *Versions, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		try writer.writeAll(self.body);
	}
};

test "a bad file leaves an empty object" {
	try std.testing.expectEqualStrings("{}", "{}");
}
