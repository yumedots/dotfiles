const std = @import("std");
const setStr = @import("opencode.zig").setStr;
const hubmod = @import("../hub.zig");
const proc = @import("../primitives/proc.zig");
const sleep = @import("../primitives/sleep.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const max_cores = 64;
pub const max_top = 48;

fn sanitize(name: []const u8) []const u8 {
	for (name) |byte| {
		if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '-') return "";
	}

	return name;
}

const Core = struct { pct: f64 = 0 };

const Process = struct {
	pid: i32 = 0,
	comm: [16]u8 = @splat(0),
	comm_len: usize = 0,
	cpu: f64 = 0,
	rss_kb: i64 = 0,

	fn name(self: *const Process) []const u8 {
		return self.comm[0..self.comm_len];
	}
};

pub const TopOut = struct {
	pid: i32,
	name: [16]u8 = undefined,
	name_len: usize = 0,
	cpu: f64,

	pub fn getName(self: *const TopOut) []const u8 {
		return self.name[0..self.name_len];
	}
};

const ProcessOut = struct {
	pid: i32,
	name: []const u8,
	cmd: []const u8,
	value: f64,
};

const CpuOut = struct {
	pct: f64,
	cores: []f64,
};

const MemoryOut = struct {
	total: i64,
	used: i64,
	available: i64,
	cached: i64,
	buffers: i64,
	swapTotal: i64,
	swapUsed: i64,
	pool: i64,
	committed: i64,
	ramFree: i64,
	swapFree: i64,
	free: i64,
	pct: f64,
};

const BatteryOut = struct {
	present: bool,
	pct: f64,
	charging: bool,
	state: []const u8,
};

const Out = struct {
	governor: []const u8,
	governors: [][]const u8,
	cpu: CpuOut,
	memory: MemoryOut,
	battery: BatteryOut,
	processes: []ProcessOut,
	byCpu: []ProcessOut,
	byMem: []ProcessOut,
};

pub const System = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	cpu_pct: f64 = 0,
	cores: [max_cores]f64 = @splat(0),
	core_count: usize = 0,
	mem_total: i64 = 0,
	mem_used: i64 = 0,
	mem_free: i64 = 0,
	mem_pct: f64 = 0,
	battery_present: bool = false,
	battery_pct: f64 = 0,
	battery_charging: bool = false,
	battery_state: []u8 = &.{},
	mem_available: i64 = 0,
	mem_cached: i64 = 0,
	mem_buffers: i64 = 0,
	swap_total: i64 = 0,
	swap_used: i64 = 0,
	mem_pool: i64 = 0,
	mem_committed: i64 = 0,
	governors: []u8 = &.{},
	governor: []u8 = &.{},
	top: [max_top]Process = @splat(.{}),
	top_count: usize = 0,
	all: std.ArrayListUnmanaged(Process) = .empty,
	mem_top: [max_top]Process = @splat(.{}),
	mem_count: usize = 0,
	previous: std.AutoHashMapUnmanaged(i32, i64) = .empty,
	last_cpu: [max_cores + 1][4]i64 = undefined,
	last_cpu_count: usize = 0,
	last_proc_at: i64 = 0,

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*System {
		const self = try allocator.create(System);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.scratch = std.heap.ArenaAllocator.init(allocator),
		};

		return self;
	}

	pub fn provider(self: *System) hubmod.Provider {
		return .{ .key = "system", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *System = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn topRows(self: *System, out: *[max_top]TopOut) usize {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		for (self.top[0..self.top_count], 0..) |*entry, index| {
			out[index] = .{ .pid = entry.pid, .name = entry.comm, .name_len = entry.comm_len, .cpu = entry.cpu };
		}

		return self.top_count;
	}

	pub fn allRows(self: *System, arena: Allocator) ![]TopOut {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		const out = try arena.alloc(TopOut, self.all.items.len);

		for (self.all.items, 0..) |*entry, index| {
			out[index] = .{ .pid = entry.pid, .name = entry.comm, .name_len = entry.comm_len, .cpu = entry.cpu };
		}

		return out;
	}

	pub fn start(self: *System) !void {
		self.sampleProcesses();

		const thread = try std.Thread.spawn(.{}, loop, .{self});
		thread.detach();
	}

	fn loop(self: *System) void {
		self.sampleCpu();
		sleep.ms(150);
		self.sampleCpu();

		var tick: usize = 0;

		while (true) {
			sleep.ms(1850);
			tick += 1;

			self.sampleCpu();
			self.sampleMemory();
			self.sampleBattery();
			self.sampleGovernors();

			if (tick % 3 == 0) self.sampleProcesses();

			self.hub.publish();
		}
	}

	fn sampleCpu(self: *System) void {
		var buffer: [16384]u8 = undefined;
		var file = std.Io.Dir.cwd().openFile(self.io, "/proc/stat", .{}) catch return;
		defer file.close(self.io);

		var reader = file.reader(self.io, &buffer);
		var list: std.ArrayList(u8) = .empty;
		defer list.deinit(self.allocator);

		var chunk: [4096]u8 = undefined;
		while (true) {
			const count = reader.interface.readSliceShort(&chunk) catch break;
			if (count == 0) break;
			list.appendSlice(self.allocator, chunk[0..count]) catch break;
		}

		var now: [max_cores + 1][4]i64 = undefined;
		var count_cores: usize = 0;

		var lines = std.mem.splitScalar(u8, list.items, '\n');
		while (lines.next()) |line| {
			if (!std.mem.startsWith(u8, line, "cpu")) continue;
			if (count_cores >= max_cores + 1) break;

			var fields = std.mem.tokenizeAny(u8, line, " \t");
			_ = fields.next() orelse continue;

			now[count_cores] = .{ 0, 0, 0, 0 };
			var field: usize = 0;
			while (fields.next()) |value| : (field += 1) {
				if (field >= 4) break;
				now[count_cores][field] = std.fmt.parseInt(i64, value, 10) catch 0;
			}

			count_cores += 1;
		}

		if (count_cores == 0) return;

		self.mutex.lockUncancelable(self.io);
		var total_pct: f64 = 0;

		if (count_cores == self.last_cpu_count) {
			total_pct = percentOf(self.last_cpu[0], now[0]) * 100;

			var core: usize = 1;
			while (core < count_cores) : (core += 1) {
				self.cores[core - 1] = percentOf(self.last_cpu[core], now[core]) * 100;
			}

			self.core_count = count_cores - 1;
		}

		self.cpu_pct = total_pct;
		self.last_cpu = now;
		self.last_cpu_count = count_cores;
		self.mutex.unlock(self.io);
	}

	fn percentOf(before: [4]i64, after: [4]i64) f64 {
		const idle_before = before[3];
		const idle_after = after[3];
		const total_before = before[0] + before[1] + before[2] + before[3];
		const total_after = after[0] + after[1] + after[2] + after[3];

		const total = total_after - total_before;
		if (total <= 0) return 0;

		return 1.0 - @as(f64, @floatFromInt(idle_after - idle_before)) / @as(f64, @floatFromInt(total));
	}

	fn sampleMemory(self: *System) void {
		const body = proc.readFile(self.io, self.allocator, "/proc/meminfo") catch return;
		defer self.allocator.free(body);

		var total: i64 = 0;
		var available: i64 = 0;
		var free_mem: i64 = 0;
		var cached: i64 = 0;
		var buffers: i64 = 0;
		var swap_total: i64 = 0;
		var swap_free: i64 = 0;

		var lines = std.mem.splitScalar(u8, body, '\n');
		while (lines.next()) |line| {
			if (std.mem.startsWith(u8, line, "MemTotal:")) total = memValue(line);
			if (std.mem.startsWith(u8, line, "MemAvailable:")) available = memValue(line);
			if (std.mem.startsWith(u8, line, "MemFree:")) free_mem = memValue(line);
			if (std.mem.startsWith(u8, line, "Cached:")) cached = memValue(line);
			if (std.mem.startsWith(u8, line, "Buffers:")) buffers = memValue(line);
			if (std.mem.startsWith(u8, line, "SwapTotal:")) swap_total = memValue(line);
			if (std.mem.startsWith(u8, line, "SwapFree:")) swap_free = memValue(line);
		}

		if (total <= 0) return;

		self.mutex.lockUncancelable(self.io);
		self.mem_total = total;
		self.mem_free = free_mem;
		self.mem_available = available;
		self.mem_used = total - available;
		const swap_used = @max(0, swap_total - swap_free);
		const pool = total + swap_total;
		const committed = self.mem_used + swap_used;

		self.mem_cached = cached;
		self.mem_buffers = buffers;
		self.swap_total = swap_total;
		self.swap_used = swap_used;
		self.mem_pool = pool;
		self.mem_committed = committed;
		self.mem_pct = if (pool > 0) 100.0 * @as(f64, @floatFromInt(committed)) / @as(f64, @floatFromInt(pool)) else 0;
		self.mutex.unlock(self.io);
	}

	fn memValue(line: []const u8) i64 {
		const colon = std.mem.indexOfScalar(u8, line, ':') orelse return 0;
		var fields = std.mem.tokenizeAny(u8, line[colon + 1 ..], " \t");

		return std.fmt.parseInt(i64, fields.next() orelse "0", 10) catch 0;
	}

	fn sampleBattery(self: *System) void {
		const body = proc.readFile(self.io, self.allocator, "/sys/class/power_supply/BAT0/uevent") catch return;
		defer self.allocator.free(body);

		var present = false;
		var pct: f64 = 0;
		var state: []const u8 = "";

		var lines = std.mem.splitScalar(u8, body, '\n');
		while (lines.next()) |line| {
			if (std.mem.startsWith(u8, line, "POWER_SUPPLY_CAPACITY=")) {
				pct = std.fmt.parseFloat(f64, line["POWER_SUPPLY_CAPACITY=".len..]) catch 0;
				present = true;
			}

			if (std.mem.startsWith(u8, line, "POWER_SUPPLY_STATUS=")) {
				state = std.mem.trim(u8, line["POWER_SUPPLY_STATUS=".len..], " \r");
			}
		}

		self.mutex.lockUncancelable(self.io);
		self.battery_present = present;
		self.battery_pct = pct;
		self.battery_charging = std.mem.eql(u8, state, "Charging");
		self.battery_state = self.allocator.dupe(u8, if (state.len > 0) state else "") catch &.{};
		self.mutex.unlock(self.io);
	}

	pub fn sampleProcesses(self: *System) void {
		const list = proc.listProcesses(self.io, self.allocator) catch return;
		defer self.allocator.free(list);
		const now = std.Io.Clock.real.now(self.io).toMilliseconds();
		const seconds = if (self.last_proc_at > 0 and now > self.last_proc_at)
			@as(f64, @floatFromInt(now - self.last_proc_at)) / 1000.0
		else
			0;
		self.last_proc_at = now;

		var next: std.AutoHashMapUnmanaged(i32, i64) = .empty;
		var top: [max_top]Process = @splat(.{});
		var top_count: usize = 0;
		var mem_top: [max_top]Process = @splat(.{});
		var mem_count: usize = 0;
		var all: std.ArrayListUnmanaged(Process) = .empty;

		for (list) |*entry| {
			const before = self.previous.get(entry.pid) orelse entry.ticks;
			const delta = entry.ticks - before;

			next.put(self.allocator, entry.pid, entry.ticks) catch continue;

			const candidate = Process{
				.pid = entry.pid,
				.comm = entry.comm,
				.comm_len = entry.comm_len,
				.cpu = if (delta > 0) cpuPercent(delta, seconds) else 0,
				.rss_kb = entry.rss_kb,
			};

			all.append(self.allocator, candidate) catch {};

			if (delta <= 0) continue;

			insertTop(&top, &top_count, candidate);
			insertTopByMem(&mem_top, &mem_count, candidate);
		}

		self.previous.deinit(self.allocator);
		self.previous = next;

		self.mutex.lockUncancelable(self.io);
		var previous_all = self.all;
		self.all = all;
		self.top = top;
		self.top_count = top_count;
		self.mem_top = mem_top;
		self.mem_count = mem_count;
		self.mutex.unlock(self.io);

		previous_all.deinit(self.allocator);
	}

	fn insertTopByMem(list: *[max_top]Process, count: *usize, candidate: Process) void {
		var at: usize = 0;

		while (at < count.* and list[at].rss_kb >= candidate.rss_kb) : (at += 1) {}

		if (at >= max_top) return;

		const limit = @min(count.*, max_top - 1);
		var index = limit;
		while (index > at) : (index -= 1) list[index] = list[index - 1];

		list[at] = candidate;
		if (count.* < max_top) count.* += 1;
	}

	fn insertTop(list: *[max_top]Process, count: *usize, candidate: Process) void {
		var at: usize = 0;

		while (at < count.* and list[at].cpu >= candidate.cpu) : (at += 1) {}

		if (at >= max_top) return;

		const limit = @min(count.*, max_top - 1);
		var index = limit;
		while (index > at) : (index -= 1) list[index] = list[index - 1];

		list[at] = candidate;
		if (count.* < max_top) count.* += 1;
	}

	pub fn setGovernor(self: *System, name: []const u8) void {
		const clean = sanitize(name);
		if (clean.len == 0) return;

		const script = std.fmt.allocPrint(self.allocator, "echo '{s}' | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null", .{clean}) catch return;
		defer self.allocator.free(script);

		const exec = @import("../primitives/exec.zig");
		const result = exec.run(self.io, self.allocator, &.{ "sh", "-c", script }) catch return;
		result.deinit(self.allocator);

		self.sampleGovernors();
		self.hub.publish();
	}

	fn sampleGovernors(self: *System) void {
		const available = proc.readFile(self.io, self.allocator, "/sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors") catch return;
		defer self.allocator.free(available);

		const current = proc.readFile(self.io, self.allocator, "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor") catch return;
		defer self.allocator.free(current);

		self.mutex.lockUncancelable(self.io);
		setStr(self.allocator, &self.governors, std.mem.trim(u8, available, " \n\r\t")) catch {};
		setStr(self.allocator, &self.governor, std.mem.trim(u8, current, " \n\r\t")) catch {};
		self.mutex.unlock(self.io);
	}

	fn render(self: *System, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);
		const arena = self.scratch.allocator();

		var governor_list: std.ArrayListUnmanaged([]const u8) = .empty;
		var governor_it = std.mem.tokenizeAny(u8, self.governors, " \t\n");

		while (governor_it.next()) |name| try governor_list.append(arena, name);

		var cores: std.ArrayListUnmanaged(f64) = .empty;
		for (self.cores[0..self.core_count]) |core| try cores.append(arena, @round(core * 10) / 10);

		var processes: std.ArrayListUnmanaged(ProcessOut) = .empty;
		for (self.top[0..self.top_count]) |*entry| {
			try processes.append(arena, .{
				.pid = entry.pid,
				.name = entry.name(),
				.cmd = entry.name(),
				.value = @round(entry.cpu * 10) / 10,
			});
		}

		var by_mem: std.ArrayListUnmanaged(ProcessOut) = .empty;
		for (self.mem_top[0..self.mem_count]) |*entry| {
			try by_mem.append(arena, .{
				.pid = entry.pid,
				.name = entry.name(),
				.cmd = entry.name(),
				.value = @floatFromInt(entry.rss_kb),
			});
		}

		const out = Out{
			.governor = self.governor,
			.governors = governor_list.items,
			.cpu = .{ .pct = @round(self.cpu_pct * 10) / 10, .cores = cores.items },
			.memory = .{
				.total = self.mem_total,
				.used = self.mem_used,
				.available = self.mem_available,
				.cached = self.mem_cached,
				.buffers = self.mem_buffers,
				.swapTotal = self.swap_total,
				.swapUsed = self.swap_used,
				.pool = self.mem_pool,
				.committed = self.mem_committed,
				.ramFree = @max(0, self.mem_total - self.mem_used - self.mem_cached - self.mem_buffers),
				.swapFree = @max(0, self.swap_total - self.swap_used),
				.free = @max(0, self.mem_pool - self.mem_committed - self.mem_cached - self.mem_buffers),
				.pct = @round(self.mem_pct * 10) / 10,
			},
			.battery = .{
				.present = self.battery_present,
				.pct = self.battery_pct,
				.charging = self.battery_charging,
				.state = self.battery_state,
			},
			.processes = processes.items,
			.byCpu = processes.items,
			.byMem = by_mem.items,
		};

		try writer.print("{f}", .{std.json.fmt(out, .{})});
	}
};

fn cpuPercent(delta: i64, seconds: f64) f64 {
	if (seconds <= 0 or delta <= 0) return 0;
	return @as(f64, @floatFromInt(delta)) / seconds;
}

test "cpu percent uses the sample window" {
	try std.testing.expectApproxEqAbs(@as(f64, 100), cpuPercent(555, 5.55), 0.001);
	try std.testing.expectApproxEqAbs(@as(f64, 50), cpuPercent(100, 2.0), 0.001);
	try std.testing.expectEqual(@as(f64, 0), cpuPercent(10, 0));
}

test "the full list reports every sampled process" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();
	const io = std.testing.io;

	var hub: hubmod.Hub = .{ .allocator = allocator, .io = io };
	const system = try System.create(allocator, io, &hub);

	var idle = Process{ .pid = 42, .rss_kb = 8 };
	@memcpy(idle.comm[0..7], "kthread");
	idle.comm_len = 7;
	try system.all.append(allocator, idle);

	try system.all.append(allocator, .{ .pid = 43, .cpu = 12.5 });

	const rows = try system.allRows(allocator);

	try std.testing.expectEqual(2, rows.len);
	try std.testing.expectEqual(@as(i32, 42), rows[0].pid);
	try std.testing.expectEqualStrings("kthread", rows[0].getName());
	try std.testing.expectEqual(@as(f64, 12.5), rows[1].cpu);
}

test "one synchronous sample fills the list before the first snapshot" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();
	const io = std.testing.io;

	var hub: hubmod.Hub = .{ .allocator = allocator, .io = io };
	const system = try System.create(allocator, io, &hub);

	try std.testing.expectEqual(@as(usize, 0), system.all.items.len);

	system.sampleProcesses();

	try std.testing.expect(system.all.items.len > 100);

	const rows = try system.allRows(allocator);
	try std.testing.expectEqual(system.all.items.len, rows.len);
}
