const std = @import("std");
const hubmod = @import("../hub.zig");
const iconsmod = @import("../primitives/icons.zig");
const json = @import("../primitives/json.zig");
const proc = @import("../primitives/proc.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const max_asked = 4000;

pub const Icons = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	resolver: *iconsmod.Icons,
	asked: std.StringHashMapUnmanaged([]u8) = .empty,

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

	pub fn start(self: *Icons) !void {
		self.resolver.scan();
	}

	pub fn want(self: *Icons, name: []const u8) void {
		const trimmed = std.mem.trim(u8, name, " \t");
		if (trimmed.len == 0) return;

		self.mutex.lockUncancelable(self.io);
		const known = self.asked.contains(trimmed);
		const full = self.asked.count() >= max_asked;
		self.mutex.unlock(self.io);

		if (known or full) return;

		self.resolveName(trimmed);
	}

	pub fn wantPid(self: *Icons, pid: i64) void {
		if (pid <= 0) return;

		const key = std.fmt.allocPrint(self.allocator, "pid:{d}", .{pid}) catch return;
		defer self.allocator.free(key);

		self.mutex.lockUncancelable(self.io);
		const known = self.asked.contains(key);
		self.mutex.unlock(self.io);

		if (known) return;

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
