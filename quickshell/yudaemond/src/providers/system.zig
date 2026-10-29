const std = @import("std");
const setStr = @import("opencode.zig").setStr;
const hubmod = @import("../hub.zig");
const color = @import("../primitives/color.zig");
const config = @import("../primitives/config.zig");
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
	valueText: []const u8,
	color: []const u8 = "",
};

const CpuOut = struct {
	pct: f64,
	color: []const u8,
	ink: []const u8,
	coreInk: [][]const u8,
	cores: []f64,
	model: []const u8,
	spec: []const u8,
	threads: i64,
	coreCount: i64,
	mhz: f64,
	cache: f64,
};

const MemoryOut = struct {
	color: []const u8,
	ink: []const u8,
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
	totalText: []const u8,
	usedText: []const u8,
	availableText: []const u8,
	cachedText: []const u8,
	buffersText: []const u8,
	swapTotalText: []const u8,
	swapUsedText: []const u8,
	poolText: []const u8,
	committedText: []const u8,
	ramFreeText: []const u8,
	swapFreeText: []const u8,
	freeText: []const u8,
};

const BatteryOut = struct {
	color: []const u8,
	present: bool,
	pct: f64,
	charging: bool,
	state: []const u8,
};

const PanelOut = struct {
	field: []const u8,
	query: []const u8,
	rows: []ProcessOut,
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
	panel: PanelOut,
};

const Palette = struct {
	mono: bool = true,
	red: color.Rgb = .{ 0xe0, 0x52, 0x52 },
	cpu_base: color.Rgb = .{ 0xa7, 0x8b, 0xfa },
	cpu_base_mono: color.Rgb = .{ 0xff, 0xff, 0xff },
	cpu_peak: color.Rgb = .{ 0xe0, 0x52, 0x52 },
	cpu_peak_mono: color.Rgb = .{ 0x9a, 0x9a, 0x9a },
	cpu_idle: color.Rgb = .{ 0x2f, 0x2f, 0x2f },
	memory_base: color.Rgb = .{ 0x7b, 0xd8, 0x8f },
	memory_base_mono: color.Rgb = .{ 0xff, 0xff, 0xff },
	memory_warn: color.Rgb = .{ 0xd8, 0xb0, 0x4a },
	memory_warn_mono: color.Rgb = .{ 0xcf, 0xcf, 0xcf },
	memory_danger: color.Rgb = .{ 0xe0, 0x52, 0x52 },
	memory_danger_mono: color.Rgb = .{ 0x6f, 0x6f, 0x6f },
	memory_warn_at: f64 = 60,
	memory_danger_at: f64 = 85,
	power_base: color.Rgb = .{ 0x7b, 0xd8, 0x8f },
	power_warn: color.Rgb = .{ 0xd8, 0xb0, 0x4a },
	power_danger: color.Rgb = .{ 0xe0, 0x52, 0x52 },
	power_warn_at: f64 = 30,
	power_danger_at: f64 = 15,

	fn load(io: Io, allocator: Allocator) Palette {
		var palette: Palette = .{};

		const cfg = config.Config.load(io, allocator) catch return palette;
		defer cfg.deinit();

		palette.mono = cfg.boolean("mono", palette.mono);
		palette.red = pick(cfg, "red", palette.red);
		palette.cpu_base = pick(cfg, "cpuBase", palette.cpu_base);
		palette.cpu_base_mono = pick(cfg, "cpuBaseMono", palette.cpu_base_mono);
		palette.cpu_peak = pick(cfg, "cpuPeak", palette.cpu_peak);
		palette.cpu_peak_mono = pick(cfg, "cpuPeakMono", palette.cpu_peak_mono);
		palette.cpu_idle = pick(cfg, "cpuIdle", palette.cpu_idle);
		palette.memory_base = pick(cfg, "memoryBase", palette.memory_base);
		palette.memory_base_mono = pick(cfg, "memoryBaseMono", palette.memory_base_mono);
		palette.memory_warn = pick(cfg, "memoryWarn", palette.memory_warn);
		palette.memory_warn_mono = pick(cfg, "memoryWarnMono", palette.memory_warn_mono);
		palette.memory_danger = pick(cfg, "memoryDanger", palette.memory_danger);
		palette.memory_danger_mono = pick(cfg, "memoryDangerMono", palette.memory_danger_mono);
		palette.memory_warn_at = cfg.number("memoryWarnAt", palette.memory_warn_at);
		palette.memory_danger_at = cfg.number("memoryDangerAt", palette.memory_danger_at);
		palette.power_base = pick(cfg, "powerBase", palette.power_base);
		palette.power_warn = pick(cfg, "powerWarn", palette.power_warn);
		palette.power_danger = pick(cfg, "powerDanger", palette.power_danger);
		palette.power_warn_at = cfg.number("powerWarnAt", palette.power_warn_at);
		palette.power_danger_at = cfg.number("powerDangerAt", palette.power_danger_at);

		return palette;
	}

	fn cpuAccent(self: Palette) color.Rgb {
		return if (self.mono) self.cpu_base_mono else self.cpu_base;
	}

	fn cpuPeakColor(self: Palette) color.Rgb {
		return if (self.mono) self.cpu_peak_mono else self.cpu_peak;
	}

	fn memoryAccent(self: Palette) color.Rgb {
		return if (self.mono) self.memory_base_mono else self.memory_base;
	}

	fn memoryWarnColor(self: Palette) color.Rgb {
		return if (self.mono) self.memory_warn_mono else self.memory_warn;
	}

	fn memoryDangerColor(self: Palette) color.Rgb {
		return if (self.mono) self.memory_danger_mono else self.memory_danger;
	}

	fn cpuInk(self: Palette, pct: f64) color.Rgb {
		return color.mix(self.cpuAccent(), self.cpuPeakColor(), pct / 100);
	}

	fn memoryInk(self: Palette, pct: f64) color.Rgb {
		return color.danger(self.memoryAccent(), self.memoryWarnColor(), self.memoryDangerColor(), self.memory_warn_at, self.memory_danger_at, pct);
	}
};

fn pick(cfg: config.Config, name: []const u8, fallback: color.Rgb) color.Rgb {
	return color.parse(cfg.color(name) orelse "") orelse fallback;
}

fn inkText(arena: Allocator, rgb: color.Rgb) ![]const u8 {
	var buffer: [7]u8 = undefined;

	return arena.dupe(u8, color.hex(&buffer, rgb));
}

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
	cpu_model: []u8 = &.{},
	cpu_spec: []u8 = &.{},
	cpu_cores: i64 = 0,
	cpu_threads: i64 = 0,
	cpu_mhz: f64 = 0,
	cpu_cache: f64 = 0,
	panel_field: []u8 = &.{},
	panel_query: []u8 = &.{},
	ignore: [][]u8 = &.{},
	panel_cpu: []i32 = &.{},
	panel_mem: []i32 = &.{},
	palette: Palette = .{},

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
		self.palette = Palette.load(self.io, self.allocator);
		self.loadCpuInfo();
		self.loadPanel();
		self.sampleProcesses();

		const thread = try std.Thread.spawn(.{}, loop, .{self});
		thread.detach();
	}

	fn loadPanel(self: *System) void {
		setStr(self.allocator, &self.panel_field, "pcpu") catch {};

		const cfg = config.Config.load(self.io, self.allocator) catch return;
		defer cfg.deinit();

		self.ignore = cfg.strings("psIgnore", self.allocator) catch &.{};
	}

	pub fn setPanel(self: *System, field: []const u8, query: []const u8) void {
		self.mutex.lockUncancelable(self.io);

		if (field.len > 0) setStr(self.allocator, &self.panel_field, field) catch {};
		setStr(self.allocator, &self.panel_query, query) catch {};

		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn ignored(self: *System, name: []const u8) bool {
		for (self.ignore) |entry| {
			if (std.mem.eql(u8, entry, name)) return true;
		}

		return false;
	}

	fn wanted(self: *System, row: ProcessOut) bool {
		if (self.ignored(row.name)) return false;
		if (self.panel_query.len == 0) return true;

		return containsIgnoreCase(row.name, self.panel_query) or containsIgnoreCase(row.cmd, self.panel_query);
	}

	fn panelRows(self: *System, arena: Allocator, rss: bool, rows: []const ProcessOut) ![]ProcessOut {
		var kept: std.ArrayListUnmanaged(ProcessOut) = .empty;

		for (rows) |row| {
			if (!self.wanted(row)) continue;

			try kept.append(arena, row);
		}

		if (self.panel_query.len > 0) return kept.items;

		var pids: std.ArrayListUnmanaged(i32) = .empty;
		for (kept.items) |row| try pids.append(arena, row.pid);

		const previous = if (rss) &self.panel_mem else &self.panel_cpu;
		const held = try holdOrder(arena, previous.*, pids.items);

		self.allocator.free(previous.*);
		previous.* = self.allocator.dupe(i32, held) catch &.{};

		var ordered: std.ArrayListUnmanaged(ProcessOut) = .empty;

		for (held) |pid| {
			for (kept.items) |row| {
				if (row.pid != pid) continue;

				try ordered.append(arena, row);
				break;
			}
		}

		return ordered.items;
	}

	const CpuInfo = struct { model: []const u8 = "", cores: i64 = 0, threads: i64 = 0, mhz: f64 = 0, cache: f64 = 0 };

	fn parseCpuInfo(text: []const u8) CpuInfo {
		var info: CpuInfo = .{};

		var lines = std.mem.splitScalar(u8, text, '\n');
		while (lines.next()) |line| {
			const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;

			const key = std.mem.trim(u8, line[0..colon], " \t");
			const value = std.mem.trim(u8, line[colon + 1 ..], " \t\r");

			if (std.mem.eql(u8, key, "processor")) {
				info.threads += 1;
			} else if (std.mem.eql(u8, key, "model name") and info.model.len == 0) {
				info.model = value;
			} else if (std.mem.eql(u8, key, "cpu cores") and info.cores == 0) {
				info.cores = std.fmt.parseInt(i64, value, 10) catch 0;
			} else if (std.mem.eql(u8, key, "cpu MHz")) {
				info.mhz = @max(info.mhz, std.fmt.parseFloat(f64, value) catch 0);
			} else if (std.mem.eql(u8, key, "cache size") and info.cache == 0) {
				info.cache = leadingFloat(value);
			}
		}

		if (info.cores == 0) info.cores = info.threads;

		return info;
	}

	fn leadingFloat(text: []const u8) f64 {
		var end: usize = 0;

		while (end < text.len and (std.ascii.isDigit(text[end]) or text[end] == '.')) end += 1;

		return std.fmt.parseFloat(f64, text[0..end]) catch 0;
	}

	fn specLine(allocator: Allocator, info: CpuInfo) ![]u8 {
		var out: std.ArrayList(u8) = .empty;
		errdefer out.deinit(allocator);

		var buf: [64]u8 = undefined;

		if (info.threads > 0) try out.appendSlice(allocator, try std.fmt.bufPrint(&buf, "{d} threads", .{info.threads}));
		if (info.cores > 0 and info.cores != info.threads) try out.appendSlice(allocator, try std.fmt.bufPrint(&buf, "{s}{d} cores", .{if (out.items.len > 0) " · " else "", info.cores}));
		if (info.mhz > 0) try out.appendSlice(allocator, try std.fmt.bufPrint(&buf, "{s}{d:.1} GHz", .{if (out.items.len > 0) " · " else "", info.mhz / 1000}));
		if (info.cache > 0) {
			const part = if (info.cache >= 1024)
				try std.fmt.bufPrint(&buf, "{s}{d} MB", .{if (out.items.len > 0) " · " else "", @as(i64, @intFromFloat(@round(info.cache / 1024)))})
			else
				try std.fmt.bufPrint(&buf, "{s}{d} KB", .{if (out.items.len > 0) " · " else "", @as(i64, @intFromFloat(info.cache))});

			try out.appendSlice(allocator, part);
		}

		return out.toOwnedSlice(allocator);
	}

	fn loadCpuInfo(self: *System) void {
		const body = proc.readFile(self.io, self.allocator, "/proc/cpuinfo") catch return;
		defer self.allocator.free(body);

		const info = parseCpuInfo(body);
		const spec = specLine(self.allocator, info) catch return;
		defer self.allocator.free(spec);

		self.mutex.lockUncancelable(self.io);
		setStr(self.allocator, &self.cpu_model, info.model) catch {};
		setStr(self.allocator, &self.cpu_spec, spec) catch {};
		self.cpu_cores = info.cores;
		self.cpu_threads = info.threads;
		self.cpu_mhz = info.mhz;
		self.cpu_cache = info.cache;
		self.mutex.unlock(self.io);
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
		const first = self.last_proc_at == 0;
		const seconds = if (!first and now > self.last_proc_at)
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

			insertTopByMem(&mem_top, &mem_count, candidate);

			if (delta <= 0 and !first) continue;

			insertTop(&top, &top_count, candidate);
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

		var core_ink: std.ArrayListUnmanaged([]const u8) = .empty;
		for (cores.items) |core| try core_ink.append(arena, try inkText(arena, color.mix(self.palette.cpu_idle, self.palette.cpuAccent(), core / 100)));

		var processes: std.ArrayListUnmanaged(ProcessOut) = .empty;
		for (self.top[0..self.top_count]) |*entry| {
			const load = @round(entry.cpu * 10) / 10;

			try processes.append(arena, .{
				.pid = entry.pid,
				.name = entry.name(),
				.cmd = entry.name(),
				.value = load,
				.valueText = try std.fmt.allocPrint(arena, "{d:.1}%", .{entry.cpu}),
				.color = try inkText(arena, self.palette.cpuInk(load)),
			});
		}

		var by_mem: std.ArrayListUnmanaged(ProcessOut) = .empty;
		for (self.mem_top[0..self.mem_count]) |*entry| {
			const share = if (self.mem_pool > 0) std.math.clamp(100 * @as(f64, @floatFromInt(entry.rss_kb)) / @as(f64, @floatFromInt(self.mem_pool)), 0, 100) else 0;

			try by_mem.append(arena, .{
				.pid = entry.pid,
				.name = entry.name(),
				.cmd = entry.name(),
				.value = @floatFromInt(entry.rss_kb),
				.valueText = try kbText(arena, entry.rss_kb),
				.color = try inkText(arena, self.palette.memoryInk(share)),
			});
		}

		const cpu_pct = @round(self.cpu_pct * 10) / 10;
		const memory_pct = @round(self.mem_pct * 10) / 10;

		const ram_free = @max(0, self.mem_total - self.mem_used - self.mem_cached - self.mem_buffers);
		const swap_free = @max(0, self.swap_total - self.swap_used);
		const pool_free = @max(0, self.mem_pool - self.mem_committed - self.mem_cached - self.mem_buffers);

		const out = Out{
			.governor = self.governor,
			.governors = governor_list.items,
			.cpu = .{
				.pct = cpu_pct,
				.color = try inkText(arena, color.mix(self.palette.cpu_base, self.palette.red, cpu_pct / 100)),
				.ink = try inkText(arena, self.palette.cpuInk(cpu_pct)),
				.coreInk = core_ink.items,
				.cores = cores.items,
				.model = self.cpu_model,
				.spec = self.cpu_spec,
				.threads = self.cpu_threads,
				.coreCount = self.cpu_cores,
				.mhz = self.cpu_mhz,
				.cache = self.cpu_cache,
			},
			.memory = .{
				.color = try inkText(arena, color.danger(self.palette.memory_base, self.palette.memory_warn, self.palette.memory_danger, self.palette.memory_warn_at, self.palette.memory_danger_at, memory_pct)),
				.ink = try inkText(arena, self.palette.memoryInk(memory_pct)),
				.total = self.mem_total,
				.used = self.mem_used,
				.available = self.mem_available,
				.cached = self.mem_cached,
				.buffers = self.mem_buffers,
				.swapTotal = self.swap_total,
				.swapUsed = self.swap_used,
				.pool = self.mem_pool,
				.committed = self.mem_committed,
				.ramFree = ram_free,
				.swapFree = swap_free,
				.free = pool_free,
				.pct = memory_pct,
				.totalText = try kbText(arena, self.mem_total),
				.usedText = try kbText(arena, self.mem_used),
				.availableText = try kbText(arena, self.mem_available),
				.cachedText = try kbText(arena, self.mem_cached),
				.buffersText = try kbText(arena, self.mem_buffers),
				.swapTotalText = try kbText(arena, self.swap_total),
				.swapUsedText = try kbText(arena, self.swap_used),
				.poolText = try kbText(arena, self.mem_pool),
				.committedText = try kbText(arena, self.mem_committed),
				.ramFreeText = try kbText(arena, ram_free),
				.swapFreeText = try kbText(arena, swap_free),
				.freeText = try kbText(arena, pool_free),
			},
			.battery = .{
				.color = try inkText(arena, color.danger(self.palette.power_base, self.palette.power_warn, self.palette.power_danger, self.palette.power_warn_at, self.palette.power_danger_at, self.battery_pct)),
				.present = self.battery_present,
				.pct = self.battery_pct,
				.charging = self.battery_charging,
				.state = self.battery_state,
			},
			.processes = processes.items,
			.byCpu = processes.items,
			.byMem = by_mem.items,
			.panel = .{
				.field = self.panel_field,
				.query = self.panel_query,
				.rows = try self.panelRows(arena, std.mem.eql(u8, self.panel_field, "rss"), if (std.mem.eql(u8, self.panel_field, "rss")) by_mem.items else processes.items),
			},
		};

		try writer.print("{f}", .{std.json.fmt(out, .{})});
	}
};

fn containsIgnoreCase(text: []const u8, needle: []const u8) bool {
	if (needle.len == 0) return true;
	if (needle.len > text.len) return false;

	var at: usize = 0;

	while (at + needle.len <= text.len) : (at += 1) {
		if (std.ascii.eqlIgnoreCase(text[at .. at + needle.len], needle)) return true;
	}

	return false;
}

fn holdOrder(arena: Allocator, previous: []const i32, incoming: []const i32) ![]i32 {
	var out: std.ArrayListUnmanaged(i32) = .empty;
	const used = try arena.alloc(bool, incoming.len);

	@memset(used, false);

	for (previous) |pid| {
		for (incoming, 0..) |value, index| {
			if (value != pid or used[index]) continue;

			used[index] = true;
			try out.append(arena, pid);
			break;
		}
	}

	for (incoming, 0..) |value, index| {
		if (!used[index]) try out.append(arena, value);
	}

	return out.items;
}

fn kbText(arena: Allocator, kb: i64) ![]const u8 {
	const value: f64 = @floatFromInt(kb);

	if (kb >= 1024 * 1024) return std.fmt.allocPrint(arena, "{d:.1} GB", .{value / 1024 / 1024});
	if (kb >= 1024) return std.fmt.allocPrint(arena, "{d:.1} MB", .{value / 1024});

	return std.fmt.allocPrint(arena, "{d} KB", .{kb});
}

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

test "one synchronous sample seeds the cpu and the rss lists" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();
	const io = std.testing.io;

	var hub: hubmod.Hub = .{ .allocator = allocator, .io = io };
	const system = try System.create(allocator, io, &hub);

	system.sampleProcesses();

	try std.testing.expect(system.top_count > 0);
	try std.testing.expect(system.mem_count > 0);
	try std.testing.expect(system.mem_top[0].rss_kb > 0);

	var index: usize = 1;
	while (index < system.mem_count) : (index += 1) {
		try std.testing.expect(system.mem_top[index - 1].rss_kb >= system.mem_top[index].rss_kb);
	}

	system.sampleProcesses();

	try std.testing.expect(system.mem_count > 0);
	try std.testing.expect(system.mem_top[0].rss_kb > 0);
}

test "memory sizes read the way the panel prints them" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();

	try std.testing.expectEqualStrings("0 KB", try kbText(allocator, 0));
	try std.testing.expectEqualStrings("512 KB", try kbText(allocator, 512));
	try std.testing.expectEqualStrings("1.0 MB", try kbText(allocator, 1024));
	try std.testing.expectEqualStrings("1.5 MB", try kbText(allocator, 1536));
	try std.testing.expectEqualStrings("32.0 GB", try kbText(allocator, 32 * 1024 * 1024));
}

test "cpuinfo names the model and the spec line" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();

	const fixture =
		\\processor : 0
		\\model name : AMD Ryzen 7 5800X 8-Core Processor
		\\cpu MHz : 3800.000
		\\cache size : 32768 KB
		\\cpu cores : 8
		\\
		\\processor : 1
		\\model name : AMD Ryzen 7 5800X 8-Core Processor
		\\cpu MHz : 4200.000
		\\cache size : 32768 KB
		\\cpu cores : 8
	;

	const info = System.parseCpuInfo(fixture);

	try std.testing.expectEqualStrings("AMD Ryzen 7 5800X 8-Core Processor", info.model);
	try std.testing.expectEqual(@as(i64, 2), info.threads);
	try std.testing.expectEqual(@as(i64, 8), info.cores);
	try std.testing.expectEqual(@as(f64, 4200), info.mhz);
	try std.testing.expectEqual(@as(f64, 32768), info.cache);

	const spec = try System.specLine(allocator, info);
	try std.testing.expectEqualStrings("2 threads · 8 cores · 4.2 GHz · 32 MB", spec);

	const tiny = try System.specLine(allocator, .{ .threads = 4, .cores = 4 });
	try std.testing.expectEqualStrings("4 threads", tiny);
}

test "the panel keeps the row order it had" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();

	const held = try holdOrder(allocator, &.{ 5, 3, 9 }, &.{ 9, 4, 3, 5 });
	try std.testing.expectEqualSlices(i32, &.{ 5, 3, 9, 4 }, held);

	const fresh = try holdOrder(allocator, &.{}, &.{ 2, 1 });
	try std.testing.expectEqualSlices(i32, &.{ 2, 1 }, fresh);

	const gone = try holdOrder(allocator, &.{ 7, 5 }, &.{ 5 });
	try std.testing.expectEqualSlices(i32, &.{5}, gone);
}

test "the panel drops the ignored names and matches the query" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();

	var ignore: [][]u8 = try allocator.alloc([]u8, 1);
	ignore[0] = try allocator.dupe(u8, "ps");

	var system: System = .{
		.allocator = allocator,
		.io = std.Io.Threaded.global_single_threaded.io(),
		.hub = undefined,
		.scratch = std.heap.ArenaAllocator.init(allocator),
		.ignore = ignore,
		.panel_field = try allocator.dupe(u8, "pcpu"),
		.panel_query = try allocator.dupe(u8, ""),
	};

	try std.testing.expect(system.ignored("ps"));
	try std.testing.expect(!system.ignored("psx"));

	const rows = [_]ProcessOut{
		.{ .pid = 1, .name = "ps", .cmd = "ps", .value = 0, .valueText = "" },
		.{ .pid = 2, .name = "Hyprland", .cmd = "Hyprland", .value = 0, .valueText = "" },
		.{ .pid = 3, .name = "alacritty", .cmd = "alacritty", .value = 0, .valueText = "" },
	};

	const kept = try system.panelRows(allocator, false, &rows);
	try std.testing.expectEqual(@as(usize, 2), kept.len);
	try std.testing.expectEqual(@as(i32, 2), kept[0].pid);
	try std.testing.expectEqual(@as(i32, 3), kept[1].pid);

	try setStr(allocator, &system.panel_query, "YPRL");

	const filtered = try system.panelRows(allocator, false, &rows);
	try std.testing.expectEqual(@as(usize, 1), filtered.len);
	try std.testing.expectEqualStrings("Hyprland", filtered[0].name);

	try std.testing.expect(containsIgnoreCase("Hyprland", "yprl"));
	try std.testing.expect(!containsIgnoreCase("Hyprland", "zzz"));
	try std.testing.expect(!containsIgnoreCase("ps", "psx"));
}
