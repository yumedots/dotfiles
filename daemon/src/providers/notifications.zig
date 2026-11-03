const std = @import("std");
const hubmod = @import("../hub.zig");
const config = @import("../primitives/config.zig");
const png = @import("../primitives/png.zig");
const proc = @import("../primitives/proc.zig");

const Note = extern struct {
	app: [*c]const u8,
	icon: [*c]const u8,
	summary: [*c]const u8,
	body: [*c]const u8,
	desktop: [*c]const u8,
	image_path: [*c]const u8,
	image_data: ?[*]const u8,
	image_size: u32,
	image_width: i32,
	image_height: i32,
	image_stride: i32,
	image_channels: i32,
	image_alpha: i32,
	replaces: u32,
	urgency: i32,
	timeout: i32,
	pid: i32,
	action_count: i32,
	actions: [32][*c]const u8,
};

const c = struct {
	extern fn nb_run(ctx: ?*anyopaque, notify: *const fn (?*anyopaque, *const Note) callconv(.c) u32, close: *const fn (?*anyopaque, u32) callconv(.c) void) c_int;
	extern fn nb_emit_closed(id: u32, reason: u32) void;
	extern fn nb_emit_action(id: u32, key: [*:0]const u8) void;
};

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const reason_dismissed: u32 = 2;

const ActionOut = struct {
	key: []const u8,
	label: []const u8,
};

const RowOut = struct {
	id: u32,
	appName: []const u8,
	summary: []const u8,
	body: []const u8,
	image: []const u8,
	icon: []const u8,
	desktopEntry: []const u8,
	senderPid: i32,
	urgent: bool,
	timeout: i32,
	gone: bool,
	actions: []const ActionOut,
};

const Out = struct {
	seq: u64,
	last: u32,
	list: []const RowOut,
};

const Row = struct {
	id: u32,
	app: []u8,
	summary: []u8,
	body: []u8,
	image: []u8,
	icon: []u8,
	desktop: []u8,
	pid: i32,
	urgent: bool,
	timeout: i32,
	gone: bool = false,
	actions: []ActionOut,
};

pub const Notifications = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	rows: std.ArrayListUnmanaged(Row) = .empty,
	next_id: u32 = 0,
	seq: u64 = 0,
	last: u32 = 0,
	history: usize = 50,
	runtime: []const u8,

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Notifications {
		const self = try allocator.create(Notifications);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.scratch = std.heap.ArenaAllocator.init(allocator),
			.runtime = proc.runtimeDir(io, allocator),
		};

		if (config.Config.load(io, allocator)) |cfg| {
			defer cfg.deinit();
			self.history = @intCast(@max(1, cfg.integer("notifyHistory", 50)));
		} else |_| {}

		return self;
	}

	pub fn provider(self: *Notifications) hubmod.Provider {
		return .{ .key = "notifications", .ctx = self, .render = renderThunk };
	}

	pub fn start(self: *Notifications) !void {
		const thread = try std.Thread.spawn(.{}, serve, .{self});
		thread.detach();
	}

	fn serve(self: *Notifications) void {
		_ = c.nb_run(self, notifyThunk, closeThunk);
	}

	fn notifyThunk(ctx: ?*anyopaque, note: *const Note) callconv(.c) u32 {
		const self: *Notifications = @ptrCast(@alignCast(ctx.?));
		const id = self.adopt(note);

		self.hub.publish();

		return id;
	}

	fn closeThunk(ctx: ?*anyopaque, id: u32) callconv(.c) void {
		const self: *Notifications = @ptrCast(@alignCast(ctx.?));

		self.mutex.lockUncancelable(self.io);
		for (self.rows.items) |*row| {
			if (row.id == id) row.gone = true;
		}
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn text(value: [*c]const u8) []const u8 {
		return if (value == null) "" else std.mem.span(value);
	}

	fn adopt(self: *Notifications, note: *const Note) u32 {
		const a = self.allocator;

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		var id = note.replaces;
		var existing: ?usize = null;

		if (id != 0) {
			for (self.rows.items, 0..) |row, index| {
				if (row.id == id) existing = index;
			}
		}

		if (existing == null) {
			self.next_id += 1;
			id = self.next_id;
		}

		const image = self.imageOf(id, note);

		var actions: std.ArrayListUnmanaged(ActionOut) = .empty;
		var at: usize = 0;
		while (at + 1 < @as(usize, @intCast(note.action_count))) : (at += 2) {
			actions.append(a, .{
				.key = a.dupe(u8, text(note.actions[at])) catch continue,
				.label = a.dupe(u8, text(note.actions[at + 1])) catch continue,
			}) catch {};
		}

		const row = Row{
			.id = id,
			.app = a.dupe(u8, text(note.app)) catch return id,
			.summary = a.dupe(u8, text(note.summary)) catch return id,
			.body = a.dupe(u8, text(note.body)) catch return id,
			.image = image,
			.icon = a.dupe(u8, text(note.icon)) catch return id,
			.desktop = a.dupe(u8, text(note.desktop)) catch return id,
			.pid = note.pid,
			.urgent = note.urgency == 2,
			.timeout = note.timeout,
			.actions = actions.toOwnedSlice(a) catch return id,
		};

		if (existing) |index| {
			self.free(self.rows.items[index]);
			self.rows.items[index] = row;
		} else {
			self.rows.append(a, row) catch return id;

			while (self.rows.items.len > self.history) self.free(self.rows.orderedRemove(0));
		}

		self.seq += 1;
		self.last = id;

		return id;
	}

	fn imageOf(self: *Notifications, id: u32, note: *const Note) []u8 {
		const a = self.allocator;

		if (note.image_data) |pixels| if (note.image_width > 0 and note.image_height > 0) {
			const data = pixels[0..note.image_size];

			if (png.encodeRgba(a, @intCast(note.image_width), @intCast(note.image_height), @intCast(note.image_stride), @intCast(note.image_channels), data)) |bytes| {
				defer a.free(bytes);

				if (self.imagePath(id)) |path| {
					proc.writeFile(self.io, path, bytes) catch {
						a.free(path);
						return a.dupe(u8, "") catch &.{};
					};

					return path;
				}
			} else |_| {}
		};

		return a.dupe(u8, text(note.image_path)) catch &.{};
	}

	fn imagePath(self: *Notifications, id: u32) ?[]u8 {
		return std.fmt.allocPrint(self.allocator, "{s}/yudaemond-notify-{d}.png", .{ self.runtime, id }) catch null;
	}

	fn free(self: *Notifications, row: Row) void {
		const a = self.allocator;

		if (std.mem.endsWith(u8, row.image, ".png") and std.mem.startsWith(u8, row.image, self.runtime))
			std.Io.Dir.cwd().deleteFile(self.io, row.image) catch {};

		a.free(row.app);
		a.free(row.summary);
		a.free(row.body);
		a.free(row.image);
		a.free(row.icon);
		a.free(row.desktop);

		for (row.actions) |action| {
			a.free(action.key);
			a.free(action.label);
		}
		a.free(row.actions);
	}

	pub fn post(self: *Notifications, app: []const u8, summary: []const u8, body: []const u8, timeout: i32) void {
		self.insert(app, summary, body, timeout);
		self.hub.publish();
	}

	fn insert(self: *Notifications, app: []const u8, summary: []const u8, body: []const u8, timeout: i32) void {
		const a = self.allocator;

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		self.next_id += 1;

		self.rows.append(a, .{
			.id = self.next_id,
			.app = a.dupe(u8, app) catch return,
			.summary = a.dupe(u8, summary) catch return,
			.body = a.dupe(u8, body) catch return,
			.image = a.alloc(u8, 0) catch return,
			.icon = a.alloc(u8, 0) catch return,
			.desktop = a.alloc(u8, 0) catch return,
			.pid = 0,
			.urgent = false,
			.timeout = timeout,
			.actions = a.alloc(ActionOut, 0) catch return,
		}) catch return;

		while (self.rows.items.len > self.history) self.free(self.rows.orderedRemove(0));

		self.seq += 1;
		self.last = self.next_id;
	}

	pub fn dismiss(self: *Notifications, id: u32) void {
		self.mutex.lockUncancelable(self.io);

		for (self.rows.items, 0..) |row, index| {
			if (row.id != id) continue;

			if (!row.gone) c.nb_emit_closed(id, reason_dismissed);
			self.free(self.rows.orderedRemove(index));
			break;
		}

		self.mutex.unlock(self.io);
		self.hub.publish();
	}

	pub fn dismissAll(self: *Notifications) void {
		self.mutex.lockUncancelable(self.io);

		for (self.rows.items) |row| {
			if (!row.gone) c.nb_emit_closed(row.id, reason_dismissed);
			self.free(row);
		}
		self.rows.clearRetainingCapacity();

		self.mutex.unlock(self.io);
		self.hub.publish();
	}

	pub fn invoke(self: *Notifications, id: u32, key: []const u8) void {
		const copy = std.fmt.allocPrintSentinel(self.allocator, "{s}", .{key}, 0) catch return;
		defer self.allocator.free(copy);

		c.nb_emit_action(id, copy.ptr);
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Notifications = @ptrCast(@alignCast(ctx));

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);
		const arena = self.scratch.allocator();

		const list = try arena.alloc(RowOut, self.rows.items.len);
		for (self.rows.items, list) |row, *out| {
			out.* = .{
				.id = row.id,
				.appName = row.app,
				.summary = row.summary,
				.body = row.body,
				.image = row.image,
				.icon = row.icon,
				.desktopEntry = row.desktop,
				.senderPid = row.pid,
				.urgent = row.urgent,
				.timeout = row.timeout,
				.gone = row.gone,
				.actions = row.actions,
			};
		}

		try writer.print("{f}", .{std.json.fmt(Out{ .seq = self.seq, .last = self.last, .list = list }, .{})});
	}
};

test "a finished task lands in the list as a row" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();
	const io = std.testing.io;

	var hub: hubmod.Hub = .{ .allocator = allocator, .io = io };
	var notes: Notifications = .{ .allocator = allocator, .io = io, .hub = &hub, .scratch = std.heap.ArenaAllocator.init(allocator), .runtime = "/tmp" };
	const self = &notes;

	self.post("OpenCode", "Greeting", "Task finished", 5000);

	try std.testing.expectEqual(@as(usize, 1), self.rows.items.len);
	try std.testing.expectEqual(@as(u32, 1), self.last);
	try std.testing.expectEqualStrings("OpenCode", self.rows.items[0].app);
	try std.testing.expectEqualStrings("Greeting", self.rows.items[0].summary);
	try std.testing.expectEqualStrings("Task finished", self.rows.items[0].body);
	try std.testing.expectEqual(@as(i32, 5000), self.rows.items[0].timeout);
}
