const std = @import("std");
const hubmod = @import("../hub.zig");
const configmod = @import("../primitives/config.zig");
const proc = @import("../primitives/proc.zig");
const watch = @import("../primitives/watch.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

pub const Config = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	state: configmod.Config,
	shell_keys: []const []const u8 = &.{},

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Config {
		const self = try allocator.create(Config);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.state = try configmod.Config.parse(allocator, ""),
		};

		return self;
	}

	pub fn provider(self: *Config) hubmod.Provider {
		return .{ .key = "settings", .ctx = self, .render = renderThunk };
	}

	pub fn usage(self: *Config) hubmod.Provider {
		return .{ .key = "config", .ctx = self, .render = usageThunk };
	}

	fn usageThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		_ = ctx;
		try configmod.renderUsage(writer);
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Config = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn start(self: *Config) !void {
		self.shell_keys = shellKeys(self.io, self.allocator) catch &.{};

		const thread = try std.Thread.spawn(.{}, watchLoop, .{self});
		thread.detach();
	}

	fn path(self: *Config, allocator: Allocator) []const u8 {
		return std.fmt.allocPrint(allocator, "{s}/.config/quickshell/config.toml", .{proc.home(self.io, allocator)}) catch "/nonexistent";
	}

	fn watchLoop(self: *Config) void {
		self.reload();

		const file = self.path(self.allocator);
		defer self.allocator.free(file);

		watch.watchFile(self.io, self.allocator, file, self, reloadThunk) catch {};
	}

	fn reloadThunk(ctx: *anyopaque) void {
		const self: *Config = @ptrCast(@alignCast(ctx));
		self.reload();
	}

	fn reload(self: *Config) void {
		const file = self.path(self.allocator);
		defer self.allocator.free(file);

		const body = proc.readFile(self.io, self.allocator, file) catch return;
		defer self.allocator.free(body);

		const next = configmod.Config.parse(self.allocator, body) catch return;

		self.mutex.lockUncancelable(self.io);
		const previous = self.state;
		self.state = next;
		self.mutex.unlock(self.io);

		previous.deinit();

		self.hub.publish();
		self.audit();
	}

	fn render(self: *Config, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		try self.state.render(writer);
	}

	fn audit(self: *Config) void {
		const used = configmod.usedKeys(self.allocator) catch return;
		defer {
			for (used) |name| self.allocator.free(name);
			self.allocator.free(used);
		}

		var consumed: std.ArrayListUnmanaged([]const u8) = .empty;
		defer consumed.deinit(self.allocator);

		consumed.appendSlice(self.allocator, used) catch return;
		consumed.appendSlice(self.allocator, self.shell_keys) catch return;

		const unknown = self.unknownList(consumed.items) catch return;
		defer {
			for (unknown) |name| self.allocator.free(name);
			self.allocator.free(unknown);
		}

		if (unknown.len == 0) return;

		var line: Writer.Allocating = .init(self.allocator);
		defer line.deinit();

		line.writer.print("config: {d} unknown keys: ", .{unknown.len}) catch return;
		for (unknown, 0..) |name, index| {
			if (index > 0) line.writer.writeAll(", ") catch return;
			line.writer.writeAll(name) catch return;
		}

		std.debug.print("{s}\n", .{line.written()});
	}

	fn unknownList(self: *Config, consumed: []const []const u8) ![][]u8 {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		return self.state.unknown(self.allocator, consumed);
	}
};

pub fn shellKeys(io: Io, allocator: Allocator) ![]const []const u8 {
	const file = std.fmt.allocPrint(allocator, "{s}/.config/quickshell/services/Config.qml", .{proc.home(io, allocator)}) catch return &.{};
	defer allocator.free(file);

	const body = proc.readFile(io, allocator, file) catch return &.{};
	defer allocator.free(body);

	var out: std.ArrayListUnmanaged([]const u8) = .empty;
	errdefer {
		for (out.items) |name| allocator.free(name);
		out.deinit(allocator);
	}

	var rest = body;
	while (std.mem.indexOf(u8, rest, "settings.")) |at| {
		const tail = rest[at + "settings.".len ..];

		var end: usize = 0;
		while (end < tail.len and (std.ascii.isAlphanumeric(tail[end]) or tail[end] == '_')) end += 1;

		if (end > 0) {
			const key = tail[0..end];

			var known = false;
			for (out.items) |item| {
				if (!std.mem.eql(u8, item, key)) continue;
				known = true;
				break;
			}

			if (!known) try out.append(allocator, try allocator.dupe(u8, key));
		}

		rest = tail[end..];
	}

	return out.toOwnedSlice(allocator);
}

test "a broken edit keeps the config it already had" {
	var hub: hubmod.Hub = .{ .allocator = std.testing.allocator, .io = std.Io.Threaded.global_single_threaded.io() };

	const self = try Config.create(std.testing.allocator, hub.io, &hub);
	defer {
		self.state.deinit();
		std.testing.allocator.destroy(self);
	}

	const good = try configmod.Config.parse(std.testing.allocator, "[colors]\nsurface = \"#101010\"\n");
	self.state.deinit();
	self.state = good;

	const broken = configmod.Config.parse(std.testing.allocator, "surface = ");
	try std.testing.expectError(error.InvalidToml, broken);

	try std.testing.expectEqualStrings("#101010", self.state.color("surface").?);
}
