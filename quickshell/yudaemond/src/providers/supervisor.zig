const std = @import("std");
const hubmod = @import("../hub.zig");
const proc = @import("../primitives/proc.zig");
const sleep = @import("../primitives/sleep.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const Out = struct {
	shell: bool,
	launcher: bool,
};

pub const Supervisor = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	shell: bool = false,
	launcher: bool = false,
	seen: bool = false,

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Supervisor {
		const self = try allocator.create(Supervisor);
		self.* = .{ .allocator = allocator, .io = io, .hub = hub };

		return self;
	}

	pub fn provider(self: *Supervisor) hubmod.Provider {
		return .{ .key = "supervisor", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Supervisor = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn start(self: *Supervisor) !void {
		const thread = try std.Thread.spawn(.{}, loop, .{self});
		thread.detach();
	}

	fn loop(self: *Supervisor) void {
		sleep.ms(4000);

		while (true) {
			self.check();
			sleep.ms(2000);
		}
	}

	fn check(self: *Supervisor) void {
		const found = find(self.io, self.allocator) catch return;

		const shell = found.shell;
		const launcher = found.launcher;
		const shell_now = shell > 0;
		const launcher_now = launcher > 0;

		self.mutex.lockUncancelable(self.io);
		const previous = self.seen;
		const was_shell = self.shell;
		const was_launcher = self.launcher;
		self.shell = shell_now;
		self.launcher = launcher_now;
		self.seen = true;
		self.mutex.unlock(self.io);

		if (previous and was_shell and !shell_now and launcher_now) {
			terminate(launcher);
		} else if (previous and was_launcher and !launcher_now and shell_now) {
			terminate(shell);
		}

		if (previous and (was_shell != shell_now or was_launcher != launcher_now)) self.hub.publish();
	}

	fn render(self: *Supervisor, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		try writer.print("{f}", .{std.json.fmt(Out{ .shell = self.shell, .launcher = self.launcher }, .{})});
	}
};

const Found = struct { shell: i32 = 0, launcher: i32 = 0 };

fn find(io: Io, allocator: Allocator) !Found {
	var dir = std.Io.Dir.cwd().openDir(io, "/proc", .{ .iterate = true }) catch return .{};
	defer dir.close(io);

	var out: Found = .{};
	var it = dir.iterate();

	while (try it.next(io)) |entry| {
		const pid = std.fmt.parseInt(i32, entry.name, 10) catch continue;

		const comm_path = try std.fmt.allocPrint(allocator, "/proc/{d}/comm", .{pid});
		defer allocator.free(comm_path);

		const comm = proc.readFile(io, allocator, comm_path) catch "";
		defer if (comm.len > 0) allocator.free(comm);

		if (!std.mem.eql(u8, std.mem.trim(u8, comm, " \n\r"), "quickshell")) continue;

		const cmd_path = try std.fmt.allocPrint(allocator, "/proc/{d}/cmdline", .{pid});
		defer allocator.free(cmd_path);

		const cmd = proc.readFile(io, allocator, cmd_path) catch "";
		defer if (cmd.len > 0) allocator.free(cmd);

		if (std.mem.indexOf(u8, cmd, "launcherShell.qml") != null) {
			if (out.launcher == 0) out.launcher = pid;
		} else if (out.shell == 0) {
			out.shell = pid;
		}
	}

	return out;
}

fn terminate(pid: i32) void {
	if (pid <= 1) return;

	_ = std.posix.kill(pid, std.posix.SIG.TERM) catch {};
}

test "the launcher is the quickshell with the shell file in its cmdline" {
	const cmdline = "/usr/bin/quickshell\x00-p\x00/home/me/.config/quickshell/launcherShell.qml\x00";
	try std.testing.expect(std.mem.indexOf(u8, cmdline, "launcherShell.qml") != null);
	try std.testing.expect(std.mem.indexOf(u8, "quickshell\x00", "launcherShell.qml") == null);
}
