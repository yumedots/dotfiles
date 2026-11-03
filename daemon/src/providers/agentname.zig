const std = @import("std");
const hubmod = @import("../hub.zig");
const config = @import("../primitives/config.zig");
const proc = @import("../primitives/proc.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

pub const AgentName = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	path: []u8,
	name: []u8 = &.{},

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*AgentName {
		const self = try allocator.create(AgentName);
		self.* = .{ .allocator = allocator, .io = io, .hub = hub, .path = try pathOf(allocator, io) };

		const body = proc.readFileOr(io, allocator, self.path);
		defer if (body.len > 0) allocator.free(body);

		self.name = try allocator.dupe(u8, std.mem.trim(u8, body, " \t\r\n"));

		return self;
	}

	pub fn provider(self: *AgentName) hubmod.Provider {
		return .{ .key = "agentName", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *AgentName = @ptrCast(@alignCast(ctx));

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		try writer.print("{f}", .{std.json.fmt(self.name, .{})});
	}

	pub fn set(self: *AgentName, text: []const u8) void {
		const trimmed = std.mem.trim(u8, text, " \t\r\n");
		const copy = self.allocator.dupe(u8, trimmed) catch return;

		self.mutex.lockUncancelable(self.io);
		self.allocator.free(self.name);
		self.name = copy;
		self.mutex.unlock(self.io);

		const line = std.fmt.allocPrint(self.allocator, "{s}\n", .{copy}) catch return;
		defer self.allocator.free(line);

		proc.writeFile(self.io, self.path, line) catch {};
		self.hub.publish();
	}
};

fn pathOf(allocator: Allocator, io: Io) ![]u8 {
	const cfg = try config.Config.load(io, allocator);
	defer cfg.deinit();

	const file = cfg.string("agentNameFile", allocator) orelse try allocator.dupe(u8, "cache/agent-name");
	defer allocator.free(file);

	return std.fmt.allocPrint(allocator, "{s}/.config/quickshell/{s}", .{ proc.home(io, allocator), file });
}
