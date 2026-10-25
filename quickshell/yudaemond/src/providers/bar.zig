const std = @import("std");
const hubmod = @import("../hub.zig");
const json = @import("../primitives/json.zig");
const proc = @import("../primitives/proc.zig");
const sleep = @import("../primitives/sleep.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;
const Value = json.Value;

const empty = "{\"position\":\"top\",\"transparent\":false,\"centerAnchor\":\"\",\"left\":[],\"center\":[],\"right\":[]}";

pub const Bar = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	body: []u8 = &.{},
	seen_at: std.Io.Timestamp = .zero,

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Bar {
		const self = try allocator.create(Bar);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.body = try allocator.dupe(u8, empty),
		};

		return self;
	}

	pub fn provider(self: *Bar) hubmod.Provider {
		return .{ .key = "bar", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Bar = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn start(self: *Bar) !void {
		self.reload();

		const thread = try std.Thread.spawn(.{}, loop, .{self});
		thread.detach();
	}

	fn loop(self: *Bar) void {
		while (true) {
			sleep.ms(2000);
			self.watch();
		}
	}

	fn watch(self: *Bar) void {
		const path = pathOf(self.io, self.allocator) catch return;
		defer self.allocator.free(path);

		const stat = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch return;
		if (stat.mtime.nanoseconds == self.seen_at.nanoseconds) return;

		self.reload();
	}

	pub fn reload(self: *Bar) void {
		const path = pathOf(self.io, self.allocator) catch return;
		defer self.allocator.free(path);

		const body = proc.readFile(self.io, self.allocator, path) catch "";
		defer if (body.len > 0) self.allocator.free(body);

		const stat = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch null;

		const next = normalize(self.allocator, body) catch self.allocator.dupe(u8, empty) catch return;

		self.mutex.lockUncancelable(self.io);
		self.allocator.free(self.body);
		self.body = next;
		if (stat) |info| self.seen_at = info.mtime;
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn render(self: *Bar, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		try writer.writeAll(self.body);
	}
};

fn pathOf(io: Io, allocator: Allocator) ![]u8 {
	return std.fmt.allocPrint(allocator, "{s}/.config/quickshell/topbarlayout.json", .{proc.home(io, allocator)});
}

fn normalize(allocator: Allocator, body: []const u8) ![]u8 {
	var arena = std.heap.ArenaAllocator.init(allocator);
	defer arena.deinit();

	const parsed = try json.parse(arena.allocator(), body);
	const root = parsed.value;

	const bar = json.field(root, "bar") orelse return error.NoBar;
	const layout = json.field(bar, "layout") orelse return error.NoLayout;

	const position = json.textAt(bar, "position");
	const anchor = json.textAt(bar, "centerAnchor");

	const out = struct {
		position: []const u8,
		transparent: bool,
		centerAnchor: []const u8,
		left: []Value,
		center: []Value,
		right: []Value,
	}{
		.position = if (std.mem.eql(u8, position, "bottom")) "bottom" else "top",
		.transparent = json.flag(bar, "transparent"),
		.centerAnchor = anchor,
		.left = slots(arena.allocator(), json.field(layout, "left")),
		.center = slots(arena.allocator(), json.field(layout, "center")),
		.right = slots(arena.allocator(), json.field(layout, "right")),
	};

	var text: Writer.Allocating = .init(allocator);
	errdefer text.deinit();

	try text.writer.print("{f}", .{std.json.fmt(out, .{})});

	return text.toOwnedSlice();
}

fn slots(allocator: Allocator, value: ?Value) []Value {
	var out: std.ArrayListUnmanaged(Value) = .empty;

	for (json.list(value)) |entry| {
		if (json.textAt(entry, "id").len == 0) continue;

		out.append(allocator, entry) catch continue;
	}

	return out.items;
}

test "the bar layout keeps the slots the shell can draw" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const text = try normalize(arena.allocator(),
		\\{"version":1,"bar":{"position":"bottom","transparent":true,"centerAnchor":"clock","layout":{
		\\ "left":[{"id":"workspaces"},{"id":""}],
		\\ "center":[{"id":"clock"}],
		\\ "right":[{"id":"cpu","mode":"rss"}]}}}
	);

	const parsed = try json.parse(arena.allocator(), text);
	try std.testing.expectEqualStrings("bottom", json.textAt(parsed.value, "position"));
	try std.testing.expect(json.flag(parsed.value, "transparent"));
	try std.testing.expectEqualStrings("clock", json.textAt(parsed.value, "centerAnchor"));
	try std.testing.expectEqual(@as(usize, 1), json.listAt(parsed.value, "left").len);
	try std.testing.expectEqualStrings("rss", json.textAt(json.listAt(parsed.value, "right")[0], "mode"));
}

test "a broken layout is rejected" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	try std.testing.expectError(error.NoBar, normalize(arena.allocator(), "{\"version\":1}"));

	if (normalize(arena.allocator(), "nonsense")) |_| {
		return error.TestUnexpectedResult;
	} else |_| {}
}
