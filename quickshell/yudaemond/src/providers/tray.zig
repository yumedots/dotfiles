const std = @import("std");
const hubmod = @import("../hub.zig");
const png = @import("../primitives/png.zig");
const proc = @import("../primitives/proc.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const Item = extern struct {
	key: [*c]const u8,
	id: [*c]const u8,
	title: [*c]const u8,
	icon_name: [*c]const u8,
	theme_path: [*c]const u8,
	status: [*c]const u8,
	menu_json: [*c]const u8,
	has_menu: i32,
	item_is_menu: i32,
	pixmap_width: i32,
	pixmap_height: i32,
	pixmap_size: u32,
	pixmap: ?[*]const u8,
};

const c = struct {
	extern fn tb_run(ctx: ?*anyopaque, update: *const fn (?*anyopaque, [*]const Item, i32) callconv(.c) void) c_int;
	extern fn tb_activate(key: [*:0]const u8, kind: i32) void;
	extern fn tb_menu_event(key: [*:0]const u8, id: i32) void;
	extern fn tb_menu_open(key: [*:0]const u8) void;
};

const Row = struct {
	key: []const u8,
	id: []const u8,
	title: []const u8,
	icon: []const u8,
	status: []const u8,
	menu: []const u8,
	has_menu: bool,
	item_is_menu: bool,
};

const RowOut = struct {
	key: []const u8,
	id: []const u8,
	title: []const u8,
	icon: []const u8,
	status: []const u8,
	hasMenu: bool,
	itemIsMenu: bool,
};

pub const Tray = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	store: std.heap.ArenaAllocator,
	rows: []Row = &.{},
	runtime: []const u8,

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Tray {
		const self = try allocator.create(Tray);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.store = std.heap.ArenaAllocator.init(allocator),
			.runtime = proc.runtimeDir(io, allocator),
		};

		return self;
	}

	pub fn provider(self: *Tray) hubmod.Provider {
		return .{ .key = "tray", .ctx = self, .render = renderThunk };
	}

	pub fn start(self: *Tray) !void {
		const thread = try std.Thread.spawn(.{}, serve, .{self});
		thread.detach();
	}

	fn serve(self: *Tray) void {
		_ = c.tb_run(self, updateThunk);
	}

	fn text(value: [*c]const u8) []const u8 {
		return if (value == null) "" else std.mem.span(value);
	}

	fn updateThunk(ctx: ?*anyopaque, items: [*]const Item, count: i32) callconv(.c) void {
		const self: *Tray = @ptrCast(@alignCast(ctx.?));

		self.mutex.lockUncancelable(self.io);

		_ = self.store.reset(.retain_capacity);
		const arena = self.store.allocator();

		const rows = arena.alloc(Row, @intCast(count)) catch {
			self.rows = &.{};
			self.mutex.unlock(self.io);
			return;
		};

		for (rows, items[0..@intCast(count)]) |*row, item| {
			row.* = .{
				.key = arena.dupe(u8, text(item.key)) catch "",
				.id = arena.dupe(u8, text(item.id)) catch "",
				.title = arena.dupe(u8, text(item.title)) catch "",
				.icon = self.iconOf(arena, item),
				.status = arena.dupe(u8, text(item.status)) catch "",
				.menu = arena.dupe(u8, text(item.menu_json)) catch "[]",
				.has_menu = item.has_menu != 0,
				.item_is_menu = item.item_is_menu != 0,
			};
		}

		self.rows = rows;
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn iconOf(self: *Tray, arena: Allocator, item: Item) []const u8 {
		if (item.pixmap) |pixels| {
			if (item.pixmap_width > 0 and item.pixmap_height > 0) {
				if (self.pixmapFile(arena, text(item.key), pixels[0..item.pixmap_size], @intCast(item.pixmap_width), @intCast(item.pixmap_height))) |path| return path;
			}
		}

		const name = text(item.icon_name);
		if (name.len == 0) return "";
		if (name[0] == '/') return arena.dupe(u8, name) catch "";

		return std.fmt.allocPrint(arena, "image://icon/{s}", .{name}) catch "";
	}

	fn pixmapFile(self: *Tray, arena: Allocator, key: []const u8, pixels: []const u8, width: usize, height: usize) ?[]const u8 {
		const rgba = self.allocator.alloc(u8, pixels.len) catch return null;
		defer self.allocator.free(rgba);

		var at: usize = 0;
		while (at + 3 < pixels.len) : (at += 4) {
			rgba[at] = pixels[at + 1];
			rgba[at + 1] = pixels[at + 2];
			rgba[at + 2] = pixels[at + 3];
			rgba[at + 3] = pixels[at];
		}

		const bytes = png.encodeRgba(self.allocator, width, height, width * 4, 4, rgba) catch return null;
		defer self.allocator.free(bytes);

		const path = std.fmt.allocPrint(arena, "{s}/yudaemond-tray-{x}.png", .{ self.runtime, std.hash.Wyhash.hash(0, key) }) catch return null;

		proc.writeFile(self.io, path, bytes) catch return null;

		return path;
	}

	pub fn activate(self: *Tray, key: []const u8, kind: i32) void {
		const copy = std.fmt.allocPrintSentinel(self.allocator, "{s}", .{key}, 0) catch return;
		defer self.allocator.free(copy);

		c.tb_activate(copy.ptr, kind);
	}

	pub fn menuEvent(self: *Tray, key: []const u8, id: i32) void {
		const copy = std.fmt.allocPrintSentinel(self.allocator, "{s}", .{key}, 0) catch return;
		defer self.allocator.free(copy);

		c.tb_menu_event(copy.ptr, id);
	}

	pub fn menuOpen(self: *Tray, key: []const u8) void {
		const copy = std.fmt.allocPrintSentinel(self.allocator, "{s}", .{key}, 0) catch return;
		defer self.allocator.free(copy);

		c.tb_menu_open(copy.ptr);
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Tray = @ptrCast(@alignCast(ctx));

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		try writer.writeAll("[");

		for (self.rows, 0..) |row, index| {
			if (index > 0) try writer.writeAll(",");

			try writer.print("{f}", .{std.json.fmt(RowOut{
				.key = row.key,
				.id = row.id,
				.title = row.title,
				.icon = row.icon,
				.status = row.status,
				.hasMenu = row.has_menu,
				.itemIsMenu = row.item_is_menu,
			}, .{})});

			writer.undo(1);
			try writer.print(",\"menu\":{s}}}", .{row.menu});
		}

		try writer.writeAll("]");
	}
};
