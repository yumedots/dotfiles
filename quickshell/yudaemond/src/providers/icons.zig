const std = @import("std");
const hubmod = @import("../hub.zig");
const appsmod = @import("apps.zig");
const iconsmod = @import("../primitives/icons.zig");
const json = @import("../primitives/json.zig");
const sleep = @import("../primitives/sleep.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const Pending = struct { key: []u8, value: []u8 };

const max_asked = 4000;
const rescan_ms = 300_000;

pub const Icons = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	resolver: *iconsmod.Icons,
	asked: std.StringHashMapUnmanaged([]u8) = .empty,
	apps: ?*appsmod.Apps = null,

	pub fn create(allocator: Allocator, io: Io, hub: *Hub, resolver: *iconsmod.Icons) !*Icons {
		const self = try allocator.create(Icons);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.scratch = std.heap.ArenaAllocator.init(allocator),
			.resolver = resolver,
		};

		return self;
	}

	pub fn provider(self: *Icons) hubmod.Provider {
		return .{ .key = "icons", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Icons = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn attach(self: *Icons, apps: *appsmod.Apps) void {
		self.apps = apps;
	}

	pub fn start(self: *Icons) !void {
		self.resolver.scan();
		self.warm(true);

		const thread = try std.Thread.spawn(.{}, loop, .{self});
		thread.detach();
	}

	fn loop(self: *Icons) void {
		while (true) {
			sleep.ms(rescan_ms);
			self.resolver.scan();
			self.warm(true);
		}
	}

	fn known(self: *Icons, key: []const u8) bool {
		self.mutex.lockUncancelable(self.io);
		const found = self.asked.contains(key);
		self.mutex.unlock(self.io);

		return found;
	}

	fn collect(self: *Icons, entries: []const appsmod.Entry, pending: *std.ArrayListUnmanaged(Pending)) void {
		for (entries) |entry| {
			if (entry.id.len == 0) continue;
			if (self.known(entry.id)) continue;

			const path = self.resolver.resolve(entry.id);
			const value = if (path.len > 0)
				std.fmt.allocPrint(self.allocator, "file://{s}", .{path}) catch continue
			else
				self.allocator.dupe(u8, "") catch continue;

			const key = self.allocator.dupe(u8, entry.id) catch {
				self.allocator.free(value);
				continue;
			};

			pending.append(self.allocator, .{ .key = key, .value = value }) catch {
				self.allocator.free(key);
				self.allocator.free(value);
				continue;
			};
		}
	}

	fn merge(self: *Icons, pending: *std.ArrayListUnmanaged(Pending)) bool {
		if (pending.items.len == 0) return false;

		var changed = false;

		self.mutex.lockUncancelable(self.io);

		for (pending.items) |*entry| {
			if (self.asked.getEntry(entry.key)) |found| {
				if (!std.mem.eql(u8, found.value_ptr.*, entry.value)) {
					self.allocator.free(found.value_ptr.*);
					found.value_ptr.* = entry.value;
					entry.value = &.{};
					changed = true;
				}
			} else {
				self.asked.put(self.allocator, entry.key, entry.value) catch continue;
				entry.key = &.{};
				entry.value = &.{};
				changed = true;
			}
		}

		self.mutex.unlock(self.io);

		return changed;
	}

	fn warm(self: *Icons, publish: bool) void {
		const apps = self.apps orelse return;

		self.resolver.ensure();

		var pending: std.ArrayListUnmanaged(Pending) = .empty;

		defer {
			for (pending.items) |entry| {
				self.allocator.free(entry.key);
				self.allocator.free(entry.value);
			}

			pending.deinit(self.allocator);
		}

		const ctx = struct {
			self: *Icons,
			pending: *std.ArrayListUnmanaged(Pending),

			fn run(state: @This(), entries: []const appsmod.Entry) void {
				state.self.collect(entries, state.pending);
			}
		}{ .self = self, .pending = &pending };

		apps.view(ctx, @TypeOf(ctx).run);

		if (self.merge(&pending) and publish) self.hub.publish();
	}

	pub fn want(self: *Icons, name: []const u8) void {
		const trimmed = std.mem.trim(u8, name, " \t");
		if (trimmed.len == 0) return;

		self.mutex.lockUncancelable(self.io);
		const found = self.asked.contains(trimmed);
		const full = self.asked.count() >= max_asked;
		self.mutex.unlock(self.io);

		if (found or full) return;

		self.resolveName(trimmed);
	}

	pub fn wantPid(self: *Icons, pid: i64) void {
		if (pid <= 0) return;

		const key = std.fmt.allocPrint(self.allocator, "pid:{d}", .{pid}) catch return;
		defer self.allocator.free(key);

		if (self.known(key)) return;

		const path = self.resolver.resolvePid(pid);
		const url = if (path.len > 0) std.fmt.allocPrint(self.allocator, "file://{s}", .{path}) catch "" else "";
		defer if (url.len > 0) self.allocator.free(url);

		self.store(key, url);
	}

	fn resolveName(self: *Icons, name: []const u8) void {
		const path = self.resolver.resolve(name);
		const url = if (path.len > 0) std.fmt.allocPrint(self.allocator, "file://{s}", .{path}) catch "" else "";
		defer if (url.len > 0) self.allocator.free(url);

		self.store(name, url);
	}

	fn store(self: *Icons, key: []const u8, value: []const u8) void {
		self.mutex.lockUncancelable(self.io);

		const entry = self.asked.getEntry(key);
		var changed = false;

		if (entry) |found| {
			if (!std.mem.eql(u8, found.value_ptr.*, value)) {
				self.allocator.free(found.value_ptr.*);
				found.value_ptr.* = self.allocator.dupe(u8, value) catch "";
				changed = true;
			}
		} else {
			const key_copy = self.allocator.dupe(u8, key) catch {
				self.mutex.unlock(self.io);
				return;
			};
			const value_copy = self.allocator.dupe(u8, value) catch {
				self.allocator.free(key_copy);
				self.mutex.unlock(self.io);
				return;
			};

			self.asked.put(self.allocator, key_copy, value_copy) catch {
				self.allocator.free(key_copy);
				self.allocator.free(value_copy);
			};

			changed = true;
		}

		self.mutex.unlock(self.io);

		if (changed) self.hub.publish();
	}

	fn render(self: *Icons, writer: *Writer) !void {
		self.warm(false);

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);
		const arena = self.scratch.allocator();

		try writer.writeAll("{\"map\":{");

		var it = self.asked.iterator();
		var first = true;

		while (it.next()) |entry| {
			if (!first) try writer.writeAll(",");
			first = false;

			try json.write(writer, entry.key_ptr.*);
			try writer.writeAll(":");
			try json.write(writer, entry.value_ptr.*);
		}

		try writer.writeAll("}}");

		_ = arena;
	}
};

test "every app entry is resolved before the map is ever asked" {
	const io = std.Io.Threaded.global_single_threaded.io();
	const allocator = std.testing.allocator;

	var hub: hubmod.Hub = .{ .allocator = allocator, .io = io };
	const resolver = try iconsmod.Icons.create(allocator, io);
	defer allocator.destroy(resolver);

	resolver.scanned_at = 1;
	try resolver.files.put(allocator, try allocator.dupe(u8, "top"), try allocator.dupe(u8, "/icons/top.svg"));
	defer {
		var it = resolver.files.iterator();
		while (it.next()) |entry| {
			allocator.free(entry.key_ptr.*);
			allocator.free(entry.value_ptr.*);
		}
		resolver.files.deinit(allocator);
	}

	const self = try Icons.create(allocator, io, &hub, resolver);
	defer {
		var it = self.asked.iterator();
		while (it.next()) |entry| {
			allocator.free(entry.key_ptr.*);
			allocator.free(entry.value_ptr.*);
		}
		self.asked.deinit(allocator);
		self.scratch.deinit();
		allocator.destroy(self);
	}

	const entries = [_]appsmod.Entry{
		.{ .id = @constCast("top"), .name = @constCast("Top"), .icon = @constCast("top"), .exec = @constCast("top"), .command = @constCast("top") },
		.{ .id = @constCast("missing"), .name = @constCast("Missing"), .icon = @constCast("nope"), .exec = @constCast("missing"), .command = @constCast("missing") },
	};

	var pending: std.ArrayListUnmanaged(Pending) = .empty;
	defer {
		for (pending.items) |entry| {
			allocator.free(entry.key);
			allocator.free(entry.value);
		}
		pending.deinit(allocator);
	}

	self.collect(&entries, &pending);
	try std.testing.expectEqual(@as(usize, 2), pending.items.len);
	try std.testing.expect(self.merge(&pending));

	try std.testing.expectEqualStrings("file:///icons/top.svg", self.asked.get("top").?);
	try std.testing.expectEqualStrings("", self.asked.get("missing").?);

	var again: std.ArrayListUnmanaged(Pending) = .empty;
	defer again.deinit(allocator);

	self.collect(&entries, &again);
	try std.testing.expectEqual(@as(usize, 0), again.items.len);
}
