const std = @import("std");
const exec = @import("primitives/exec.zig");
const fmt = @import("primitives/fmt.zig");
const hypr = @import("primitives/hypr.zig");
const json = @import("primitives/json.zig");
const proc = @import("primitives/proc.zig");
const sleep = @import("primitives/sleep.zig");
const sock = @import("primitives/sock.zig");
const environ = @import("primitives/environ.zig");
const report = @import("bench_report.zig");

const gpa = std.heap.smp_allocator;
const Allocator = std.mem.Allocator;
const Io = std.Io;

const usage =
	\\usage: yudaemond bench widgets [--json] [--hold ms] [--timeout ms] [--widgets id[,id]]
	\\
	\\Opens every shell widget in the nested hypr-test session one at a time and
	\\measures what it costs: open time (trigger returned to on screen), then shell
	\\and daemon RSS growth and CPU over the hold while it stays open, then closes
	\\it with Escape and waits for it to go.
	\\
	\\The instance is reused when one is live, otherwise started here and stopped
	\\again on the way out. A widget the session cannot show (no window to switch
	\\to, not in the bar layout, no tray items) is n/a with the reason and does not
	\\fail the run.
	\\
	\\worst = highest shell% + daemon% while open, then RSS growth, then open time.
	\\Signal: hyprctl layers for bar popups (~10ms); a grim PPM frame diff for the
	\\always mapped windows (~35ms). Both processes are sampled from 250ms after
	\\the widget is visible.
	;

const Kind = enum { layer, bar, frame, launcher, clipboard, windows, control, skip };

const Spec = struct {
	id: []const u8,
	kind: Kind,
	note: []const u8 = "",
	miss: []const u8 = "nothing appeared within the timeout",
};

pub const specs = [_]Spec{
	.{ .id = "launcher", .kind = .launcher },
	.{ .id = "clipboard", .kind = .clipboard },
	.{ .id = "windows", .kind = .windows },
	.{ .id = "windowsStep", .kind = .control, .note = "control entry point, steps the window switcher" },
	.{ .id = "cpu", .kind = .layer },
	.{ .id = "memory", .kind = .layer },
	.{ .id = "volume", .kind = .layer },
	.{ .id = "calendar", .kind = .layer },
	.{ .id = "weather", .kind = .layer },
	.{ .id = "notifications", .kind = .layer },
	.{ .id = "github", .kind = .layer },
	.{ .id = "media", .kind = .layer },
	.{ .id = "network", .kind = .layer },
	.{ .id = "speedtest", .kind = .skip, .note = "runs a real speed test; its popup is measured as network" },
	.{ .id = "bareBar", .kind = .skip, .note = "toggles the bare bar mode, a fade rather than a popup" },
	.{ .id = "killPopups", .kind = .control, .note = "control entry point, closes popups" },
	.{ .id = "killPopupsLocal", .kind = .control, .note = "control entry point, closes the launcher" },
	.{ .id = "closeBarPopups", .kind = .control, .note = "control entry point, closes bar popups" },
	.{ .id = "closeLauncher", .kind = .control, .note = "control entry point, closes the launcher" },
	.{ .id = "display", .kind = .layer },
	.{ .id = "agent", .kind = .layer },
	.{ .id = "power", .kind = .layer },
	.{ .id = "powerMenu", .kind = .frame },
	.{ .id = "tray", .kind = .bar, .miss = "the tray has no items in the test session" },
	.{ .id = "wallpaper", .kind = .frame },
};

const Instance = struct {
	id: []const u8,
	shell: i32,
	worktree: []const u8,
	signature: []const u8,
	wayland: []const u8,
	output: []const u8,
};

const Layers = struct {
	tooltip: bool = false,
	launcher: bool = false,
	bar_from: usize = 0,
	bar_to: usize = 0,
};

pub const Ppm = struct {
	w: usize,
	h: usize,
	off: usize,
};

const Bench = struct {
	io: Io,
	allocator: Allocator,
	inst: Instance,
	env: *std.process.Environ.Map,
	hold_ns: i96,
	timeout_ns: i96,
	launcher: i32 = 0,
	launcher_owned: bool = false,
	launcher_child: ?std.process.Child = null,
	frame_path: []const u8,
	daemon: i32 = 0,
	daemon_socket: []const u8 = "",
	daemon_shared: bool = false,
	bar_from: usize = 0,
	bar_to: usize = 0,
	layout: std.ArrayList([]const u8) = .empty,

	fn now(self: *Bench) i96 {
		return std.Io.Clock.awake.now(self.io).nanoseconds;
	}

	fn layers(self: *Bench) Layers {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();
		const allocator = arena.allocator();

		const body = hypr.requestSigned(self.io, allocator, self.inst.signature, "j/layers") catch return .{};
		const parsed = json.parse(allocator, body) catch return .{};

		if (parsed.value != .object) return .{};

		var out: Layers = .{};
		var outputs = parsed.value.object.iterator();

		while (outputs.next()) |output| {
			const levels = json.field(output.value_ptr.*, "levels") orelse continue;
			if (levels != .object) continue;

			var level_it = levels.object.iterator();
			while (level_it.next()) |level| {
				for (json.list(level.value_ptr.*)) |layer| {
					const namespace = json.textAt(layer, "namespace");

					if (std.mem.eql(u8, namespace, "tooltip")) out.tooltip = true;
					if (std.mem.eql(u8, namespace, "launcher")) out.launcher = true;

					if (std.mem.eql(u8, namespace, "quickshell")) {
						const y = json.integer(json.field(layer, "y"));
						const h = json.integer(json.field(layer, "h"));

						if (y >= 0 and h > 0) {
							out.bar_from = @intCast(y);
							out.bar_to = @intCast(y + h);
						}
					}
				}
			}
		}

		return out;
	}

	fn syncBar(self: *Bench) void {
		const found = self.layers();
		if (found.bar_to > found.bar_from) {
			self.bar_from = found.bar_from;
			self.bar_to = found.bar_to;
		}
	}

	fn hasClients(self: *Bench) bool {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();
		const allocator = arena.allocator();

		const body = hypr.requestSigned(self.io, allocator, self.inst.signature, "j/clients") catch return false;
		const parsed = json.parse(allocator, body) catch return false;

		return json.list(parsed.value).len > 0;
	}

	fn ipc(self: *Bench, target: ?[]const u8, function: []const u8) !exec.Result {
		var argv: std.ArrayList([]const u8) = .empty;
		try argv.appendSlice(self.allocator, &.{ "timeout", "20", "qs", "ipc" });

		if (target) |path| try argv.appendSlice(self.allocator, &.{ "-p", path });

		try argv.appendSlice(self.allocator, &.{ "call", "shell", function });

		return exec.runEnv(self.io, self.allocator, argv.items, self.env);
	}

	fn key(self: *Bench, code: []const u8) void {
		_ = exec.runEnv(self.io, self.allocator, &.{ "timeout", "5", "wtype", "-k", code }, self.env) catch return;
	}

	fn launcherConfig(self: *Bench) ![]const u8 {
		return std.fmt.allocPrint(self.allocator, "{s}/quickshell/launcherShell.qml", .{self.inst.worktree});
	}

	fn grab(self: *Bench) ![]const u8 {
		const result = try exec.runEnv(self.io, self.allocator, &.{ "timeout", "15", "grim", "-t", "ppm", "-o", self.inst.output, self.frame_path }, self.env);
		if (result.code != 0) return error.GrabFailed;

		return proc.readFile(self.io, self.allocator, self.frame_path);
	}

	fn stableFrame(self: *Bench) ![]const u8 {
		var previous = try self.grab();
		var waited: u64 = 0;

		while (waited < 1000) : (waited += 40) {
			const frame = try self.grab();
			if (std.mem.eql(u8, previous, frame)) return frame;

			previous = frame;
			sleep.ms(40);
		}

		return previous;
	}

	fn settle(self: *Bench) void {
		self.key("Escape");
		_ = self.ipc(null, "closeBarPopups") catch null;

		if (self.launcher > 0) {
			const config = self.launcherConfig() catch "";
			if (config.len > 0) _ = self.ipc(config, "closeLauncher") catch null;
		}

		var waited: u64 = 0;
		while (waited < 3000) : (waited += 25) {
			if (!self.layers().tooltip) break;
			sleep.ms(25);
		}

		var stable: u8 = 0;
		var previous = proc.rssKb(self.io, self.allocator, self.inst.shell);
		while (waited < 3800 and stable < 3) : (waited += 50) {
			sleep.ms(50);

			const current = proc.rssKb(self.io, self.allocator, self.inst.shell);
			stable = if (@abs(current - previous) <= 256) stable + 1 else 0;
			previous = current;
		}
	}

	fn close(self: *Bench, kind: Kind, toggle: ?[]const u8, reference: []const u8, from: usize, to: usize) bool {
		self.key("Escape");

		if (toggle) |function| _ = self.ipc(null, function) catch null;

		const limit: f64 = switch (kind) {
			.bar => 0.10,
			.launcher, .clipboard, .windows => 0.06,
			else => 0.02,
		};
		const span = 2 * @as(i96, std.time.ns_per_s);

		if (self.waitGone(kind, reference, from, to, limit, span)) return true;

		self.key("Escape");
		_ = self.ipc(null, "closeBarPopups") catch null;

		if (self.launcher > 0) {
			const config = self.launcherConfig() catch "";
			if (config.len > 0) _ = self.ipc(config, "closeLauncher") catch null;
		}

		return self.waitGone(kind, reference, from, to, limit, span);
	}

	fn waitGone(self: *Bench, kind: Kind, reference: []const u8, from: usize, to: usize, limit: f64, span: i96) bool {
		const deadline = self.now() + span;

		while (self.now() < deadline) {
			switch (kind) {
				.layer => {
					if (!self.layers().tooltip) return true;
				},
				.bar, .frame, .launcher, .clipboard, .windows => {
					const frame = self.grab() catch return false;
					if (frameDiff(reference, frame, from, to) < limit) return true;
				},
				else => return true,
			}
		}

		return false;
	}

	fn refreshDaemon(self: *Bench) void {
		const io = self.io;
		const allocator = self.allocator;

		const xdg = proc.runtimeDir(io, allocator);
		const path = std.fmt.allocPrint(allocator, "{s}/yudaemond.sock", .{xdg}) catch return;
		const home_socket = std.fmt.allocPrint(allocator, "/run/user/{d}/yudaemond.sock", .{std.os.linux.getuid()}) catch "";

		self.daemon_socket = path;
		self.daemon_shared = std.mem.eql(u8, path, home_socket);

		const buffer = allocator.alloc(u8, 1024 * 1024) catch return;
		var connection = sock.Connection.connect(path, buffer) catch return;
		defer connection.close();

		(connection.writeLine(sock.sync) catch return);

		const line = (connection.readLine() catch return) orelse return;
		const parsed = json.parse(allocator, line) catch return;
		const pid = json.integer(json.deep(parsed.value, &.{ "daemon", "pid" }));

		if (pid > 0) self.daemon = @intCast(pid);

		if (json.field(parsed.value, "bar")) |bar| {
			if (bar == .object) {
				var keys = bar.object.iterator();
				while (keys.next()) |entry| {
					for (json.list(entry.value_ptr.*)) |item| {
						const id = json.textAt(item, "id");
						if (id.len == 0) continue;
						self.layout.append(allocator, id) catch continue;
					}
				}
			}
		}
	}

	fn findLauncher(self: *Bench) ?i32 {
		const io = self.io;
		const allocator = self.allocator;
		const needle = std.fmt.allocPrint(allocator, "{s}/quickshell/launcherShell.qml", .{self.inst.worktree}) catch return null;

		var dir = std.Io.Dir.cwd().openDir(io, "/proc", .{ .iterate = true }) catch return null;
		defer dir.close(io);

		var it = dir.iterate();
		while (it.next(io) catch null) |entry| {
			const pid = std.fmt.parseInt(i32, entry.name, 10) catch continue;

			const cmdline_path = std.fmt.allocPrint(allocator, "/proc/{d}/cmdline", .{pid}) catch continue;
			const cmdline = proc.readFile(io, allocator, cmdline_path) catch continue;
			if (std.mem.indexOf(u8, cmdline, needle) == null) continue;

			const environ_path = std.fmt.allocPrint(allocator, "/proc/{d}/environ", .{pid}) catch continue;
			const block = proc.readFile(io, allocator, environ_path) catch continue;

			const wayland = proc.envFrom(block, "WAYLAND_DISPLAY") orelse continue;
			if (!std.mem.eql(u8, wayland, self.inst.wayland)) continue;

			const signature = proc.envFrom(block, "HYPRLAND_INSTANCE_SIGNATURE") orelse continue;
			if (!std.mem.eql(u8, signature, self.inst.signature)) continue;

			return pid;
		}

		return null;
	}

	fn ensureLauncher(self: *Bench) void {
		const io = self.io;

		if (self.findLauncher()) |pid| {
			self.launcher = pid;
			return;
		}

		const config = self.launcherConfig() catch return;
		self.launcher_child = std.process.spawn(io, .{
			.argv = &.{ "quickshell", "-p", config },
			.stdin = .ignore,
			.stdout = .ignore,
			.stderr = .ignore,
			.environ_map = self.env,
		}) catch return;

		self.launcher_owned = true;

		var waited: u64 = 0;
		while (waited < 15000) : (waited += 100) {
			if (self.findLauncher()) |pid| {
				self.launcher = pid;
				if (self.layers().launcher) return;
			}

			sleep.ms(100);
		}

		self.launcher = 0;
	}

	fn warmLauncher(self: *Bench) void {
		if (self.launcher == 0) return;

		const config = self.launcherConfig() catch return;

		_ = self.ipc(config, "launcher") catch null;
		sleep.ms(900);
		self.key("Escape");
		sleep.ms(400);
	}

	fn cleanup(self: *Bench, base_env: *std.process.Environ.Map, owned: bool) void {
		const io = self.io;

		if (self.launcher_owned and self.launcher > 0) {
			std.posix.kill(self.launcher, .TERM) catch {};
			if (self.launcher_child) |*child| _ = child.wait(io) catch {};
		}

		std.Io.Dir.cwd().deleteFile(io, self.frame_path) catch {};

		if (!owned) return;

		var map = base_env.clone(self.allocator) catch return;
		defer map.deinit();
		map.put("HYPR_TEST_ID", self.inst.id) catch return;

		const path = harness(io, self.allocator) catch return;
		_ = exec.runEnv(io, self.allocator, &.{ path, "stop" }, &map) catch {};
	}

	fn inLayout(self: *Bench, id: []const u8) bool {
		return layoutHas(self.layout.items, id);
	}

	fn measure(self: *Bench, spec: Spec) !report.Row {
		const io = self.io;
		const allocator = self.allocator;
		const launcher_kind = spec.kind == .launcher or spec.kind == .clipboard or spec.kind == .windows;

		self.settle();

		if (!proc.running(io, allocator, self.inst.shell)) {
			return .{ .widget = spec.id, .status = report.Status.fail, .reason = "the test instance died mid-run" };
		}

		if (self.daemon == 0 or !proc.running(io, allocator, self.daemon)) self.refreshDaemon();

		const shell_pid: i32 = if (launcher_kind) self.launcher else self.inst.shell;
		const target: ?[]const u8 = if (launcher_kind) try self.launcherConfig() else null;
		const function = if (spec.kind == .launcher) "launcher" else spec.id;
		const toggle: ?[]const u8 = if (spec.kind == .bar) function else null;

		const shell_rss_before = proc.rssKb(io, allocator, shell_pid);
		const daemon_rss_before = proc.rssKb(io, allocator, self.daemon);

		const shot = switch (spec.kind) {
			.bar, .frame, .launcher, .clipboard, .windows => true,
			else => false,
		};

		var reference: []const u8 = &.{};
		var rows_from: usize = 0;
		var rows_to: usize = std.math.maxInt(usize);
		var threshold: f64 = 0.01;

		if (shot) {
			reference = try self.stableFrame();

			if (spec.kind == .bar) {
				rows_from = self.bar_from;
				rows_to = self.bar_to;
				threshold = 0.02;
			}
		}

		const started = self.now();
		const result = self.ipc(target, function) catch null;
		const returned = self.now();

		if (result == null or result.?.code != 0) {
			_ = self.close(spec.kind, toggle, reference, rows_from, rows_to);

			return .{
				.widget = spec.id,
				.status = .fail,
				.reason = if (proc.running(io, allocator, self.inst.shell))
					"the ipc call could not be delivered"
				else
					"the test instance died mid-run",
			};
		}

		const deadline = returned + self.timeout_ns;
		var opened: i96 = 0;

		while (self.now() < deadline) {
			if (shot) {
				const frame = self.grab() catch break;
				if (frameDiff(reference, frame, rows_from, rows_to) > threshold) {
					opened = self.now();
					break;
				}
			} else if (self.layers().tooltip) {
				opened = self.now();
				break;
			}
		}

		if (opened == 0) {
			_ = self.close(spec.kind, toggle, reference, rows_from, rows_to);

			return .{ .widget = spec.id, .status = .na, .reason = spec.miss };
		}

		sleep.ms(250);

		const ticks_shell_before = proc.threadTicks(io, allocator, shell_pid);
		const ticks_daemon_before = proc.threadTicks(io, allocator, self.daemon);
		const shell_rss_open = proc.rssKb(io, allocator, shell_pid);

		var peak_shell = if (shell_rss_open > 0) shell_rss_open else shell_rss_before;
		var peak_daemon = daemon_rss_before;

		const held_from = self.now();
		while (self.now() - held_from < self.hold_ns) {
			const shell_rss = proc.rssKb(io, allocator, shell_pid);
			const daemon_rss = proc.rssKb(io, allocator, self.daemon);

			if (shell_rss > 0) peak_shell = @max(peak_shell, shell_rss);
			if (daemon_rss > 0) peak_daemon = @max(peak_daemon, daemon_rss);

			sleep.ms(20);
		}

		const held = self.now() - held_from;
		const ticks_shell_after = proc.threadTicks(io, allocator, shell_pid);
		const ticks_daemon_after = proc.threadTicks(io, allocator, self.daemon);
		const closed = self.close(spec.kind, toggle, reference, rows_from, rows_to);
		sleep.ms(300);

		var notes: std.ArrayList(u8) = .empty;
		if (spec.note.len > 0) try notes.appendSlice(allocator, spec.note);
		if (notes.items.len > 0) try notes.appendSlice(allocator, "; ");
		try notes.appendSlice(allocator, if (shot) "frame-diff signal, ~35ms" else "layer signal");
		try notes.appendSlice(allocator, "; sampled 250ms after visible");

		if (launcher_kind) try notes.print(allocator, "; launcher instance {d}", .{shell_pid});
		if (self.daemon_shared) try notes.appendSlice(allocator, "; daemon shared with the real session");

		if (shell_rss_before > 0 and peak_shell < shell_rss_before) {
			try notes.appendSlice(allocator, "; the shell freed more than the widget added");
		}
		if (!closed) try notes.appendSlice(allocator, "; did not close cleanly");

		return .{
			.widget = spec.id,
			.status = .ok,
			.openMs = @as(f64, @floatFromInt(opened - returned)) / @as(f64, std.time.ns_per_ms),
			.ipcMs = @as(f64, @floatFromInt(returned - started)) / @as(f64, std.time.ns_per_ms),
			.shellRssDeltaKb = if (shell_rss_before > 0) peak_shell - shell_rss_before else null,
			.shellCpuPct = if (ticks_shell_before > 0) fmt.round2(percent(ticks_shell_after - ticks_shell_before, held)) else null,
			.daemonRssDeltaKb = if (daemon_rss_before > 0) peak_daemon - daemon_rss_before else null,
			.daemonCpuPct = if (ticks_daemon_before > 0) fmt.round2(percent(ticks_daemon_after - ticks_daemon_before, held)) else null,
			.shellPid = shell_pid,
			.shellRssPeakKb = if (peak_shell > 0) peak_shell else null,
			.daemonRssPeakKb = if (peak_daemon > 0) peak_daemon else null,
			.notes = notes.items,
		};
	}
};

pub fn run(io: Io, args: []const []const u8) !void {
	var as_json = false;
	var hold_ms: u64 = 2500;
	var timeout_ms: u64 = 4000;
	var only: ?[]const u8 = null;
	var index: usize = 3;

	for (args[3..]) |arg| {
		if (!std.mem.eql(u8, arg, "-h") and !std.mem.eql(u8, arg, "--help")) continue;

		var buffer: [2048]u8 = undefined;
		var writer = std.Io.File.stdout().writer(io, &buffer);
		try writer.interface.writeAll(usage);
		try writer.interface.flush();

		return;
	}

	while (index < args.len) : (index += 1) {
		if (std.mem.eql(u8, args[index], "--json")) as_json = true;

		if (std.mem.eql(u8, args[index], "--hold") and index + 1 < args.len) {
			index += 1;
			hold_ms = std.fmt.parseInt(u64, args[index], 10) catch hold_ms;
		}

		if (std.mem.eql(u8, args[index], "--timeout") and index + 1 < args.len) {
			index += 1;
			timeout_ms = std.fmt.parseInt(u64, args[index], 10) catch timeout_ms;
		}

		if (std.mem.eql(u8, args[index], "--widgets") and index + 1 < args.len) {
			index += 1;
			only = args[index];
		}
	}

	var arena = std.heap.ArenaAllocator.init(gpa);
	defer arena.deinit();
	const allocator = arena.allocator();

	const existing = try discover(io, allocator);
	const inst = existing orelse try startInstance(io, allocator);
	const owned = existing == null;

	var base_env = try std.process.Environ.createMap(try environ.current(io, allocator), allocator);
	defer base_env.deinit();

	var nested = try base_env.clone(allocator);
	defer nested.deinit();
	try nested.put("HYPRLAND_INSTANCE_SIGNATURE", inst.signature);
	try nested.put("WAYLAND_DISPLAY", inst.wayland);
	try nested.put("XDG_CONFIG_HOME", inst.worktree);
	_ = nested.swapRemove("HYPR_TEST_ID");

	var bench = Bench{
		.io = io,
		.allocator = allocator,
		.inst = inst,
		.env = &nested,
		.hold_ns = @as(i96, @intCast(hold_ms)) * std.time.ns_per_ms,
		.timeout_ns = @as(i96, @intCast(timeout_ms)) * std.time.ns_per_ms,
		.frame_path = try std.fmt.allocPrint(allocator, "{s}/yudaemond-bench-widgets.ppm", .{proc.runtimeDir(io, allocator)}),
	};

	defer bench.cleanup(&base_env, owned);

	bench.ensureLauncher();
	bench.syncBar();
	bench.warmLauncher();
	bench.refreshDaemon();

	var rows: std.ArrayList(report.Row) = .empty;
	for (specs) |spec| {
		if (only) |list| if (!listed(list, spec.id)) continue;

		if (spec.kind == .control or spec.kind == .skip) {
			try rows.append(allocator, .{ .widget = spec.id, .status = .na, .reason = spec.note });
			continue;
		}

		if (bench.launcher == 0 and (spec.kind == .launcher or spec.kind == .clipboard or spec.kind == .windows)) {
			try rows.append(allocator, .{
				.widget = spec.id,
				.status = .na,
				.reason = "no launcher instance in the test session",
			});
			continue;
		}

		if (spec.kind == .layer and !bench.inLayout(spec.id)) {
			try rows.append(allocator, .{
				.widget = spec.id,
				.status = .na,
				.reason = "not in the bar layout, the shell has nothing to toggle",
			});
			continue;
		}

		if (spec.kind == .windows and !bench.hasClients()) {
			try rows.append(allocator, .{
				.widget = spec.id,
				.status = .na,
				.reason = "window switcher needs a window; the test session has none",
			});
			continue;
		}

		std.debug.print("bench widgets: {s}\n", .{spec.id});
		try rows.append(allocator, try bench.measure(spec));
	}

	const worst = report.pickWorst(rows.items);
	std.mem.sort(report.Row, rows.items, {}, report.byRank);

	const now_ms = fmt.nowMs(io);
	const stamp = try report.stamp(allocator, now_ms);
	const payload = report.Report{
		.at = try fmt.isoFromMs(allocator, now_ms),
		.instance = .{
			.id = inst.id,
			.reused = !owned,
			.shellPid = inst.shell,
			.worktree = inst.worktree,
			.signature = inst.signature,
			.wayland = inst.wayland,
		},
		.launcherPid = bench.launcher,
		.daemonPid = bench.daemon,
		.daemonSocket = bench.daemon_socket,
		.daemonShared = bench.daemon_shared,
		.holdSeconds = @as(f64, @floatFromInt(hold_ms)) / 1000.0,
		.worst = if (worst) |row| row.widget else null,
		.widgets = rows.items,
	};

	const body = try std.fmt.allocPrint(allocator, "{f}\n", .{std.json.fmt(payload, .{ .whitespace = .indent_2 })});
	const dir = try std.fmt.allocPrint(allocator, "{s}/.config/quickshell/yudaemond/bench/widgets", .{proc.home(io, allocator)});
	std.Io.Dir.cwd().createDirPath(io, dir) catch {};
	const path = try std.fmt.allocPrint(allocator, "{s}/{s}.json", .{ dir, stamp });
	proc.writeFileAtomic(io, allocator, path, body) catch {};

	var buffer: [16384]u8 = undefined;
	var writer = std.Io.File.stdout().writer(io, &buffer);
	const w = &writer.interface;

	if (as_json) {
		try w.writeAll(body);
		try w.flush();
		return finish(rows.items);
	}

	try w.print("instance {s} ({s}), shell {d}, launcher {d}, daemon {d}{s}\n", .{
		inst.id,
		if (owned) "started by this run" else "reused",
		inst.shell,
		bench.launcher,
		bench.daemon,
		if (bench.daemon_shared) " shared with the real session" else "",
	});
	try report.table(w, allocator, rows.items);

	if (worst) |row| {
		try w.print("\nworst hogger: {s} — open {d:.1}ms, shell cpu {d:.1}% rss {d}kB, daemon cpu {d:.1}% rss {d}kB\n", .{
			row.widget,
			row.openMs orelse 0,
			row.shellCpuPct orelse 0,
			row.shellRssDeltaKb orelse 0,
			row.daemonCpuPct orelse 0,
			row.daemonRssDeltaKb orelse 0,
		});
	}

	try w.print("raw run: {s}\n", .{path});
	try w.flush();

	return finish(rows.items);
}

fn finish(rows: []const report.Row) !void {
	for (rows) |row| {
		if (row.status == .fail) {
			std.debug.print("bench widgets: {s}: {s}\n", .{ row.widget, row.reason });
			std.process.exit(1);
		}
	}
}

pub fn layoutHas(layout: []const []const u8, id: []const u8) bool {
	if (layout.len == 0) return true;

	const want = if (std.mem.eql(u8, id, "calendar"))
		"clock"
	else if (std.mem.eql(u8, id, "notifications"))
		"notify"
	else
		id;

	for (layout) |entry| {
		if (std.mem.eql(u8, entry, want)) return true;
	}

	return false;
}

fn listed(list: []const u8, id: []const u8) bool {
	var it = std.mem.splitScalar(u8, list, ',');

	while (it.next()) |item| {
		if (std.mem.eql(u8, std.mem.trim(u8, item, " "), id)) return true;
	}

	return false;
}

pub fn parseState(body: []const u8, key: []const u8) ?[]const u8 {
	var lines = std.mem.splitScalar(u8, body, '\n');

	while (lines.next()) |line| {
		const trimmed = std.mem.trim(u8, line, " \r");
		const split = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
		if (!std.mem.eql(u8, trimmed[0..split], key)) continue;

		return trimmed[split + 1 ..];
	}

	return null;
}

fn discover(io: Io, allocator: Allocator) !?Instance {
	const runtime = proc.runtimeDir(io, allocator);
	const root = try std.fmt.allocPrint(allocator, "{s}/hypr-test/instances", .{runtime});
	const want = proc.env(io, allocator, "HYPR_TEST_ID");

	var found: ?Instance = null;
	var count: usize = 0;

	if (std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true })) |opened| {
		var dir = opened;
		defer dir.close(io);

		var it = dir.iterate();
		while (try it.next(io)) |entry| {
			if (entry.kind != .directory) continue;
			if (want) |id| if (!std.mem.eql(u8, id, entry.name)) continue;

			const path = try std.fmt.allocPrint(allocator, "{s}/{s}/state", .{ root, entry.name });
			const body = proc.readFile(io, allocator, path) catch continue;

			if (try fromState(io, allocator, body)) |inst| {
				found = inst;
				count += 1;
			}
		}
	} else |_| {}

	const legacy = try std.fmt.allocPrint(allocator, "{s}/hypr-test/state", .{runtime});
	if (proc.readFile(io, allocator, legacy)) |body| {
		if (try fromState(io, allocator, body)) |inst| {
			found = inst;
			count += 1;
		}
	} else |_| {}

	if (count > 1) {
		std.debug.print("bench widgets: more than one live hypr-test instance, set HYPR_TEST_ID\n", .{});
		std.process.exit(1);
	}

	return found;
}

fn fromState(io: Io, allocator: Allocator, body: []const u8) !?Instance {
	const shell = std.fmt.parseInt(i32, parseState(body, "QS_PID") orelse return null, 10) catch return null;
	if (!proc.running(io, allocator, shell)) return null;

	return .{
		.id = try allocator.dupe(u8, parseState(body, "ID") orelse "unknown"),
		.shell = shell,
		.worktree = try allocator.dupe(u8, parseState(body, "WORKTREE") orelse return null),
		.signature = try allocator.dupe(u8, parseState(body, "SIG") orelse return null),
		.wayland = try allocator.dupe(u8, parseState(body, "SOCK") orelse return null),
		.output = try allocator.dupe(u8, parseState(body, "OUTPUT") orelse "WAYLAND-1"),
	};
}

fn harness(io: Io, allocator: Allocator) ![]u8 {
	return std.fmt.allocPrint(allocator, "{s}/.config/scripts/hypr-test", .{proc.home(io, allocator)});
}

fn startInstance(io: Io, allocator: Allocator) !Instance {
	const path = try harness(io, allocator);
	const runtime = proc.runtimeDir(io, allocator);

	var map = std.process.Environ.createMap(try environ.current(io, allocator), allocator) catch return error.StartFailed;

	if (map.get("WAYLAND_DISPLAY")) |display| {
		const socket = std.fmt.allocPrint(allocator, "{s}/{s}", .{ runtime, display }) catch "";
		if (socket.len == 0 or !proc.exists(io, socket)) _ = map.swapRemove("WAYLAND_DISPLAY");
	}

	const result = exec.runEnv(io, allocator, &.{ path, "start" }, &map) catch |err| {
		std.debug.print("bench widgets: could not run hypr-test: {s}\n", .{@errorName(err)});
		std.process.exit(1);
	};

	if (result.code != 0) {
		dumpHarnessLog(io, allocator, runtime);
		std.debug.print("bench widgets: hypr-test start failed: {s}\n", .{std.mem.trim(u8, result.out, " \n")});
		std.process.exit(1);
	}

	return (try discover(io, allocator)) orelse {
		std.debug.print("bench widgets: hypr-test start reported success but no instance is live\n", .{});
		std.process.exit(1);
	};
}

fn dumpHarnessLog(io: Io, allocator: Allocator, runtime: []const u8) void {
	const id = proc.env(io, allocator, "HYPR_TEST_ID") orelse "legacy";
	const log = std.fmt.allocPrint(allocator, "{s}/hypr-test/instances/{s}/hyprland.log", .{ runtime, id }) catch return;
	const body = proc.readFile(io, allocator, log) catch return;

	var lines: usize = 0;
	var it = std.mem.splitScalar(u8, body, '\n');
	while (it.next()) |_| lines += 1;

	var skip = lines -| 12;
	it = std.mem.splitScalar(u8, body, '\n');
	while (it.next()) |line| {
		if (skip > 0) {
			skip -= 1;
			continue;
		}

		if (line.len > 0) std.debug.print("  {s}\n", .{line});
	}
}

fn percent(ticks: i64, elapsed_ns: i96) f64 {
	if (ticks <= 0 or elapsed_ns <= 0) return 0;

	const seconds = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, std.time.ns_per_s);

	return @as(f64, @floatFromInt(ticks)) / 100.0 / seconds * 100.0;
}

pub fn ppmInfo(body: []const u8) ?Ppm {
	if (!std.mem.startsWith(u8, body, "P6")) return null;

	var values: [3]usize = undefined;
	var index: usize = 2;

	for (&values) |*slot| {
		while (index < body.len and std.ascii.isWhitespace(body[index])) index += 1;

		const start = index;
		while (index < body.len and !std.ascii.isWhitespace(body[index])) index += 1;

		slot.* = std.fmt.parseInt(usize, body[start..index], 10) catch return null;
	}

	if (index >= body.len) return null;

	return .{ .w = values[0], .h = values[1], .off = index + 1 };
}

pub fn frameDiff(a: []const u8, b: []const u8, from: usize, to: usize) f64 {
	const left = ppmInfo(a) orelse return 1;
	const right = ppmInfo(b) orelse return 1;

	const height = @min(left.h, right.h);
	const top = @min(from, height);
	const bottom = @min(to, height);
	const rows = if (bottom > top) bottom - top else 0;

	const left_start = left.off + top * left.w * 3;
	const right_start = right.off + top * right.w * 3;
	const span = if (rows == 0) 0 else @min(rows * @min(left.w, right.w) * 3, @min(a.len -| left_start, b.len -| right_start));

	if (span == 0) return 1;

	const step = @max(@as(usize, 1), span / 7000);

	var seen: usize = 0;
	var changed: usize = 0;
	var index: usize = 0;

	while (index + 2 < span) : (index += step) {
		seen += 1;

		if (a[left_start + index] != b[right_start + index] or
			a[left_start + index + 1] != b[right_start + index + 1] or
			a[left_start + index + 2] != b[right_start + index + 2]) changed += 1;
	}

	if (seen == 0) return 1;

	return @as(f64, @floatFromInt(changed)) / @as(f64, @floatFromInt(seen));
}

test "state parsing reads the fields hypr-test writes" {
	const body = "ID=1-2\nOWNER=gabriel\nQS_PID=4242\nSIG=abc_1_2\nWORKTREE=/tmp/w\nOUTPUT=WAYLAND-1\n";

	try std.testing.expectEqualStrings("4242", parseState(body, "QS_PID").?);
	try std.testing.expectEqualStrings("abc_1_2", parseState(body, "SIG").?);
	try std.testing.expectEqualStrings("/tmp/w", parseState(body, "WORKTREE").?);
	try std.testing.expect(parseState(body, "MISSING") == null);
	try std.testing.expect(parseState("NOPE\n", "QS_PID") == null);
}

test "ppm header and frame diff" {
	const header = "P6\n4 2\n255\n";
	var a: [header.len + 24]u8 = undefined;
	@memcpy(a[0..header.len], header);
	@memset(a[header.len..], 10);

	try std.testing.expectEqual(@as(f64, 0), frameDiff(&a, &a, 0, 2));

	var b = a;
	b[header.len + 3] = 200;
	try std.testing.expect(frameDiff(&a, &b, 0, 2) > 0);

	const info = ppmInfo(&a).?;
	try std.testing.expectEqual(@as(usize, 4), info.w);
	try std.testing.expectEqual(@as(usize, 2), info.h);
	try std.testing.expectEqual(@as(usize, header.len), info.off);
	try std.testing.expect(ppmInfo("P3\n1 1\n255\n") == null);
}

test "a window outside the frame is an empty region" {
	const header = "P6\n2 2\n255\n";
	var a: [header.len + 12]u8 = undefined;
	@memcpy(a[0..header.len], header);
	@memset(a[header.len..], 5);

	try std.testing.expectEqual(@as(f64, 1), frameDiff(&a, &a, 5, 9));
}

test "cpu percent is over the elapsed hold" {
	try std.testing.expectEqual(@as(f64, 50), percent(100, 2 * std.time.ns_per_s));
	try std.testing.expectEqual(@as(f64, 0), percent(0, std.time.ns_per_s));
	try std.testing.expectEqual(@as(f64, 0), percent(50, 0));
}

test "the bar layout decides which widgets can open" {
	const layout = [_][]const u8{ "workspaces", "notify", "clock", "weather", "tray", "cpu", "display" };

	try std.testing.expect(layoutHas(&layout, "calendar"));
	try std.testing.expect(layoutHas(&layout, "notifications"));
	try std.testing.expect(layoutHas(&layout, "cpu"));
	try std.testing.expect(!layoutHas(&layout, "github"));
	try std.testing.expect(!layoutHas(&layout, "power"));
	try std.testing.expect(layoutHas(&[_][]const u8{}, "anything"));
}

test "the widget list matches the shell entry points" {
	const expected = [_][]const u8{
		"launcher",       "clipboard",   "windows", "windowsStep",   "cpu",      "memory",
		"volume",         "calendar",    "weather", "notifications", "github",   "media",
		"network",        "speedtest",   "bareBar", "killPopups",    "killPopupsLocal",
		"closeBarPopups", "closeLauncher", "display", "agent",       "power",    "powerMenu",
		"tray",           "wallpaper",
	};

	try std.testing.expectEqual(expected.len, specs.len);

	for (expected) |id| {
		var found = false;
		for (specs) |spec| {
			if (std.mem.eql(u8, spec.id, id)) found = true;
		}
		try std.testing.expect(found);
	}
}
