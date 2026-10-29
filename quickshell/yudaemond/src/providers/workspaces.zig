const std = @import("std");
const hubmod = @import("../hub.zig");
const hypr = @import("../primitives/hypr.zig");
const json = @import("../primitives/json.zig");
const exec = @import("../primitives/exec.zig");
const sleep = @import("../primitives/sleep.zig");
const sock = @import("../primitives/sock.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const persistent = [_]i64{ 1, 2, 3, 4 };
const max_slot = 64;

const Out = struct {
	ids: []const i64,
	focusedSlot: i64,
	focusedVersion: i64,
	versions: []const i64,
};

pub const Workspaces = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	ids: std.ArrayListUnmanaged(i64) = .empty,
	focused_slot: i64 = -1,
	focused_version: i64 = 1,
	versions: [max_slot + 1]i64 = @splat(1),

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Workspaces {
		const self = try allocator.create(Workspaces);
		self.* = .{ .allocator = allocator, .io = io, .hub = hub };

		return self;
	}

	pub fn provider(self: *Workspaces) hubmod.Provider {
		return .{ .key = "workspaces", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Workspaces = @ptrCast(@alignCast(ctx));

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		var highest: usize = 0;
		for (self.ids.items) |id| highest = @max(highest, @as(usize, @intCast(@min(id, max_slot))));

		try writer.print("{f}", .{std.json.fmt(Out{
			.ids = self.ids.items,
			.focusedSlot = self.focused_slot,
			.focusedVersion = self.focused_version,
			.versions = self.versions[0 .. highest + 1],
		}, .{})});
	}

	pub fn start(self: *Workspaces) !void {
		self.refresh();

		const thread = try std.Thread.spawn(.{}, loop, .{self});
		thread.detach();
	}

	fn loop(self: *Workspaces) void {
		while (true) {
			self.listen();
			sleep.ms(1000);
			self.refresh();
		}
	}

	fn listen(self: *Workspaces) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const path = hypr.monitorPath(self.io, arena.allocator()) orelse return;

		var buffer: [8192]u8 = undefined;
		var connection = sock.Connection.connect(path, &buffer) catch return;
		defer connection.close();

		while (connection.readLine() catch return) |line| {
			if (std.mem.indexOf(u8, line, "workspace") == null and !std.mem.startsWith(u8, line, "focusedmon")) continue;

			self.refresh();
		}
	}

	pub fn focus(self: *Workspaces, id: i64) void {
		if (id < 1) return;

		const thread = std.Thread.spawn(.{}, focusThread, .{ self, id }) catch return;
		thread.detach();
	}

	fn focusThread(self: *Workspaces, id: i64) void {
		var buffer: [96]u8 = undefined;

		if (hypr.usingLua(self.io, self.allocator)) {
			const script = std.fmt.bufPrint(&buffer, "hl.dispatch(hl.dsp.focus({{ workspace = {d} }}))", .{id}) catch return;
			const result = exec.run(self.io, self.allocator, &.{ "hyprctl", "eval", script }) catch return;
			result.deinit(self.allocator);
			return;
		}

		const command = std.fmt.bufPrint(&buffer, "dispatch workspace {d}", .{id}) catch return;
		const answer = hypr.request(self.io, self.allocator, command) catch return;
		self.allocator.free(answer);
	}

	pub fn refresh(self: *Workspaces) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();

		const all = hypr.request(self.io, allocator, "j/workspaces") catch return;
		const active = hypr.request(self.io, allocator, "j/activeworkspace") catch return;

		const all_json = json.parse(allocator, all) catch return;
		const active_json = json.parse(allocator, active) catch return;

		var ids: std.ArrayListUnmanaged(i64) = .empty;
		for (persistent) |id| ids.append(allocator, id) catch return;

		self.mutex.lockUncancelable(self.io);

		for (json.list(all_json.value)) |entry| {
			const id = json.integer(json.field(entry, "id"));
			if (id > 0) ids.append(allocator, id) catch {};

			if (slotOf(json.textAt(entry, "name"))) |place| {
				if (place.slot > 0 and place.slot <= max_slot and self.versions[@intCast(place.slot)] == 1) {
					self.versions[@intCast(place.slot)] = place.version;
				}
			}
		}

		std.mem.sort(i64, ids.items, {}, std.sort.asc(i64));

		var unique: usize = 0;
		for (ids.items) |id| {
			if (unique > 0 and ids.items[unique - 1] == id) continue;
			ids.items[unique] = id;
			unique += 1;
		}

		const name = json.textAt(active_json.value, "name");
		const active_id = json.integer(json.field(active_json.value, "id"));
		const place = slotOf(name);
		const slot = if (place) |found| found.slot else active_id;
		const version = if (place) |found| found.version else 1;

		if (name.len > 0 and slot > 0 and slot <= max_slot) self.versions[@intCast(slot)] = version;

		const changed = !std.mem.eql(i64, self.ids.items, ids.items[0..unique]) or self.focused_slot != slot or self.focused_version != version;

		self.ids.clearRetainingCapacity();
		self.ids.appendSlice(self.allocator, ids.items[0..unique]) catch {};
		self.focused_slot = slot;
		self.focused_version = version;

		self.mutex.unlock(self.io);

		if (changed) self.hub.publish();
	}
};

const Place = struct { slot: i64, version: i64 };

fn slotOf(name: []const u8) ?Place {
	if (name.len < 4 or name[0] != 'v') return null;

	const dot = std.mem.indexOfScalar(u8, name, '.') orelse return null;
	const slot = std.fmt.parseInt(i64, name[1..dot], 10) catch return null;
	const version = std.fmt.parseInt(i64, name[dot + 1 ..], 10) catch return null;

	return .{ .slot = slot, .version = version };
}

test "versioned workspace names carry a slot and a version" {
	try std.testing.expectEqual(@as(i64, 3), slotOf("v3.2").?.slot);
	try std.testing.expectEqual(@as(i64, 2), slotOf("v3.2").?.version);
	try std.testing.expect(slotOf("3") == null);
	try std.testing.expect(slotOf("vx.1") == null);
}
