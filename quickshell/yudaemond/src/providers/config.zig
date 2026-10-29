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

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Config = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn start(self: *Config) !void {
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
	}

	fn render(self: *Config, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		try self.state.render(writer);
	}
};

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
