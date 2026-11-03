const std = @import("std");
const proc = @import("../../primitives/proc.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const Sample = struct {
	cpu_ticks: u64 = 0,
	rss_kb: u64 = 0,
};

pub const Cgroup = struct {
	path: []const u8,

	pub fn create(io: Io, allocator: Allocator, name: []const u8, mem_mb: u32, cores: u32) !Cgroup {
		const uid = std.os.linux.getuid();
		const path = try std.fmt.allocPrint(allocator, "/sys/fs/cgroup/user.slice/user-{d}.slice/user@{d}.service/yudae-vm-{s}", .{ uid, uid, name });

		std.Io.Dir.createDirAbsolute(io, path, .default_dir) catch |err| switch (err) {
			error.PathAlreadyExists => {},
			else => {
				std.debug.print("cgroup dir {s}: {s}\n", .{ path, @errorName(err) });
				return err;
			},
		};

		const memory = try std.fmt.allocPrint(allocator, "{d}", .{@as(u64, mem_mb) * 1024 * 1024});
		proc.writeFile(io, try std.fs.path.join(allocator, &.{ path, "memory.max" }), memory) catch |err| {
			std.debug.print("cgroup memory.max: {s}\n", .{@errorName(err)});
		};

		const quota = try std.fmt.allocPrint(allocator, "{d} 100000", .{cores * 100000});
		proc.writeFile(io, try std.fs.path.join(allocator, &.{ path, "cpu.max" }), quota) catch |err| {
			std.debug.print("cgroup cpu.max: {s}\n", .{@errorName(err)});
		};

		proc.writeFile(io, try std.fs.path.join(allocator, &.{ path, "io.weight" }), "50") catch {};

		return .{ .path = path };
	}

	pub fn open(allocator: Allocator, name: []const u8) Cgroup {
		const uid = std.os.linux.getuid();
		const path = std.fmt.allocPrint(allocator, "/sys/fs/cgroup/user.slice/user-{d}.slice/user@{d}.service/yudae-vm-{s}", .{ uid, uid, name }) catch "";
		return .{ .path = path };
	}

	pub fn attach(self: Cgroup, io: Io, pid: i32) void {
		if (pid <= 0) return;

		const text = std.fmt.allocPrint(std.heap.smp_allocator, "{d}", .{pid}) catch return;
		defer std.heap.smp_allocator.free(text);

		const path = std.fs.path.join(std.heap.smp_allocator, &.{ self.path, "cgroup.procs" }) catch return;
		defer std.heap.smp_allocator.free(path);

		proc.writeFile(io, path, text) catch |err| {
			std.debug.print("cgroup attach: {s}\n", .{@errorName(err)});
		};
	}

	pub fn sample(self: Cgroup, io: Io, allocator: Allocator) Sample {
		var out: Sample = .{};

		const cpu_path = std.fs.path.join(allocator, &.{ self.path, "cpu.stat" }) catch return out;
		defer allocator.free(cpu_path);

		if (proc.readFile(io, allocator, cpu_path)) |body| {
			defer allocator.free(body);

			var lines = std.mem.splitScalar(u8, body, '\n');
			while (lines.next()) |line| {
				if (!std.mem.startsWith(u8, line, "usage_usec ")) continue;
				const value = line["usage_usec ".len..];
				out.cpu_ticks = (std.fmt.parseInt(u64, value, 10) catch 0) / 1000;
				break;
			}
		} else |_| {}

		const memory_path = std.fs.path.join(allocator, &.{ self.path, "memory.current" }) catch return out;
		defer allocator.free(memory_path);

		if (proc.readFile(io, allocator, memory_path)) |body| {
			defer allocator.free(body);
			out.rss_kb = (std.fmt.parseInt(u64, std.mem.trim(u8, body, " \n"), 10) catch 0) / 1024;
		} else |_| {}

		return out;
	}

	pub fn park(self: Cgroup, io: Io, allocator: Allocator) void {
		const current = self.sample(io, allocator);
		if (current.rss_kb == 0) return;

		const bytes = current.rss_kb * 1024 * 3 / 4;
		reclaimBytes(io, allocator, self.path, bytes);
	}

	pub fn destroy(self: Cgroup, io: Io) void {
		std.Io.Dir.cwd().deleteTree(io, self.path) catch {};
	}
};

pub fn reclaim(io: Io, allocator: Allocator, path: []const u8, bytes: u64) void {
	reclaimBytes(io, allocator, path, bytes);
}

fn reclaimBytes(io: Io, allocator: Allocator, path: []const u8, bytes: u64) void {
	const text = std.fmt.allocPrint(allocator, "{d}", .{bytes}) catch return;
	defer allocator.free(text);

	const file = std.fs.path.join(allocator, &.{ path, "memory.reclaim" }) catch return;
	defer allocator.free(file);

	proc.writeFile(io, file, text) catch {};
}

pub fn sampleProc(io: Io, allocator: Allocator, pid: i32) Sample {
	if (pid <= 0) return .{};

	const stat_path = std.fmt.allocPrint(allocator, "/proc/{d}/stat", .{pid}) catch return .{};
	defer allocator.free(stat_path);

	const status_path = std.fmt.allocPrint(allocator, "/proc/{d}/status", .{pid}) catch return .{};
	defer allocator.free(status_path);

	var out: Sample = .{};

	if (proc.readFile(io, allocator, stat_path)) |body| {
		defer allocator.free(body);

		var it = std.mem.tokenizeAny(u8, body, " \n");

		var field: usize = 1;
		while (it.next()) |part| : (field += 1) {
			if (field == 14) out.cpu_ticks = std.fmt.parseInt(u64, part, 10) catch 0;
			if (field == 15) {
				out.cpu_ticks += std.fmt.parseInt(u64, part, 10) catch 0;
				break;
			}
		}
	} else |_| {}

	if (proc.readFile(io, allocator, status_path)) |body| {
		defer allocator.free(body);

		var lines = std.mem.splitScalar(u8, body, '\n');
		while (lines.next()) |line| {
			if (!std.mem.startsWith(u8, line, "VmRSS:")) continue;
			const value = std.mem.trim(u8, line["VmRSS:".len..], " \tkB");
			out.rss_kb = std.fmt.parseInt(u64, value, 10) catch 0;
			break;
		}
	} else |_| {}

	return out;
}
