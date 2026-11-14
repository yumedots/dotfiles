const std = @import("std");
const hubmod = @import("../hub.zig");
const proc = @import("../primitives/proc.zig");
const json = @import("../primitives/json.zig");
const fmt = @import("../primitives/fmt.zig");
const sleep = @import("../primitives/sleep.zig");
const exec = @import("../primitives/exec.zig");
const qmp = @import("vms/qmp.zig");
const vsock = @import("vms/vsock.zig");
const qemu = @import("vms/qemu.zig");
const images = @import("vms/images.zig");
const budget = @import("vms/budget.zig");
const tiers = @import("vms/tiers.zig");
const input = @import("vms/input.zig");
const cgroup = @import("vms/cgroup.zig");
const opencode = @import("opencode.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;

const Vm = struct {
	name: []u8,
	dir: []u8,
	disk: []u8,
	agent: []u8,
	controller: []u8,
	harness: []u8,
	session: []u8,
	session_title: []u8 = &.{},
	agent_since_ms: i64 = 0,
	last_call_ms: i64 = 0,
	thumb: bool = false,
	thumb_ms: i64 = 0,
	screen_w: u32 = 0,
	screen_h: u32 = 0,
	cid: u32,
	cores: u32,
	mem_mb: u32,
	gl: bool,
	tier: tiers.Tier = .off,
	pid: i32 = 0,
	vfs_pid: i32 = 0,
	wall_pid: i32 = 0,
	pump_pid: i32 = 0,
	qmp: ?*qmp.Qmp = null,
	qemu_child: ?std.process.Child = null,
	vfs_child: ?std.process.Child = null,
	wall_child: ?std.process.Child = null,
	pump_child: ?std.process.Child = null,
	cgroup: ?cgroup.Cgroup = null,
	created_ms: i64,
	used_ms: i64,
	destroy_ms: i64 = 0,
	cpu_ticks: u64 = 0,
	cpu_ms: i64 = 0,
	cpu_pct: f64 = 0,
	rss_kb: u64 = 0,
};


fn writeVm(writer: *Writer, vm: *const Vm, now: i64) !void {
	try writer.writeAll("{\"name\":");
	try std.json.Stringify.encodeJsonString(vm.name, .{}, writer);
	try writer.writeAll(",\"tier\":");
	try std.json.Stringify.encodeJsonString(vm.tier.text(), .{}, writer);
	try writer.print(",\"cid\":{d},\"pid\":{d},\"cores\":{d},\"memMb\":{d},\"gl\":{s},\"cpu\":{d:.1},\"rssKb\":{d},\"agent\":", .{
		vm.cid,
		vm.pid,
		vm.cores,
		vm.mem_mb,
		if (vm.gl) "true" else "false",
		vm.cpu_pct,
		vm.rss_kb,
	});
	try std.json.Stringify.encodeJsonString(vm.agent, .{}, writer);
	try writer.writeAll(",\"controller\":");
	try std.json.Stringify.encodeJsonString(vm.controller, .{}, writer);
	try writer.writeAll(",\"harness\":");
	try std.json.Stringify.encodeJsonString(vm.harness, .{}, writer);
	try writer.writeAll(",\"session\":");
	try std.json.Stringify.encodeJsonString(vm.session, .{}, writer);
	try writer.writeAll(",\"sessionTitle\":");
	try std.json.Stringify.encodeJsonString(vm.session_title, .{}, writer);
	try writer.print(",\"agentSinceMs\":{d},\"lastCallMs\":{d},\"thumb\":{s},\"thumbAt\":{d},\"lastUsed\":{d},\"upMs\":{d}}}", .{ vm.agent_since_ms, vm.last_call_ms, if (vm.thumb) "true" else "false", vm.thumb_ms, vm.used_ms, now - vm.created_ms });
}

pub const Vms = struct {
	allocator: Allocator,
	io: Io,
	hub: *hubmod.Hub,
	mutex: std.Io.Mutex = .init,
	op: std.Io.Mutex = .init,
	list: std.ArrayList(*Vm) = .empty,
	selected: []u8 = &.{},
	opencode: ?*opencode.Opencode = null,
	limit: budget.Budget,

	pub fn create(allocator: Allocator, io: Io, hub: *hubmod.Hub) !*Vms {
		const self = try allocator.create(Vms);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.limit = budget.detect(io, allocator),
		};

		self.recover();

		const thread = try std.Thread.spawn(.{}, governorLoop, .{self});
		thread.detach();

		return self;
	}

	pub fn attachOpencode(self: *Vms, client: *opencode.Opencode) void {
		self.opencode = client;
	}

	pub const Info = struct {
		name: []const u8,
		tier: tiers.Tier,
		mem_mb: u32,
		cores: u32,
		gl: bool,
	};

	pub fn info(self: *Vms, allocator: Allocator) ![]Info {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		var out: std.ArrayList(Info) = .empty;

		for (self.list.items) |vm| {
			try out.append(allocator, .{
				.name = try allocator.dupe(u8, vm.name),
				.tier = vm.tier,
				.mem_mb = vm.mem_mb,
				.cores = vm.cores,
				.gl = vm.gl,
			});
		}

		return out.toOwnedSlice(allocator);
	}

	pub fn provider(self: *Vms) hubmod.Provider {
		return .{ .key = "vms", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Vms = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	fn render(self: *Vms, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		const now = fmt.nowMs(self.io);
		var used_mem: u64 = 0;
		var used_cores: u64 = 0;
		var gl_count: u32 = 0;

		for (self.list.items) |vm| {
			if (vm.tier == .off) continue;

			used_mem += vm.mem_mb;
			used_cores += vm.cores;
			if (vm.gl) gl_count += 1;

			if (vm.pid > 0 and vm.tier != .off) {
				const sample = if (vm.cgroup) |group|
					group.sample(self.io, self.allocator)
				else
					cgroup.sampleProc(self.io, self.allocator, vm.pid);

				if (vm.cpu_ms > 0 and now > vm.cpu_ms) {
					const delta = sample.cpu_ticks -| vm.cpu_ticks;
					vm.cpu_pct = @as(f64, @floatFromInt(delta)) / @as(f64, @floatFromInt(now - vm.cpu_ms)) * 100.0;
				}

				vm.cpu_ticks = sample.cpu_ticks;
				vm.cpu_ms = now;
				vm.rss_kb = sample.rss_kb;
			}
		}

		try writer.print("{{\"budget\":{{\"memMb\":{d},\"cores\":{d},\"usedMemMb\":{d},\"usedCores\":{d},\"gl\":{d},\"maxGl\":{d}}},\"selected\":", .{
			self.limit.mem_mb,
			self.limit.cores,
			used_mem,
			used_cores,
			gl_count,
			@max(self.limit.cores / 2, 1),
		});
		try std.json.Stringify.encodeJsonString(self.selected, .{}, writer);
		try writer.writeAll(",\"list\":[");

		for (self.list.items, 0..) |vm, index| {
			if (index > 0) try writer.writeAll(",");
			try writeVm(writer, vm, now);
		}

		try writer.writeAll("]}");
	}

	pub fn call(self: *Vms, method: []const u8, args: json.Value, allocator: Allocator) anyerror![]u8 {
		const name = json.textAt(args, "name");

		if (name.len > 0) {
			const wakeable = std.mem.eql(u8, method, "exec") or std.mem.eql(u8, method, "state") or
				std.mem.eql(u8, method, "screenshot") or std.mem.eql(u8, method, "key") or
				std.mem.eql(u8, method, "type") or std.mem.eql(u8, method, "click") or
				std.mem.eql(u8, method, "move") or std.mem.eql(u8, method, "wait") or
				std.mem.eql(u8, method, "wake") or std.mem.eql(u8, method, "view") or
				std.mem.eql(u8, method, "gui") or std.mem.eql(u8, method, "scroll");

			if (wakeable) self.wakeForCall(name);
		}

		if (std.mem.eql(u8, method, "create")) return self.createVm(args, allocator);
		if (std.mem.eql(u8, method, "start")) return self.startVm(args, allocator);
		if (std.mem.eql(u8, method, "list")) return self.listJson(allocator);
		if (std.mem.eql(u8, method, "destroy")) return self.destroyVm(args, allocator);
		if (std.mem.eql(u8, method, "stop")) return self.stopVm(args, allocator);
		if (std.mem.eql(u8, method, "sleep")) return self.sleepVm(args, allocator);
		if (std.mem.eql(u8, method, "park")) return self.parkVm(args, allocator);
		if (std.mem.eql(u8, method, "wake")) return self.wakeVm(args, allocator);
		if (std.mem.eql(u8, method, "exec")) return self.execVm(args, allocator);
		if (std.mem.eql(u8, method, "state")) return self.stateVm(args, allocator);
		if (std.mem.eql(u8, method, "screenshot")) return self.screenshotVm(args, allocator);
		if (std.mem.eql(u8, method, "key")) return self.keyVm(args, allocator);
		if (std.mem.eql(u8, method, "type")) return self.typeVm(args, allocator);
		if (std.mem.eql(u8, method, "click")) return self.clickVm(args, allocator);
		if (std.mem.eql(u8, method, "move")) return self.moveVm(args, allocator);
		if (std.mem.eql(u8, method, "wait")) return self.waitVm(args, allocator);
		if (std.mem.eql(u8, method, "snapshot")) return self.snapshotVm(args, allocator);
		if (std.mem.eql(u8, method, "restore")) return self.restoreVm(args, allocator);
		if (std.mem.eql(u8, method, "fork")) return self.forkVm(args, allocator);
		if (std.mem.eql(u8, method, "view")) return self.viewVm(args, allocator);
		if (std.mem.eql(u8, method, "agent")) return self.agentVm(args, allocator);
		if (std.mem.eql(u8, method, "app")) return self.openApp(allocator);
		if (std.mem.eql(u8, method, "select")) return self.selectVm(args, allocator);
		if (std.mem.eql(u8, method, "ui")) return self.uiVm(args, allocator);
		if (std.mem.eql(u8, method, "gui")) return self.guiVm(args, allocator);
		if (std.mem.eql(u8, method, "config")) return self.configVm(args, allocator);
		if (std.mem.eql(u8, method, "scroll")) return self.scrollVm(args, allocator);
		if (std.mem.eql(u8, method, "release")) return self.releaseVm(args, allocator);
		if (std.mem.eql(u8, method, "push")) return self.pushVm(args, allocator);
		if (std.mem.eql(u8, method, "pull")) return self.pullVm(args, allocator);
		if (std.mem.eql(u8, method, "ui_tree")) return self.uiTreeVm(args, allocator);
		if (std.mem.eql(u8, method, "run_scenario")) return self.scenarioVm(args, allocator);

		return error.UnknownMethod;
	}


	fn wakeForCall(self: *Vms, name: []const u8) void {
		self.mutex.lockUncancelable(self.io);
		const vm = self.findLocked(name) orelse {
			self.mutex.unlock(self.io);
			return;
		};

		const previous = vm.tier;
		if (previous == .off) {
			self.mutex.unlock(self.io);
			return;
		}

		vm.tier = .hot;
		vm.used_ms = fmt.nowMs(self.io);
		const client = vm.qmp;
		const cid = vm.cid;
		self.mutex.unlock(self.io);

		if (client) |qmp_client| {
			_ = qmp_client.execute(null, "balloon", "{\"value\":0}") catch {};
			_ = qmp_client.execute(null, "cont", null) catch {};
		}

		if (previous == .warm or previous == .parked) self.syncGuestClock(cid);
	}

	fn pidAlive(self: *Vms, pid: i32) bool {
		if (pid <= 0) return false;

		var buffer: [64]u8 = undefined;
		const path = std.fmt.bufPrint(&buffer, "/proc/{d}/stat", .{pid}) catch return false;
		const body = proc.readFile(self.io, self.allocator, path) catch return false;
		defer self.allocator.free(body);

		const close = std.mem.lastIndexOfScalar(u8, body, ')') orelse return false;
		if (close + 2 >= body.len) return false;

		const state = body[close + 2];
		return state != 'Z' and state != 'X';
	}

	fn syncGuestClock(self: *Vms, cid: u32) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();
		const allocator = arena.allocator();
		const command = std.fmt.allocPrint(allocator, "sudo -n date -s \"@{d}\" >/dev/null 2>&1 || true", .{@divTrunc(fmt.nowMs(self.io), 1000)}) catch return;

		_ = self.guestExec(cid, &.{ "sh", "-lc", command }, allocator) catch return;
	}

	fn governorLoop(self: *Vms) void {
		while (true) {
			sleep.ms(5000);
			self.govern();
		}
	}

	fn govern(self: *Vms) void {
		const now = fmt.nowMs(self.io);
		const hot_idle: i64 = 300000;
		const warm_idle: i64 = 900000;
		const parked_idle: i64 = 3600000;
		var changed = false;
		var doomed: std.ArrayListUnmanaged([]u8) = .empty;
		defer doomed.deinit(self.allocator);

		self.mutex.lockUncancelable(self.io);

		for (self.list.items) |vm| {
			if (vm.tier != .off and !self.pidAlive(vm.pid)) {
				self.haltVm(vm);
				changed = true;
				continue;
			}

			if (std.mem.eql(u8, vm.controller, "human") and now - vm.used_ms > 600000) {
				vm.controller = self.allocator.dupe(u8, "agent") catch vm.controller;
				changed = true;
			}

			if (vm.tier == .hot and now - vm.used_ms > hot_idle and vm.cpu_pct < 1.0) {
				vm.tier = .warm;
				vm.used_ms = now;
				changed = true;

				if (vm.qmp) |client| {
					_ = client.execute(null, "stop", null) catch {};
					var buffer: [128]u8 = undefined;
					const body = std.fmt.bufPrint(&buffer, "{{\"value\":{d}}}", .{balloonBytes(vm.mem_mb)}) catch continue;
					_ = client.execute(null, "balloon", body) catch {};
				}
			} else if (vm.tier == .warm and now - vm.used_ms > warm_idle) {
				vm.tier = .parked;
				vm.used_ms = now;
				changed = true;
				if (vm.cgroup) |group| group.park(self.io, self.allocator);
			} else if (vm.tier == .parked and now - vm.used_ms > parked_idle) {
				vm.tier = .off;
				vm.used_ms = now;
				changed = true;

				if (vm.qmp) |client| {
					_ = client.execute(null, "quit", null) catch {};
					client.close();
					vm.qmp = null;
				}

				if (vm.pid > 0) kill(vm.pid);
				if (vm.vfs_pid > 0) kill(vm.vfs_pid);

				if (vm.qemu_child) |*child| {
					_ = child.wait(self.io) catch {};
					vm.qemu_child = null;
				}

				if (vm.vfs_child) |*child| {
					_ = child.wait(self.io) catch {};
					vm.vfs_child = null;
				}

				if (vm.cgroup) |group| group.destroy(self.io);

				vm.cgroup = null;
				vm.pid = 0;
				vm.vfs_pid = 0;
			}

			if (idleDestroy(vm.destroy_ms, vm.used_ms, now)) {
				const copy = self.allocator.dupe(u8, vm.name) catch continue;
				doomed.append(self.allocator, copy) catch self.allocator.free(copy);
			}
		}

		self.mutex.unlock(self.io);

		for (doomed.items) |name| {
			_ = self.removeVm(name, self.allocator) catch {};
			self.allocator.free(name);
		}

		if (changed) self.hub.publish();
	}

	fn createVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		self.op.lockUncancelable(self.io);
		defer self.op.unlock(self.io);

		const name = try self.vmName(args);
		const from = json.textAt(args, "from");

		if (!validName(name)) return error.BadName;

		self.mutex.lockUncancelable(self.io);

		const session = json.textAt(args, "session");

		if (self.findLocked(name)) |existing| {
			const same = session.len > 0 and std.mem.eql(u8, existing.session, session);
			if (!same) {
				self.mutex.unlock(self.io);
				return error.NameTaken;
			}

			const boot = existing.tier == .off;
			existing.used_ms = fmt.nowMs(self.io);
			self.mutex.unlock(self.io);

			if (boot) {
				self.bootVm(existing) catch |err| {
					self.cleanupVm(existing);
					return err;
				};
				self.hub.publish();
			}

			return std.fmt.allocPrint(allocator, "{{\"name\":\"{s}\",\"cid\":{d},\"pid\":{d},\"reused\":true}}", .{ existing.name, existing.cid, existing.pid });
		}

		const mem = self.memOf(args);
		const cores = self.coresOf(args);
		const gl = if (json.field(args, "gl")) |value| switch (value) {
			.bool => |flag| flag,
			else => true,
		} else true;

		if (self.usedMemLocked() + mem > self.limit.mem_mb) {
			self.mutex.unlock(self.io);
			return error.BudgetFull;
		}
		if (self.usedCoresLocked() + cores > self.limit.cores) {
			self.mutex.unlock(self.io);
			return error.BudgetFull;
		}
		if (gl and self.glCountLocked() >= @max(self.limit.cores / 2, 1)) {
			self.mutex.unlock(self.io);
			return error.GlBudgetFull;
		}

		const cid = self.nextCidLocked();
		self.mutex.unlock(self.io);

		const vm = try self.allocator.create(Vm);
		const dir = try std.fs.path.join(self.allocator, &.{ proc.repo(self.io, self.allocator), "vm", "runs", name });
		const disk = if (from.len > 0) blk: {
			if (self.diskOf(from) != null) break :blk try self.cloneDisk(name, from);
			break :blk images.overlayFrom(self.io, self.allocator, name, from) catch return error.NotFound;
		} else try images.overlay(self.io, self.allocator, name);

		vm.* = .{
			.name = try self.allocator.dupe(u8, name),
			.dir = dir,
			.disk = disk,
			.agent = try self.allocator.dupe(u8, json.textAt(args, "agent")),
			.controller = try self.allocator.dupe(u8, "agent"),
			.harness = try self.allocator.dupe(u8, json.textAt(args, "harness")),
			.session = try self.allocator.dupe(u8, json.textAt(args, "session")),
			.cid = cid,
			.cores = cores,
			.mem_mb = mem,
			.gl = gl,
			.tier = .off,
			.created_ms = fmt.nowMs(self.io),
			.used_ms = fmt.nowMs(self.io),
			.destroy_ms = destroyIdleOf(args),
		};

		self.bootVm(vm) catch |err| {
			self.cleanupVm(vm);
			return err;
		};

		self.mutex.lockUncancelable(self.io);
		try self.list.append(self.allocator, vm);
		self.mutex.unlock(self.io);

		self.hub.publish();

		return std.fmt.allocPrint(allocator, "{{\"name\":\"{s}\",\"cid\":{d},\"pid\":{d}}}", .{ vm.name, vm.cid, vm.pid });
	}

	fn startVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		self.op.lockUncancelable(self.io);
		defer self.op.unlock(self.io);

		const name = json.textAt(args, "name");

		self.mutex.lockUncancelable(self.io);
		const vm = self.findLocked(name) orelse {
			self.mutex.unlock(self.io);
			return error.NotFound;
		};
		const boot = vm.tier == .off;
		self.mutex.unlock(self.io);

		if (boot) {
			self.bootVm(vm) catch |err| {
				self.cleanupVm(vm);
				return err;
			};
			self.hub.publish();
		}

		return std.fmt.allocPrint(allocator, "{{\"name\":\"{s}\",\"cid\":{d},\"pid\":{d}}}", .{ vm.name, vm.cid, vm.pid });
	}

	fn wallpaperDir(self: *Vms, repo: []const u8) []const u8 {
		const path = std.fs.path.join(self.allocator, &.{ repo, "shell", "cache", "settings.lua" }) catch return "";
		defer self.allocator.free(path);

		const body = proc.readFile(self.io, self.allocator, path) catch return "";
		defer self.allocator.free(body);

		const marker = "wallpaper = \"";
		const start = std.mem.indexOf(u8, body, marker) orelse return "";
		const rest = body[start + marker.len ..];
		const end = std.mem.indexOfScalar(u8, rest, '"') orelse return "";
		const file = rest[0..end];
		if (file.len == 0) return "";
		const slash = std.mem.lastIndexOfScalar(u8, file, '/') orelse return "";
		return self.allocator.dupe(u8, file[0..slash]) catch "";
	}

	fn syncDesktop(self: *Vms) void {
		const repo = proc.repo(self.io, self.allocator);
		const script = std.fmt.allocPrint(self.allocator, "{s}/vm/desktop-sync", .{repo}) catch return;
		defer self.allocator.free(script);

		if (exec.run(self.io, self.allocator, &.{ "bash", script })) |result| {
			result.deinit(self.allocator);
		} else |_| {}
	}

	fn applyDesktop(self: *Vms, vm: *Vm) void {
		const repo = proc.repo(self.io, self.allocator);
		const script = std.fmt.allocPrint(self.allocator, "{s}/vm/desktop", .{repo}) catch return;
		defer self.allocator.free(script);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		if (self.guestExec(vm.cid, &.{ "bash", script }, arena.allocator())) |result| {
			_ = result;
		} else |_| {}
	}

	fn bootVm(self: *Vms, vm: *Vm) !void {
		self.syncDesktop();
		try std.Io.Dir.cwd().createDirPath(self.io, vm.dir);

		const repo = proc.repo(self.io, self.allocator);
		const vfs_socket = try std.fs.path.join(self.allocator, &.{ vm.dir, "virtiofsd.sock" });
		const vfs_args = [_][]const u8{
			"/usr/lib/virtiofsd",
			try std.fmt.allocPrint(self.allocator, "--socket-path={s}", .{vfs_socket}),
			try std.fmt.allocPrint(self.allocator, "--shared-dir={s}", .{repo}),
			"--readonly",
			"--cache=never",
		};

		const vfs = exec.spawn(self.io, .{
			.argv = &vfs_args,
			.stdin = .ignore,
			.stdout = .ignore,
			.stderr = .ignore,
		}) catch return error.VirtiofsSpawnFailed;
		vm.vfs_pid = vfs.id orelse 0;
		vm.vfs_child = vfs;

		if (!try waitFile(self.io, vfs_socket, 5000)) return error.VirtiofsSocket;

		const wall_dir = self.wallpaperDir(repo);
		defer if (wall_dir.len > 0) self.allocator.free(wall_dir);

		var share_wall = wall_dir.len > 0;
		if (share_wall) {
			const wall_socket = try std.fs.path.join(self.allocator, &.{ vm.dir, "wallpaper.sock" });
			std.Io.Dir.cwd().deleteFile(self.io, wall_socket) catch {};
			const wall_args = [_][]const u8{
				"/usr/lib/virtiofsd",
				try std.fmt.allocPrint(self.allocator, "--socket-path={s}", .{wall_socket}),
				try std.fmt.allocPrint(self.allocator, "--shared-dir={s}", .{wall_dir}),
				"--readonly",
				"--cache=never",
			};
			const wall = exec.spawn(self.io, .{
				.argv = &wall_args,
				.stdin = .ignore,
				.stdout = .ignore,
				.stderr = .ignore,
			}) catch null;
			if (wall) |child| {
				vm.wall_pid = child.id orelse 0;
				vm.wall_child = child;
				if (!try waitFile(self.io, wall_socket, 5000)) {
					self.stopWall(vm);
					share_wall = false;
				}
			} else {
				share_wall = false;
			}
		}

		const argv = try qemu.args(self.allocator, .{
			.name = vm.name,
			.dir = vm.dir,
			.disk = vm.disk,
			.dotfiles = repo,
			.wallpaper_dir = if (share_wall) wall_dir else "",
			.cores = vm.cores,
			.mem_mb = vm.mem_mb,
			.cid = vm.cid,
			.gl = vm.gl,
		});

		const qmp_path = try std.fs.path.join(self.allocator, &.{ vm.dir, "qmp.sock" });
		std.Io.Dir.cwd().deleteFile(self.io, qmp_path) catch {};

		const child = exec.spawn(self.io, .{
			.argv = argv,
			.stdin = .ignore,
			.stdout = .ignore,
			.stderr = .inherit,
		}) catch return error.QemuSpawnFailed;
		vm.pid = child.id orelse 0;
		vm.qemu_child = child;

		const group = cgroup.Cgroup.create(self.io, self.allocator, vm.name, vm.mem_mb, vm.cores) catch |err| blk: {
			std.debug.print("cgroup {s}: {s}\n", .{ vm.name, @errorName(err) });
			break :blk null;
		};

		if (group) |value| {
			value.attach(self.io, vm.pid);
			value.attach(self.io, vm.vfs_pid);
			if (vm.wall_pid > 0) value.attach(self.io, vm.wall_pid);
			vm.cgroup = value;
		}

		const pidfile = try std.fs.path.join(self.allocator, &.{ vm.dir, "qemu.pid" });
		const pid_text = try std.fmt.allocPrint(self.allocator, "{d}\n", .{vm.pid});
		proc.writeFile(self.io, pidfile, pid_text) catch {};

		const socket = try std.fs.path.join(self.allocator, &.{ vm.dir, "qmp.sock" });
		if (!try waitFile(self.io, socket, 10000)) return error.QmpSocket;

		const client = try self.allocator.create(qmp.Qmp);
		try client.init(socket);

		vm.qmp = client;
		vm.tier = .hot;
		vm.used_ms = fmt.nowMs(self.io);
		self.writeMeta(vm);

		self.startPump(vm);

		const boot_name = self.allocator.dupe(u8, vm.name) catch null;
		const agent = if (boot_name) |name|
			std.Thread.spawn(.{}, agentBoot, .{ self, vm.cid, name }) catch null
		else
			null;
		if (agent) |thread| {
			thread.detach();
		} else if (boot_name) |name| {
			self.allocator.free(name);
		}
	}

	fn recover(self: *Vms) void {
		const runs = std.fs.path.join(self.allocator, &.{ proc.repo(self.io, self.allocator), "vm", "runs" }) catch return;
		var dir = std.Io.Dir.cwd().openDir(self.io, runs, .{ .iterate = true }) catch return;
		defer dir.close(self.io);

		var iterator = dir.iterate();

		while (iterator.next(self.io) catch null) |entry| {
			if (entry.kind != .directory) continue;

			const meta_path = std.fs.path.join(self.allocator, &.{ runs, entry.name, "vm.json" }) catch continue;
			const body = proc.readFile(self.io, self.allocator, meta_path) catch continue;

			var arena = std.heap.ArenaAllocator.init(self.allocator);
			const parsed = json.parse(arena.allocator(), body) catch {
				arena.deinit();
				continue;
			};

			const name = json.textAt(parsed.value, "name");
			const pid: i32 = @intCast(json.integer(json.field(parsed.value, "pid")));
			if (name.len == 0) {
				arena.deinit();
				continue;
			}

			const vm = self.allocator.create(Vm) catch {
				arena.deinit();
				continue;
			};

			const alive = pid > 0 and proc.exists(self.io, std.fmt.allocPrint(self.allocator, "/proc/{d}", .{pid}) catch "");
			const dir_path = std.fs.path.join(self.allocator, &.{ runs, entry.name }) catch {
				arena.deinit();
				continue;
			};

			vm.* = .{
				.name = self.allocator.dupe(u8, name) catch {
					arena.deinit();
					continue;
				},
				.dir = dir_path,
				.disk = std.fs.path.join(self.allocator, &.{ dir_path, "disk.qcow2" }) catch "",
				.agent = self.allocator.dupe(u8, json.textAt(parsed.value, "agent")) catch "",
				.controller = self.allocator.dupe(u8, "agent") catch "",
				.harness = self.allocator.dupe(u8, json.textAt(parsed.value, "harness")) catch "",
				.session = self.allocator.dupe(u8, json.textAt(parsed.value, "session")) catch "",
				.session_title = self.allocator.dupe(u8, json.textAt(parsed.value, "sessionTitle")) catch "",
				.cid = @intCast(@max(json.integer(json.field(parsed.value, "cid")), 3)),
				.cores = @intCast(@max(json.integer(json.field(parsed.value, "cores")), 1)),
				.mem_mb = @intCast(@max(json.integer(json.field(parsed.value, "memMb")), 512)),
				.gl = json.flag(parsed.value, "gl"),
				.tier = if (alive) .hot else .off,
				.pid = if (alive) pid else 0,
				.created_ms = fmt.nowMs(self.io),
				.used_ms = fmt.nowMs(self.io),
				.destroy_ms = if (json.field(parsed.value, "destroyMs")) |value| @max(json.integer(value), 0) else idleDestroyDefault(),
			};

			const thumb_path = std.fs.path.join(self.allocator, &.{ vm.dir, "thumb.jpg" }) catch "";
			if (thumb_path.len > 0) {
				if (std.Io.Dir.cwd().statFile(self.io, thumb_path, .{})) |stat| {
					vm.thumb = true;
					vm.thumb_ms = @intCast(@divTrunc(stat.mtime.nanoseconds, std.time.ns_per_ms));
				} else |_| {}
			}

			if (alive) {
				const socket = std.fs.path.join(self.allocator, &.{ vm.dir, "qmp.sock" }) catch "";
				const client = self.allocator.create(qmp.Qmp) catch null;

				if (client) |value| {
					value.init(socket) catch {
						vm.tier = .off;
						vm.pid = 0;
					};

					if (vm.tier == .hot) vm.qmp = value;
				}

				vm.cgroup = cgroup.Cgroup.open(self.allocator, vm.name);
			}

			self.list.append(self.allocator, vm) catch {};
			arena.deinit();
		}
	}

	fn writeMeta(self: *Vms, vm: *Vm) void {
		const path = std.fs.path.join(self.allocator, &.{ vm.dir, "vm.json" }) catch return;
		const repo = proc.repo(self.io, self.allocator);

		var base_mem: ?[]u8 = null;
		var dirty: []const u8 = "false";
		var packages_mem: ?[]u8 = null;

		if (exec.run(self.io, self.allocator, &.{ "git", "-C", repo, "rev-parse", "HEAD" })) |result| {
			base_mem = self.allocator.dupe(u8, std.mem.trim(u8, result.out, " \r\n")) catch null;
			result.deinit(self.allocator);
		} else |_| {}

		if (exec.run(self.io, self.allocator, &.{ "git", "-C", repo, "status", "--porcelain" })) |result| {
			if (std.mem.trim(u8, result.out, " \r\n").len > 0) dirty = "true";
			result.deinit(self.allocator);
		} else |_| {}

		if (exec.run(self.io, self.allocator, &.{ "sh", "-c", "pacman -Qqen | sha256sum | cut -d' ' -f1" })) |result| {
			packages_mem = self.allocator.dupe(u8, std.mem.trim(u8, result.out, " \r\n")) catch null;
			result.deinit(self.allocator);
		} else |_| {}

		const body = std.fmt.allocPrint(self.allocator, "{{\"name\":\"{s}\",\"cid\":{d},\"cores\":{d},\"memMb\":{d},\"gl\":{s},\"pid\":{d},\"agent\":\"{s}\",\"harness\":\"{s}\",\"session\":\"{s}\",\"sessionTitle\":\"{s}\",\"base\":\"{s}\",\"dirty\":{s},\"packages\":\"{s}\",\"destroyMs\":{d}}}", .{
			vm.name,
			vm.cid,
			vm.cores,
			vm.mem_mb,
			if (vm.gl) "true" else "false",
			vm.pid,
			vm.agent,
			vm.harness,
			vm.session,
			vm.session_title,
			base_mem orelse "",
			dirty,
			packages_mem orelse "",
			vm.destroy_ms,
		}) catch return;

		proc.writeFile(self.io, path, body) catch {};

		if (base_mem) |value| self.allocator.free(value);
		if (packages_mem) |value| self.allocator.free(value);
	}

	fn haltVm(self: *Vms, vm: *Vm) void {
		if (vm.qmp) |client| {
			_ = client.execute(null, "quit", null) catch {};
			client.close();
			vm.qmp = null;
		}

		if (vm.pid > 0) kill(vm.pid);
		if (vm.vfs_pid > 0) kill(vm.vfs_pid);
		self.stopWall(vm);
		self.stopPump(vm);

		if (vm.qemu_child) |*child| {
			_ = child.wait(self.io) catch {};
			vm.qemu_child = null;
		}

		if (vm.vfs_child) |*child| {
			_ = child.wait(self.io) catch {};
			vm.vfs_child = null;
		}

		vm.pid = 0;
		vm.vfs_pid = 0;
		vm.wall_pid = 0;
		vm.tier = .off;
		vm.cpu_pct = 0;
		vm.cpu_ticks = 0;
		vm.cpu_ms = 0;
		vm.rss_kb = 0;
	}

	fn setGuestMode(self: *Vms, cid: u32, width: u32, height: u32, scale: []const u8) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();
		const allocator = arena.allocator();

		const command = std.fmt.allocPrint(allocator, "sudo -n timedatectl set-ntp false >/dev/null 2>&1; " ++
			"export XDG_RUNTIME_DIR=/run/user/1000; " ++
			"export WAYLAND_DISPLAY=$(basename $(ls /run/user/1000/wayland-* 2>/dev/null | grep -v '\\.lock$' | head -1)); " ++
			"export HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr | head -1); " ++
			"hyprctl dispatch 'function() hl.monitor({{output=\"Virtual-1\",mode=\"{d}x{d}@279.96\",position=\"auto\",scale=\"{s}\"}}) end'", .{ width, height, scale }) catch return;

		_ = self.guestExec(cid, &.{ "sh", "-lc", command }, allocator) catch return;
	}

	fn agentBoot(self: *Vms, cid: u32, name: []const u8) void {
		defer self.allocator.free(name);

		var attempt: usize = 0;
		while (attempt < 45) : (attempt += 1) {
			var arena = std.heap.ArenaAllocator.init(self.allocator);
			defer arena.deinit();
			if (self.guestExec(cid, &.{ "sh", "-lc", "pgrep -x Hyprland >/dev/null" }, arena.allocator())) |result| {
				if (result.code == 0) break;
			} else |_| {}
			sleep.ms(2000);
		}
		var human = false;
		self.mutex.lockUncancelable(self.io);
		if (self.findLocked(name)) |vm| human = std.mem.eql(u8, vm.controller, "human");
		self.mutex.unlock(self.io);

		if (human) self.setGuestMode(cid, 2560, 1440, "1.6667") else self.setGuestMode(cid, 1536, 864, "1");
	}

	fn stopWall(self: *Vms, vm: *Vm) void {
		if (vm.wall_pid > 0) kill(vm.wall_pid);
		if (vm.wall_child) |*child| {
			_ = child.wait(self.io) catch {};
			vm.wall_child = null;
		}
		vm.wall_pid = 0;
	}

	fn startPump(self: *Vms, vm: *Vm) void {
		if (vm.pump_pid > 0) return;

		const repo = proc.repo(self.io, self.allocator);
		const display_qmp = std.fs.path.join(self.allocator, &.{ vm.dir, "display.qmp" }) catch return;
		const pump_path = std.fmt.allocPrint(self.allocator, "{s}/daemon/zig-out/bin/yudae-pump", .{repo}) catch return;
		const pump_args = [_][]const u8{ "setsid", pump_path, "--qmp", display_qmp, "--width", "1536", "--height", "864" };

		if (exec.spawn(self.io, .{ .argv = &pump_args, .stdin = .ignore, .stdout = .ignore, .stderr = .ignore })) |pump| {
			vm.pump_pid = pump.id orelse 0;
			vm.pump_child = pump;
		} else |_| {}
	}

	fn stopPump(self: *Vms, vm: *Vm) void {
		if (vm.pump_pid > 0) kill(vm.pump_pid);
		if (vm.pump_child) |*child| {
			_ = child.wait(self.io) catch {};
			vm.pump_child = null;
		}
		vm.pump_pid = 0;
	}

	fn cleanupVm(self: *Vms, vm: *Vm) void {
		if (vm.qmp) |client| {
			_ = client.execute(null, "quit", null) catch {};
			client.close();
			vm.qmp = null;
		}

		if (vm.pid > 0) kill(vm.pid);
		if (vm.vfs_pid > 0) kill(vm.vfs_pid);
		self.stopWall(vm);
		self.stopPump(vm);

		if (vm.qemu_child) |*child| {
			_ = child.wait(self.io) catch {};
			vm.qemu_child = null;
		}

		if (vm.vfs_child) |*child| {
			_ = child.wait(self.io) catch {};
			vm.vfs_child = null;
		}

		if (vm.cgroup) |group| group.destroy(self.io);

		vm.cgroup = null;
		vm.pid = 0;
		vm.vfs_pid = 0;
		vm.wall_pid = 0;
		vm.tier = .off;
	}

	fn destroyVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		return self.removeVm(json.textAt(args, "name"), allocator);
	}

	fn removeVm(self: *Vms, name: []const u8, allocator: Allocator) ![]u8 {
		self.op.lockUncancelable(self.io);
		defer self.op.unlock(self.io);

		self.mutex.lockUncancelable(self.io);
		const vm = self.findLocked(name) orelse {
			self.mutex.unlock(self.io);
			return error.NotFound;
		};
		var index: usize = 0;
		while (index < self.list.items.len) : (index += 1) {
			if (self.list.items[index] == vm) {
				_ = self.list.swapRemove(index);
				break;
			}
		}
		self.mutex.unlock(self.io);

		self.cleanupVm(vm);
		std.Io.Dir.cwd().deleteTree(self.io, vm.dir) catch {};

		self.hub.publish();

		return std.fmt.allocPrint(allocator, "{{\"destroyed\":\"{s}\"}}", .{vm.name});
	}

	fn stopVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		self.op.lockUncancelable(self.io);
		defer self.op.unlock(self.io);

		const name = json.textAt(args, "name");

		self.mutex.lockUncancelable(self.io);
		const vm = self.findLocked(name) orelse {
			self.mutex.unlock(self.io);
			return error.NotFound;
		};
		self.mutex.unlock(self.io);

		self.captureThumb(vm);
		self.haltVm(vm);
		self.hub.publish();

		return std.fmt.allocPrint(allocator, "{{\"name\":\"{s}\",\"tier\":\"off\"}}", .{vm.name});
	}

	fn sleepVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");

		self.mutex.lockUncancelable(self.io);
		const vm = self.findLocked(name) orelse {
			self.mutex.unlock(self.io);
			return error.NotFound;
		};

		if (vm.qmp) |client| {
			_ = client.execute(null, "stop", null) catch {};
			var buffer: [128]u8 = undefined;
			const body = std.fmt.bufPrint(&buffer, "{{\"value\":{d}}}", .{balloonBytes(vm.mem_mb)}) catch {
				self.mutex.unlock(self.io);
				return error.OutOfMemory;
			};
			_ = client.execute(null, "balloon", body) catch {};
		}

		vm.tier = .warm;
		vm.used_ms = fmt.nowMs(self.io);
		const reply = std.fmt.allocPrint(allocator, "{{\"name\":\"{s}\",\"tier\":\"warm\"}}", .{vm.name}) catch {
			self.mutex.unlock(self.io);
			return error.OutOfMemory;
		};
		self.mutex.unlock(self.io);
		self.hub.publish();

		return reply;
	}

	fn parkVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");

		self.mutex.lockUncancelable(self.io);
		const vm = self.findLocked(name) orelse {
			self.mutex.unlock(self.io);
			return error.NotFound;
		};

		if (vm.qmp) |client| {
			_ = client.execute(null, "stop", null) catch {};
			var buffer: [128]u8 = undefined;
			const body = std.fmt.bufPrint(&buffer, "{{\"value\":{d}}}", .{balloonBytes(vm.mem_mb)}) catch {
				self.mutex.unlock(self.io);
				return error.OutOfMemory;
			};
			_ = client.execute(null, "balloon", body) catch {};
		}

		if (vm.cgroup) |group| group.park(self.io, self.allocator);

		vm.tier = .parked;
		vm.used_ms = fmt.nowMs(self.io);
		const reply = std.fmt.allocPrint(allocator, "{{\"name\":\"{s}\",\"tier\":\"parked\"}}", .{vm.name}) catch {
			self.mutex.unlock(self.io);
			return error.OutOfMemory;
		};
		self.mutex.unlock(self.io);
		self.hub.publish();

		return reply;
	}

	fn wakeVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");

		self.mutex.lockUncancelable(self.io);
		const vm = self.findLocked(name) orelse {
			self.mutex.unlock(self.io);
			return error.NotFound;
		};
		const off = vm.tier == .off;
		if (off) {
			self.mutex.unlock(self.io);
			return self.startVm(args, allocator);
		}

		const slept = vm.tier != .hot;
		if (vm.qmp) |client| {
			_ = client.execute(null, "balloon", "{\"value\":0}") catch {};
			_ = client.execute(null, "cont", null) catch {};
		}

		vm.tier = .hot;
		vm.used_ms = fmt.nowMs(self.io);
		const cid = vm.cid;
		self.mutex.unlock(self.io);

		if (slept) self.syncGuestClock(cid);

		self.hub.publish();

		return std.fmt.allocPrint(allocator, "{{\"name\":\"{s}\",\"tier\":\"hot\"}}", .{vm.name});
	}

	fn execVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");
		const cid = self.cidOf(name) orelse return error.NotFound;
		const command = json.textAt(args, "cmd");

		var argv: []const []const u8 = undefined;

		if (command.len > 0) {
			argv = &.{ "sh", "-lc", command };
		} else {
			const list = json.listAt(args, "argv");
			const built = try allocator.alloc([]const u8, list.len);

			for (list, 0..) |item, index| built[index] = json.text(item);
			argv = built;
		}

		if (argv.len == 0) return error.MissingArgs;

		const result = self.guestExec(cid, argv, allocator) catch |err| {
			return std.fmt.allocPrint(allocator, "{{\"code\":255,\"out\":\"\",\"err\":\"{s}\"}}", .{@errorName(err)});
		};

		var out: std.Io.Writer.Allocating = .init(allocator);
		const writer = &out.writer;
		try writer.print("{{\"code\":{d},\"out\":", .{result.code});
		try json.encodeText(writer, result.out);
		try writer.writeAll(",\"err\":");
		try json.encodeText(writer, result.err);
		try writer.writeAll("}");

		return out.written();
	}

	fn stateVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");
		const cid = self.cidOf(name) orelse return error.NotFound;
		return self.guestState(cid, allocator);
	}

	fn guestScreenshot(self: *Vms, vm: *Vm, path: []const u8, allocator: Allocator) !void {
		const command =
			"export XDG_RUNTIME_DIR=/run/user/1000; " ++
			"export WAYLAND_DISPLAY=$(basename $(ls /run/user/1000/wayland-* 2>/dev/null | grep -v '\\.lock$' | head -1)); " ++
			"export HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr | head -1); " ++
			"grim -s $(python3 -c 'import json,subprocess;print(json.loads(subprocess.check_output([\"hyprctl\",\"monitors\",\"-j\"]))[0][\"scale\"])') /tmp/yudae-shot.png >/dev/null 2>&1; base64 -w0 /tmp/yudae-shot.png";

		var attempts: usize = 0;
		var text: []const u8 = "";

		while (attempts < 40) : (attempts += 1) {
			const result = self.guestExec(vm.cid, &.{ "sh", "-lc", command }, allocator) catch null;

			if (result) |value| {
				if (value.code == 0) {
					const trimmed = std.mem.trim(u8, value.out, " \r\n");
					if (trimmed.len > 0) {
						text = trimmed;
						break;
					}
				}
			}

			sleep.ms(250);
		}

		if (text.len == 0) return error.ScreenshotFailed;

		const decoder = std.base64.standard.Decoder;
		const size = try decoder.calcSizeForSlice(text);
		const bytes = try allocator.alloc(u8, size);
		defer allocator.free(bytes);
		try decoder.decode(bytes, text);

		if (bytes.len < 8 or !std.mem.eql(u8, bytes[1..4], "PNG")) return error.ScreenshotFailed;
		try proc.writeFile(self.io, path, bytes);
	}

	fn screenOf(self: *Vms, name: []const u8) [2]u32 {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		const vm = self.findLocked(name) orelse return .{ 0, 0 };
		return .{ vm.screen_w, vm.screen_h };
	}

	fn rememberScreen(self: *Vms, name: []const u8, path: []const u8, allocator: Allocator) void {
		const bytes = proc.readFile(self.io, allocator, path) catch return;
		if (bytes.len < 24 or !std.mem.eql(u8, bytes[1..4], "PNG")) return;

		const width = std.mem.readInt(u32, bytes[16..20], .big);
		const height = std.mem.readInt(u32, bytes[20..24], .big);

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		const vm = self.findLocked(name) orelse return;
		vm.screen_w = width;
		vm.screen_h = height;
	}

	fn guestThumb(self: *Vms, vm: *Vm, path: []const u8, allocator: Allocator) !void {
		const command =
			"export XDG_RUNTIME_DIR=/run/user/1000; " ++
			"export WAYLAND_DISPLAY=$(basename $(ls /run/user/1000/wayland-* 2>/dev/null | grep -v '\\.lock$' | head -1)); " ++
			"export HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr | head -1); " ++
			"grim -t jpeg -q 80 /tmp/yudae-thumb.jpg >/dev/null 2>&1; base64 -w0 /tmp/yudae-thumb.jpg";

		var text: []const u8 = "";
		var attempts: usize = 0;
		while (attempts < 20) : (attempts += 1) {
			const result = self.guestExec(vm.cid, &.{ "sh", "-lc", command }, allocator) catch null;
			if (result) |value| {
				if (value.code == 0) {
					const trimmed = std.mem.trim(u8, value.out, " \r\n");
					if (trimmed.len > 0) {
						text = trimmed;
						break;
					}
				}
			}
			sleep.ms(250);
		}
		if (text.len == 0) return error.ScreenshotFailed;

		const decoder = std.base64.standard.Decoder;
		const size = try decoder.calcSizeForSlice(text);
		const bytes = try allocator.alloc(u8, size);
		defer allocator.free(bytes);
		try decoder.decode(bytes, text);
		try proc.writeFile(self.io, path, bytes);
	}

	fn captureThumb(self: *Vms, vm: *Vm) void {
		if (vm.tier == .off or vm.cid == 0) return;

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();
		const allocator = arena.allocator();
		const dst = std.fmt.allocPrint(allocator, "{s}/thumb.jpg", .{vm.dir}) catch return;

		self.guestThumb(vm, dst, allocator) catch return;

		self.mutex.lockUncancelable(self.io);
		vm.thumb = true;
		vm.thumb_ms = fmt.nowMs(self.io);
		self.mutex.unlock(self.io);
	}

	fn screenshotVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");

		self.mutex.lockUncancelable(self.io);
		const vm = self.findLocked(name) orelse {
			self.mutex.unlock(self.io);
			return error.NotFound;
		};
		self.mutex.unlock(self.io);

		const path = if (json.textAt(args, "path").len > 0)
			try allocator.dupe(u8, json.textAt(args, "path"))
		else
			try std.fmt.allocPrint(allocator, "{s}/shot-{d}.png", .{ vm.dir, fmt.nowMs(self.io) });

		if (vm.gl) {
			if (self.guestScreenshot(vm, path, allocator)) |_| {
				self.rememberScreen(name, path, allocator);
				return std.fmt.allocPrint(allocator, "{{\"path\":\"{s}\"}}", .{path});
			} else |_| {}
		}

		const client = vm.qmp orelse return error.NotRunning;

		var body: std.Io.Writer.Allocating = .init(allocator);
		const writer = &body.writer;
		try writer.writeAll("{\"filename\":");
		try std.json.Stringify.encodeJsonString(path, .{}, writer);
		try writer.writeAll(",\"format\":\"png\"}");

		_ = client.execute(allocator, "screendump", body.written()) catch {
			var fallback: std.Io.Writer.Allocating = .init(allocator);
			try fallback.writer.writeAll("{\"filename\":");
			try std.json.Stringify.encodeJsonString(path, .{}, &fallback.writer);
			try fallback.writer.writeAll("}");
			_ = client.execute(allocator, "screendump", fallback.written()) catch return error.ScreenshotFailed;
		};

		return std.fmt.allocPrint(allocator, "{{\"path\":\"{s}\"}}", .{path});
	}

	fn guestExec(self: *Vms, cid: u32, argv: []const []const u8, allocator: Allocator) !vsock.Result {
		var attempts: usize = 0;

		while (attempts < 40) : (attempts += 1) {
			if (vsock.exec(self.io, allocator, cid, argv)) |result| return result else |err| {
				if (err != error.ConnectFailed and err != error.SocketFailed) return err;
			}
			sleep.ms(50);
		}

		return error.ConnectFailed;
	}

	fn guestState(self: *Vms, cid: u32, allocator: Allocator) ![]u8 {
		var attempts: usize = 0;

		while (attempts < 40) : (attempts += 1) {
			if (vsock.state(self.io, allocator, cid)) |body| return body else |err| {
				if (err != error.ConnectFailed and err != error.SocketFailed) return err;
			}
			sleep.ms(50);
		}

		return error.ConnectFailed;
	}

	fn pushVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");
		const cid = self.cidOf(name) orelse return error.NotFound;
		const path = json.textAt(args, "path");
		const to = if (json.textAt(args, "to").len > 0) json.textAt(args, "to") else path;

		if (!safePath(to)) return error.BadPath;

		const body = try proc.readFile(self.io, allocator, path);
		if (body.len > 512 * 1024) return error.TooLarge;

		const encoder = std.base64.standard.Encoder;
		const encoded = try allocator.alloc(u8, encoder.calcSize(body.len));
		_ = encoder.encode(encoded, body);

		const command = try std.fmt.allocPrint(allocator, "printf %s '{s}' | base64 -d > '{s}'", .{ encoded, to });
		const result = try self.guestExec(cid, &.{ "sh", "-lc", command }, allocator);
		if (result.code != 0) return error.PushFailed;

		return std.fmt.allocPrint(allocator, "{{\"path\":\"{s}\",\"bytes\":{d}}}", .{ to, body.len });
	}

	fn pullVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");
		const cid = self.cidOf(name) orelse return error.NotFound;
		const path = json.textAt(args, "path");
		const to = json.textAt(args, "to");

		if (!safePath(path) or !safePath(to)) return error.BadPath;

		const command = try std.fmt.allocPrint(allocator, "base64 -w0 '{s}'", .{path});
		const result = try self.guestExec(cid, &.{ "sh", "-lc", command }, allocator);
		if (result.code != 0) return error.PullFailed;

		const text = std.mem.trim(u8, result.out, " \r\n");
		const decoder = std.base64.standard.Decoder;
		const size = try decoder.calcSizeForSlice(text);
		const bytes = try allocator.alloc(u8, size);
		try decoder.decode(bytes, text);

		try proc.writeFile(self.io, to, bytes);

		return std.fmt.allocPrint(allocator, "{{\"path\":\"{s}\",\"bytes\":{d}}}", .{ to, bytes.len });
	}

	fn uiTreeVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");
		const cid = self.cidOf(name) orelse return error.NotFound;

		const state = try self.guestState(cid, allocator);
		const command =
			"export XDG_RUNTIME_DIR=/run/user/1000; " ++
			"export WAYLAND_DISPLAY=$(basename $(ls /run/user/1000/wayland-* 2>/dev/null | grep -v '\\.lock$' | head -1)); " ++
			"export HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr | head -1); " ++
			"hyprctl -j clients";

		const clients = self.guestExec(cid, &.{ "sh", "-lc", command }, allocator) catch null;
		var tree: []const u8 = "[]";

		if (clients) |value| {
			const trimmed = std.mem.trim(u8, value.out, " \r\n");
			if (value.code == 0 and trimmed.len > 0 and (trimmed[0] == '[' or trimmed[0] == '{')) tree = trimmed;
		}

		var out: std.Io.Writer.Allocating = .init(allocator);
		const writer = &out.writer;
		try writer.writeAll("{\"state\":");
		try writer.writeAll(state);
		try writer.writeAll(",\"clients\":");
		try writer.writeAll(tree);
		try writer.writeAll("}");
		return out.written();
	}

	fn scenarioVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const scenario = json.textAt(args, "scenario");
		if (scenario.len == 0) return error.MissingArgs;

		const repo = proc.repo(self.io, self.allocator);
		const path = try std.fs.path.join(allocator, &.{ repo, "vm", "scenarios", try std.fmt.allocPrint(allocator, "{s}.json", .{scenario}) });
		const body = proc.readFile(self.io, allocator, path) catch return error.ScenarioMissing;

		var arena = std.heap.ArenaAllocator.init(allocator);
		defer arena.deinit();
		const parsed = json.parse(arena.allocator(), body) catch return error.ScenarioBad;

		const name = if (json.textAt(args, "name").len > 0) json.textAt(args, "name") else scenario;
		const context = json.field(parsed.value, "context") orelse json.Value{ .null = {} };

		var create_args: std.Io.Writer.Allocating = .init(allocator);
		const writer = &create_args.writer;
		try writer.writeAll("{\"name\":");
		try std.json.Stringify.encodeJsonString(name, .{}, writer);
		try writer.writeAll(",\"cores\":");
		try writer.print("{d}", .{json.integer(json.field(context, "cores"))});
		try writer.writeAll(",\"mem\":");
		try writer.print("{d}", .{json.integer(json.field(context, "mem"))});
		try writer.writeAll(",\"gl\":");
		try writer.writeAll(if (json.flag(context, "gl")) "true" else "false");
		if (json.textAt(context, "from").len > 0) {
			try writer.writeAll(",\"from\":");
			try std.json.Stringify.encodeJsonString(json.textAt(context, "from"), .{}, writer);
		}
		try writer.writeAll("}");

		const created = try self.createVm((try json.parse(allocator, create_args.written())).value, allocator);
		_ = created;

		var results: std.Io.Writer.Allocating = .init(allocator);
		const results_writer = &results.writer;
		try results_writer.writeAll("[");

		const shots = try std.fs.path.join(allocator, &.{ repo, "vm", "runs", "shots", name });
		var ok = true;
		var index: usize = 0;

		for (json.listAt(parsed.value, "steps")) |step| {
			const action = json.textAt(step, "do");
			var result: []u8 = undefined;

			if (std.mem.eql(u8, action, "sleep")) {
				const ms = json.integer(json.field(step, "ms"));
				sleep.ms(@intCast(@max(ms, 0)));
				result = try allocator.dupe(u8, "{}");
			} else {
				var built: std.Io.Writer.Allocating = .init(allocator);
				const step_writer = &built.writer;
				try step_writer.writeAll("{\"name\":");
				try std.json.Stringify.encodeJsonString(name, .{}, step_writer);

				for ([_][]const u8{ "cmd", "text", "until", "path", "to" }) |key| {
					if (json.field(step, key)) |value| {
						try step_writer.writeAll(",");
						try std.json.Stringify.encodeJsonString(key, .{}, step_writer);
						try step_writer.writeAll(":");
						try step_writer.print("{f}", .{std.json.fmt(value, .{})});
					}
				}

				for ([_][]const u8{ "x", "y", "timeout" }) |key| {
					if (json.field(step, key)) |value| {
						try step_writer.writeAll(",");
						try std.json.Stringify.encodeJsonString(key, .{}, step_writer);
						try step_writer.writeAll(":");
						try step_writer.print("{f}", .{std.json.fmt(value, .{})});
					}
				}

				if (json.field(step, "keys")) |keys| {
					try step_writer.writeAll(",\"keys\":");
					try step_writer.print("{f}", .{std.json.fmt(keys, .{})});
				}

				if (std.mem.eql(u8, action, "screenshot") and json.textAt(step, "path").len == 0) {
					const shot_path = try std.fmt.allocPrint(allocator, "{s}/shot-{d}.png", .{ shots, fmt.nowMs(self.io) });
					try step_writer.writeAll(",\"path\":");
					try std.json.Stringify.encodeJsonString(shot_path, .{}, step_writer);
				}

				try step_writer.writeAll("}");

				result = try self.call(action, (try json.parse(allocator, built.written())).value, allocator);
			}

			if (json.field(step, "code")) |want| {
				const got = json.integer(json.field((try json.parse(allocator, result)).value, "code"));
				if (got != json.integer(want)) ok = false;
			}

			if (index > 0) try results_writer.writeAll(",");
			try results_writer.writeAll(result);
			index += 1;
		}

		try results_writer.writeAll("]");

		const keep = json.flag(args, "keep") or json.flag(context, "keep") or json.flag(parsed.value, "keep");
		const kept = !(ok and !keep);
		if (!kept) _ = self.removeVm(name, allocator) catch {};

		return std.fmt.allocPrint(allocator, "{{\"scenario\":\"{s}\",\"name\":\"{s}\",\"ok\":{s},\"kept\":{s},\"proof\":\"{s}\",\"steps\":{s}}}", .{
			scenario,
			name,
			if (ok) "true" else "false",
			if (kept) "true" else "false",
			shots,
			results.written(),
		});
	}

	fn humanHolds(self: *Vms, name: []const u8) bool {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		const vm = self.findLocked(name) orelse return false;
		return std.mem.eql(u8, vm.controller, "human");
	}

	fn openApp(self: *Vms, allocator: Allocator) ![]u8 {
		const repo = proc.repo(self.io, self.allocator);
		const class = "com.yudae.vms";

		if (exec.run(self.io, self.allocator, &.{ "hyprctl", "clients", "-j" })) |result| {
			defer result.deinit(self.allocator);
			if (std.mem.indexOf(u8, result.out, class) != null) {
				const focus = std.fmt.allocPrint(allocator, "function() for _,w in ipairs(hl.get_windows()) do if w.class == \"{s}\" then hl.dispatch(hl.dsp.focus({{window=w}})) return end end end", .{class}) catch return allocator.dupe(u8, "{}");
				const hypr = @import("../primitives/hypr.zig");
				const reply = hypr.request(self.io, allocator, focus) catch null;
				if (reply) |body| allocator.free(body);
				return allocator.dupe(u8, "{}");
			}
		} else |_| {}

		const entry = std.fmt.allocPrint(self.allocator, "{s}/shell/app-vms.qml", .{repo}) catch return error.OutOfMemory;
		const argv = [_][]const u8{ "setsid", "quickshell", "-p", entry };
		_ = exec.spawn(self.io, .{ .argv = &argv, .stdin = .ignore, .stdout = .ignore, .stderr = .ignore }) catch return error.SpawnFailed;
		return allocator.dupe(u8, "{}");
	}

	fn selectVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");
		if (name.len == 0) return error.MissingArgs;

		self.mutex.lockUncancelable(self.io);
		const vm = self.findLocked(name) orelse {
			self.mutex.unlock(self.io);
			return error.NotFound;
		};
		self.allocator.free(self.selected);
		self.selected = try self.allocator.dupe(u8, vm.name);
		self.mutex.unlock(self.io);

		self.hub.publish();
		return allocator.dupe(u8, "{}");
	}

	fn agentVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");
		if (name.len == 0) return error.MissingArgs;

		self.mutex.lockUncancelable(self.io);

		const vm = self.findLocked(name) orelse {
			self.mutex.unlock(self.io);
			return error.NotFound;
		};
		const harness = json.textAt(args, "harness");
		const session = json.textAt(args, "session");
		const now = fmt.nowMs(self.io);

		if (harness.len > 0) {
			self.allocator.free(vm.harness);
			vm.harness = try self.allocator.dupe(u8, harness);
		}
		if (session.len > 0) {
			self.allocator.free(vm.session);
			vm.session = try self.allocator.dupe(u8, session);

			if (self.opencode) |source| {
				const title = source.sessionTitle(self.allocator, session) catch null;
				if (title) |value| {
					self.allocator.free(vm.session_title);
					vm.session_title = value;
				}
			}
		}
		if (vm.agent_since_ms == 0) vm.agent_since_ms = now;
		vm.last_call_ms = now;
		vm.used_ms = now;
		self.mutex.unlock(self.io);

		self.hub.publish();

		return allocator.dupe(u8, "{}");
	}

	fn viewVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");

		self.mutex.lockUncancelable(self.io);
		const vm = self.findLocked(name) orelse {
			self.mutex.unlock(self.io);
			return error.NotFound;
		};
		vm.controller = try self.allocator.dupe(u8, "human");
		vm.used_ms = fmt.nowMs(self.io);
		self.allocator.free(self.selected);
		self.selected = try self.allocator.dupe(u8, vm.name);
		const cid = vm.cid;
		const off = vm.tier == .off;
		self.mutex.unlock(self.io);

		if (off) _ = try self.startVm(args, allocator);

		self.stopPump(vm);
		self.setGuestMode(cid, 2560, 1440, "1.6667");

		self.hub.publish();

		self.syncDesktop();
		self.applyDesktop(vm);

		return std.fmt.allocPrint(allocator, "{{\"name\":\"{s}\",\"controller\":\"human\"}}", .{vm.name});
	}

	fn guiVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");
		const app = json.textAt(args, "app");
		if (name.len == 0 or app.len == 0) return error.MissingArgs;
		if (!validName(app)) return error.BadName;

		const cid = self.cidOf(name) orelse return error.NotFound;
		const repo = proc.repo(self.io, self.allocator);
		const entry = try std.fs.path.join(allocator, &.{ repo, "shell", try std.fmt.allocPrint(allocator, "app-{s}.qml", .{app}) });
		const shell_app = proc.exists(self.io, entry);

		const env =
			"export XDG_RUNTIME_DIR=/run/user/1000; " ++
			"export WAYLAND_DISPLAY=$(basename $(ls /run/user/1000/wayland-* 2>/dev/null | grep -v '\\.lock$' | head -1)); " ++
			"export HYPRLAND_INSTANCE_SIGNATURE=$(for d in $(ls -t /run/user/1000/hypr); do [ -S /run/user/1000/hypr/$d/.socket.sock ] && echo $d && break; done); ";

		const command = if (shell_app)
			try std.fmt.allocPrint(allocator, "{s}setsid quickshell -p {s} >/tmp/quickshell-{s}.log 2>&1 &", .{ env, entry, app })
		else
			try std.fmt.allocPrint(allocator, "{s}setsid {s} >/tmp/{s}.log 2>&1 &", .{ env, app, app });

		const result = self.guestExec(cid, &.{ "sh", "-lc", command }, allocator) catch return error.GuestUnreachable;
		if (result.code != 0) return error.AppFailed;

		return std.fmt.allocPrint(allocator, "{{\"name\":\"{s}\",\"app\":\"{s}\"}}", .{ name, app });
	}

	fn configVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");
		if (name.len == 0) return error.MissingArgs;

		const cores = json.integer(json.field(args, "cores"));
		const mem = json.integer(json.field(args, "mem"));
		if (cores == 0 and mem == 0) return error.MissingArgs;
		if (cores != 0 and (cores < 1 or cores > 32)) return error.BadValue;
		if (mem != 0 and (mem < 512 or mem > 65536)) return error.BadValue;

		self.mutex.lockUncancelable(self.io);
		const vm = self.findLocked(name) orelse {
			self.mutex.unlock(self.io);
			return error.NotFound;
		};

		if (cores > 0) vm.cores = @intCast(cores);
		if (mem > 0) vm.mem_mb = @intCast(mem);
		self.writeMeta(vm);

		const reply = std.fmt.allocPrint(allocator, "{{\"name\":\"{s}\",\"cores\":{d},\"memMb\":{d}}}", .{ vm.name, vm.cores, vm.mem_mb }) catch {
			self.mutex.unlock(self.io);
			return error.OutOfMemory;
		};
		self.mutex.unlock(self.io);
		self.hub.publish();

		return reply;
	}

	fn scrollVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");
		if (self.humanHolds(name) and !humanRequest(args)) return error.HumanControl;
		const client = self.qmpOf(name) orelse return error.NotRunning;
		const dy = json.integer(json.field(args, "dy"));
		if (dy == 0) return error.MissingArgs;

		const x = json.numberAt(args, "x");
		const y = json.numberAt(args, "y");
		if (x > 0 or y > 0) try pointer(self.io, client, allocator, x, y, self.screenOf(name));

		const up = dy < 0;
		var count: usize = @intCast(if (up) -dy else dy);
		if (count > 20) count = 20;

		for (0..count) |_| {
			try buttonEvent(client, allocator, if (up) "wheel-up" else "wheel-down", true);
			try buttonEvent(client, allocator, if (up) "wheel-up" else "wheel-down", false);
			sleep.ms(30);
		}

		return std.fmt.allocPrint(allocator, "{{\"scrolled\":{d}}}", .{count});
	}

	fn uiVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");
		const action = json.textAt(args, "action");
		const cid = self.cidOf(name) orelse return error.NotFound;

		const glyph = if (std.mem.eql(u8, action, "clipboard"))
			"clipboard"
		else if (std.mem.eql(u8, action, "windows"))
			"windows"
		else
			"launcher";

		const command = try std.fmt.allocPrint(allocator, "export XDG_RUNTIME_DIR=/run/user/1000; " ++
			"export WAYLAND_DISPLAY=$(basename $(ls /run/user/1000/wayland-* 2>/dev/null | grep -v '\\.lock$' | head -1)); " ++
			"export HYPRLAND_INSTANCE_SIGNATURE=$(ls /run/user/1000/hypr | head -1); " ++
			"hyprctl dispatch 'hl.dsp.global(\"quickshell:{s}\")'", .{glyph});

		const result = try self.guestExec(cid, &.{ "sh", "-lc", command }, allocator);
		if (result.code != 0) return error.UiFailed;

		return std.fmt.allocPrint(allocator, "{{\"name\":\"{s}\",\"action\":\"{s}\"}}", .{ name, action });
	}

	fn releaseVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");

		self.mutex.lockUncancelable(self.io);
		const vm = self.findLocked(name) orelse {
			self.mutex.unlock(self.io);
			return error.NotFound;
		};
		vm.controller = try self.allocator.dupe(u8, "agent");
		const cid = vm.cid;

		if (vm.tier == .warm or vm.tier == .parked) {
			if (vm.qmp) |client| {
				_ = client.execute(null, "balloon", "{\"value\":0}") catch {};
				_ = client.execute(null, "cont", null) catch {};
			}
			vm.tier = .hot;
		}

		self.allocator.free(self.selected);
		self.selected = try self.allocator.dupe(u8, "");
		self.mutex.unlock(self.io);

		self.captureThumb(vm);
		self.setGuestMode(cid, 1536, 864, "1");
		self.startPump(vm);
		self.hub.publish();

		return std.fmt.allocPrint(allocator, "{{\"name\":\"{s}\",\"controller\":\"agent\"}}", .{vm.name});
	}

	fn keyVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");
		if (self.humanHolds(name) and !humanRequest(args)) return error.HumanControl;
		const keys = json.listAt(args, "keys");

		if (keys.len == 0) return error.MissingArgs;

		const asked = json.integer(json.field(args, "hold"));
		const hold = std.math.clamp(if (asked == 0) 30 else asked, 10, 10000);

		var body: std.Io.Writer.Allocating = .init(allocator);
		const writer = &body.writer;
		try writer.writeAll("{\"keys\":[");

		for (keys, 0..) |item, index| {
			if (index > 0) try writer.writeAll(",");

			const key = input.hardwareOf(json.text(item)) orelse blk: {
				break :blk try std.ascii.allocLowerString(allocator, json.text(item));
			};

			try writer.writeAll("{\"type\":\"qcode\",\"data\":");
			try std.json.Stringify.encodeJsonString(key, .{}, writer);
			try writer.writeAll("}");
		}

		try writer.print("],\"hold-time\":{d}}}", .{hold});

		const client = self.qmpOf(name) orelse return error.NotRunning;
		_ = client.execute(allocator, "send-key", body.written()) catch return error.KeyFailed;

		return allocator.dupe(u8, "{\"ok\":true}");
	}

	fn typeVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");
		if (self.humanHolds(name) and !humanRequest(args)) return error.HumanControl;
		const text = json.textAt(args, "text");
		const client = self.qmpOf(name) orelse return error.NotRunning;

		var count: usize = 0;

		for (text) |char| {
			const key = input.keyOf(char) orelse continue;

			var body: std.Io.Writer.Allocating = .init(allocator);
			const writer = &body.writer;
			try writer.writeAll("{\"keys\":[");

			if (key.shift) try writer.writeAll("{\"type\":\"qcode\",\"data\":\"shift\"},");

			try writer.writeAll("{\"type\":\"qcode\",\"data\":");
			try std.json.Stringify.encodeJsonString(key.code, .{}, writer);
			try writer.writeAll("}],\"hold-time\":15}");

			_ = client.execute(allocator, "send-key", body.written()) catch continue;
			count += 1;
			sleep.ms(8);
		}

		return std.fmt.allocPrint(allocator, "{{\"typed\":{d}}}", .{count});
	}

	fn clickVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");
		if (self.humanHolds(name) and !humanRequest(args)) return error.HumanControl;
		const client = self.qmpOf(name) orelse return error.NotRunning;
		const x = json.numberAt(args, "x");
		const y = json.numberAt(args, "y");
		const button = if (std.mem.eql(u8, json.textAt(args, "button"), "right")) "right" else "left";

		try pointer(self.io, client, allocator, x, y, self.screenOf(name));
		try buttonEvent(client, allocator, button, true);
		sleep.ms(40);
		try buttonEvent(client, allocator, button, false);

		return allocator.dupe(u8, "{\"ok\":true}");
	}

	fn moveVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");
		if (self.humanHolds(name) and !humanRequest(args)) return error.HumanControl;
		const client = self.qmpOf(name) orelse return error.NotRunning;

		try pointer(self.io, client, allocator, json.numberAt(args, "x"), json.numberAt(args, "y"), self.screenOf(name));

		return allocator.dupe(u8, "{\"ok\":true}");
	}

	fn waitVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");
		const until = json.textAt(args, "until");
		const timeout = if (json.integer(json.field(args, "timeout")) > 0) json.integer(json.field(args, "timeout")) else 30000;
		const cid = self.cidOf(name) orelse return error.NotFound;

		const start = fmt.nowMs(self.io);
		var waited: i64 = 0;

		while (fmt.nowMs(self.io) - start < timeout) {
			waited = fmt.nowMs(self.io) - start;

			if (std.mem.eql(u8, until, "guest")) {
				if (vsock.state(self.io, allocator, cid)) |_| {
					return std.fmt.allocPrint(allocator, "{{\"waited\":{d}}}", .{waited});
				} else |_| {}
			} else if (std.mem.startsWith(u8, until, "exec:")) {
				const command = until["exec:".len..];
				const result = vsock.exec(self.io, allocator, cid, &.{ "sh", "-lc", command }) catch null;

				if (result) |value| {
					if (value.code == 0) return std.fmt.allocPrint(allocator, "{{\"waited\":{d},\"out\":\"ok\"}}", .{waited});
				}
			} else if (std.mem.startsWith(u8, until, "sleep:")) {
				const ms = std.fmt.parseInt(i64, until["sleep:".len..], 10) catch 0;
				sleep.ms(@intCast(@max(ms, 0)));
				return std.fmt.allocPrint(allocator, "{{\"waited\":{d}}}", .{ms});
			} else {
				if (vsock.state(self.io, allocator, cid)) |body| {
					if (std.mem.indexOf(u8, body, until) != null) return std.fmt.allocPrint(allocator, "{{\"waited\":{d}}}", .{waited});
				} else |_| {}
			}

			sleep.ms(100);
		}

		return error.Timeout;
	}

	fn snapshotVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");
		const tag = json.textAt(args, "tag");
		if (tag.len == 0) return error.MissingArgs;

		const disk = self.diskOf(name) orelse return error.NotFound;
		if (self.tierOf(name) != .off) return error.MustStop;

		const result = try exec.run(self.io, allocator, &.{ "qemu-img", "snapshot", "-c", tag, disk });
		defer result.deinit(allocator);

		if (result.code != 0) return error.SnapshotFailed;
		return allocator.dupe(u8, "{\"ok\":true}");
	}

	fn restoreVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		const name = json.textAt(args, "name");
		const tag = json.textAt(args, "tag");
		if (tag.len == 0) return error.MissingArgs;

		const disk = self.diskOf(name) orelse return error.NotFound;
		if (self.tierOf(name) != .off) return error.MustStop;

		const result = try exec.run(self.io, allocator, &.{ "qemu-img", "snapshot", "-a", tag, disk });
		defer result.deinit(allocator);

		if (result.code != 0) return error.SnapshotFailed;
		return allocator.dupe(u8, "{\"ok\":true}");
	}

	fn forkVm(self: *Vms, args: json.Value, allocator: Allocator) ![]u8 {
		self.op.lockUncancelable(self.io);
		defer self.op.unlock(self.io);

		const name = json.textAt(args, "name");
		const from = json.textAt(args, "from");
		if (!validName(name)) return error.BadName;

		self.mutex.lockUncancelable(self.io);
		const source = self.findLocked(from) orelse {
			self.mutex.unlock(self.io);
			return error.NotFound;
		};
		if (self.findLocked(name) != null) {
			self.mutex.unlock(self.io);
			return error.NameTaken;
		}

		const cores = source.cores;
		const mem = source.mem_mb;
		const gl = source.gl;
		const source_disk = try self.allocator.dupe(u8, source.disk);
		const cid = self.nextCidLocked();
		self.mutex.unlock(self.io);

		const dir = try std.fs.path.join(self.allocator, &.{ proc.repo(self.io, self.allocator), "vm", "runs", name });
		try std.Io.Dir.cwd().createDirPath(self.io, dir);
		const target = try std.fs.path.join(self.allocator, &.{ dir, "disk.qcow2" });

		const result = try exec.run(self.io, allocator, &.{ "qemu-img", "convert", "-O", "qcow2", "-U", source_disk, target });
		defer result.deinit(allocator);

		if (result.code != 0) return error.ForkFailed;

		const vm = try self.allocator.create(Vm);
		vm.* = .{
			.name = try self.allocator.dupe(u8, name),
			.dir = dir,
			.disk = target,
			.agent = try self.allocator.dupe(u8, "agent"),
			.controller = try self.allocator.dupe(u8, "agent"),
			.harness = try self.allocator.dupe(u8, ""),
			.session = try self.allocator.dupe(u8, ""),
			.cid = cid,
			.cores = cores,
			.mem_mb = mem,
			.gl = gl,
			.tier = .off,
			.created_ms = fmt.nowMs(self.io),
			.used_ms = fmt.nowMs(self.io),
			.destroy_ms = idleDestroyDefault(),
		};

		self.mutex.lockUncancelable(self.io);
		try self.list.append(self.allocator, vm);
		self.mutex.unlock(self.io);

		self.hub.publish();

		return std.fmt.allocPrint(allocator, "{{\"name\":\"{s}\",\"from\":\"{s}\",\"cid\":{d}}}", .{ name, from, cid });
	}

	fn listJson(self: *Vms, allocator: Allocator) ![]u8 {
		var out: std.Io.Writer.Allocating = .init(allocator);
		const writer = &out.writer;

		writer.writeAll("[") catch return error.OutOfMemory;

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		for (self.list.items, 0..) |vm, index| {
			if (index > 0) try writer.writeAll(",");
			try writer.print("{{\"name\":\"{s}\",\"tier\":\"{s}\",\"cid\":{d},\"pid\":{d},\"cores\":{d},\"memMb\":{d},\"gl\":{s}}}", .{
				vm.name,
				vm.tier.text(),
				vm.cid,
				vm.pid,
				vm.cores,
				vm.mem_mb,
				if (vm.gl) "true" else "false",
			});
		}

		try writer.writeAll("]");
		return out.written();
	}

	fn vmName(self: *Vms, args: json.Value) ![]const u8 {
		const name = json.textAt(args, "name");
		if (name.len > 0) return name;

		const session = json.textAt(args, "session");
		if (session.len > 0) return session;

		return std.fmt.allocPrint(self.allocator, "vm-{d}", .{fmt.nowMs(self.io)});
	}

	fn memOf(self: *Vms, args: json.Value) u32 {
		const value = json.integer(json.field(args, "mem"));
		if (value <= 0) return @min(4096, self.limit.mem_mb);
		return @intCast(@min(@as(i64, self.limit.mem_mb), value));
	}

	fn coresOf(self: *Vms, args: json.Value) u32 {
		const value = json.integer(json.field(args, "cores"));
		if (value <= 0) return self.limit.cores;
		return @intCast(@min(@as(i64, self.limit.cores), value));
	}

	fn usedMemLocked(self: *Vms) u64 {
		var total: u64 = 0;
		for (self.list.items) |vm| {
			if (vm.tier != .off) total += vm.mem_mb;
		}
		return total;
	}

	fn glCountLocked(self: *Vms) u32 {
		var total: u32 = 0;
		for (self.list.items) |vm| {
			if (vm.tier != .off and vm.gl) total += 1;
		}
		return total;
	}

	fn usedCoresLocked(self: *Vms) u64 {
		var total: u64 = 0;
		for (self.list.items) |vm| {
			if (vm.tier != .off) total += vm.cores;
		}
		return total;
	}

	fn nextCidLocked(self: *Vms) u32 {
		var cid: u32 = 3;
		for (self.list.items) |vm| {
			if (vm.cid >= cid) cid = vm.cid + 1;
		}
		return cid;
	}

	fn findLocked(self: *Vms, name: []const u8) ?*Vm {
		for (self.list.items) |vm| {
			if (std.mem.eql(u8, vm.name, name)) return vm;
		}
		return null;
	}

	fn cidOf(self: *Vms, name: []const u8) ?u32 {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		const vm = self.findLocked(name) orelse return null;
		return vm.cid;
	}

	fn tierOf(self: *Vms, name: []const u8) tiers.Tier {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		const vm = self.findLocked(name) orelse return .off;
		return vm.tier;
	}

	fn diskOf(self: *Vms, name: []const u8) ?[]const u8 {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		const vm = self.findLocked(name) orelse return null;
		return vm.disk;
	}

	fn qmpOf(self: *Vms, name: []const u8) ?*qmp.Qmp {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		const vm = self.findLocked(name) orelse return null;
		return vm.qmp;
	}

	fn cloneDisk(self: *Vms, name: []const u8, from: []const u8) ![]u8 {
		const source = self.diskOf(from) orelse return error.NotFound;
		const dir = try std.fs.path.join(self.allocator, &.{ proc.repo(self.io, self.allocator), "vm", "runs", name });
		try std.Io.Dir.cwd().createDirPath(self.io, dir);

		const target = try std.fs.path.join(self.allocator, &.{ dir, "disk.qcow2" });
		const result = try exec.run(self.io, self.allocator, &.{ "qemu-img", "create", "-f", "qcow2", "-F", "qcow2", "-b", source, target, "32G" });
		defer result.deinit(self.allocator);

		if (result.code != 0) return error.ForkFailed;
		return target;
	}
};

fn humanRequest(args: json.Value) bool {
	const value = json.field(args, "human") orelse return false;
	return switch (value) {
		.bool => |flag| flag,
		else => false,
	};
}

fn balloonBytes(mem_mb: u32) u64 {
	return @as(u64, mem_mb) * 1024 * 1024 * 3 / 4;
}

test "the balloon target fits a four gigabyte guest" {
	try std.testing.expectEqual(@as(u64, 3221225472), balloonBytes(4096));
}

test "the idle destroy ignores the off switch and fires past the deadline" {
	try std.testing.expect(!idleDestroy(0, 0, 86400000));
	try std.testing.expect(!idleDestroy(1000, 5000, 5500));
	try std.testing.expect(idleDestroy(1000, 5000, 7000));
}

fn safePath(path: []const u8) bool {
	if (path.len == 0 or path.len > 256) return false;
	if (std.mem.indexOfScalar(u8, path, '\'') != null) return false;
	return path[0] == '/';
}

fn validName(name: []const u8) bool {
	if (name.len == 0 or name.len > 64) return false;

	for (name) |char| {
		if (std.ascii.isAlphanumeric(char)) continue;
		if (char == '-' or char == '_') continue;
		return false;
	}

	return true;
}

fn idleDestroyDefault() i64 {
	const raw = std.c.getenv("YUDAE_VM_IDLE_DESTROY_MS") orelse return 86400000;
	return @max(std.fmt.parseInt(i64, std.mem.span(raw), 10) catch 86400000, 0);
}

fn destroyIdleOf(args: json.Value) i64 {
	if (json.field(args, "destroyIdleMs")) |value| return @max(json.integer(value), 0);
	return idleDestroyDefault();
}

fn idleDestroy(destroy_ms: i64, used_ms: i64, now: i64) bool {
	return destroy_ms > 0 and now - used_ms > destroy_ms;
}

fn waitFile(io: Io, path: []const u8, timeout_ms: i64) !bool {
	const start = fmt.nowMs(io);

	while (fmt.nowMs(io) - start < timeout_ms) {
		if (proc.exists(io, path)) return true;
		sleep.ms(20);
	}

	return false;
}

fn kill(pid: i32) void {
	std.posix.kill(pid, std.posix.SIG.TERM) catch return;
}

fn pointer(io: Io, client: *qmp.Qmp, allocator: Allocator, x: f64, y: f64, screen: [2]u32) !void {
	_ = io;
	const width: f64 = @floatFromInt(if (screen[0] > 0) screen[0] else 2560);
	const height: f64 = @floatFromInt(if (screen[1] > 0) screen[1] else 1440);
	const px: i64 = @intFromFloat(@max(0, @min(32767, x / width * 32767.0)));
	const py: i64 = @intFromFloat(@max(0, @min(32767, y / height * 32767.0)));

	var body: std.Io.Writer.Allocating = .init(allocator);
	const writer = &body.writer;
	try writer.print("{{\"events\":[{{\"type\":\"abs\",\"data\":{{\"axis\":\"x\",\"value\":{d}}}}},{{\"type\":\"abs\",\"data\":{{\"axis\":\"y\",\"value\":{d}}}}}]}}", .{ px, py });

	_ = client.execute(allocator, "input-send-event", body.written()) catch return error.InputFailed;
}

fn buttonEvent(client: *qmp.Qmp, allocator: Allocator, button: []const u8, down: bool) !void {
	var body: std.Io.Writer.Allocating = .init(allocator);
	const writer = &body.writer;
	try writer.writeAll("{\"events\":[{\"type\":\"btn\",\"data\":{\"down\":");
	try writer.writeAll(if (down) "true" else "false");
	try writer.writeAll(",\"button\":");
	try std.json.Stringify.encodeJsonString(button, .{}, writer);
	try writer.writeAll("}}]}");

	_ = client.execute(allocator, "input-send-event", body.written()) catch return error.InputFailed;
}

test "the vm json carries the agent fields" {
	var vm: Vm = .{
		.name = @constCast("demo"),
		.dir = @constCast(""),
		.disk = @constCast(""),
		.agent = @constCast("agent-1"),
		.controller = @constCast("agent"),
		.harness = @constCast("opencode"),
		.session = @constCast("ses_123"),
		.session_title = @constCast("fix the vm"),
		.cid = 3,
		.cores = 2,
		.mem_mb = 2048,
		.gl = true,
		.created_ms = 1000,
		.used_ms = 2000,
		.agent_since_ms = 1500,
		.last_call_ms = 2500,
	};

	var buffer: [1024]u8 = undefined;
	var writer = std.Io.Writer.fixed(&buffer);
	try writeVm(&writer, &vm, 3000);

	const body = writer.buffered();
	try std.testing.expect(std.mem.indexOf(u8, body, "\"harness\":\"opencode\"") != null);
	try std.testing.expect(std.mem.indexOf(u8, body, "\"session\":\"ses_123\"") != null);
	try std.testing.expect(std.mem.indexOf(u8, body, "\"sessionTitle\":\"fix the vm\"") != null);
	try std.testing.expect(std.mem.indexOf(u8, body, "\"agentSinceMs\":1500") != null);
	try std.testing.expect(std.mem.indexOf(u8, body, "\"lastCallMs\":2500") != null);
}
