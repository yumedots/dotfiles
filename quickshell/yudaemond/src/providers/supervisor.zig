const std = @import("std");
const hubmod = @import("../hub.zig");
const proc = @import("../primitives/proc.zig");
const exec = @import("../primitives/exec.zig");
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

	pub fn route(self: *Supervisor, to_launcher: bool, name: []const u8, arg: []const u8) void {
		if (name.len == 0) return;

		const job = self.allocator.create(Route) catch return;
		job.* = .{
			.supervisor = self,
			.to_launcher = to_launcher,
			.name = self.allocator.dupe(u8, name) catch return,
			.arg = self.allocator.dupe(u8, arg) catch return,
		};

		const thread = std.Thread.spawn(.{}, Route.run, .{job}) catch {
			job.deinit();
			return;
		};
		thread.detach();
	}

	fn render(self: *Supervisor, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		try writer.print("{f}", .{std.json.fmt(Out{ .shell = self.shell, .launcher = self.launcher }, .{})});
	}
};

const Route = struct {
	supervisor: *Supervisor,
	to_launcher: bool,
	name: []u8,
	arg: []u8,

	fn deinit(self: *Route) void {
		const allocator = self.supervisor.allocator;

		allocator.free(self.name);
		allocator.free(self.arg);
		allocator.destroy(self);
	}

	fn run(self: *Route) void {
		defer self.deinit();

		const sup = self.supervisor;
		const found = find(sup.io, sup.allocator) catch return;
		const pid = if (self.to_launcher) found.launcher else found.shell;

		var pid_text: [16]u8 = undefined;
		var argv: [9][]const u8 = undefined;
		var count: usize = 0;

		for ([_][]const u8{ "quickshell", "ipc" }) |word| {
			argv[count] = word;
			count += 1;
		}

		if (pid > 0) {
			argv[count] = "--pid";
			argv[count + 1] = std.fmt.bufPrint(&pid_text, "{d}", .{pid}) catch return;
			count += 2;
		}

		for ([_][]const u8{ "call", "shell", self.name }) |word| {
			argv[count] = word;
			count += 1;
		}

		if (self.arg.len > 0) {
			argv[count] = self.arg;
			count += 1;
		}

		const result = exec.run(sup.io, sup.allocator, argv[0..count]) catch return;
		result.deinit(sup.allocator);
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
