const std = @import("std");
const json = @import("primitives/json.zig");
const proc = @import("primitives/proc.zig");
const sock = @import("primitives/sock.zig");
const sleep = @import("primitives/sleep.zig");

const gpa = std.heap.smp_allocator;
const Io = std.Io;

const Hog = struct {
	comm: []const u8,
	pid: i32,
	rss_kb: i64,
	cpu: f64,
};

const Report = struct {
	binaryBytes: i64,
	bootMs: i64,
	listenMs: i64,
	idleRssKb: i64,
	idleCpu: f64,
	threads: i64,
	shellRssKb: i64,
	daemonPid: i32,
	hogs: []Hog,
	buildMs: i64,
	cacheMb: i64,
};

const Snapshot = struct {
	processes: []proc.ProcessInfo,
	shell_rss: i64,
};

pub fn run(io: Io, args: []const []const u8) !void {
	var seconds: u64 = 10;
	var as_json = false;
	var index: usize = 2;

	while (index < args.len) : (index += 1) {
		if (std.mem.eql(u8, args[index], "--json")) as_json = true;

		if (std.mem.eql(u8, args[index], "--seconds") and index + 1 < args.len) {
			index += 1;
			seconds = std.fmt.parseInt(u64, args[index], 10) catch 10;
		}
	}

	var arena = std.heap.ArenaAllocator.init(gpa);
	defer arena.deinit();
	const allocator = arena.allocator();

	const state = fetch(io, allocator) orelse {
		std.debug.print("yudaemond is not running\n", .{});
		std.process.exit(2);
	};

	const daemon_pid: i32 = @intCast(json.integer(json.deep(state, &.{ "daemon", "pid" })));
	const boot = json.integer(json.deep(state, &.{ "daemon", "bootMs" }));
	const listen = json.integer(json.deep(state, &.{ "daemon", "listenMs" }));
	const threads = json.integer(json.deep(state, &.{ "daemon", "threads" }));

	const before = try snapshot(io, allocator);
	sleep.ms(seconds * 1000);
	const after = try snapshot(io, allocator);

	const daemon_ticks_before = tickOf(before.processes, daemon_pid);
	const daemon_ticks_after = tickOf(after.processes, daemon_pid);
	const daemon_rss = rssOf(after.processes, daemon_pid);

	const idle_cpu = percent(daemon_ticks_after - daemon_ticks_before, seconds);

	var hogs: std.ArrayList(Hog) = .empty;
	for (after.processes) |*entry| {
		if (entry.pid == daemon_pid) continue;

		try hogs.append(allocator, .{
			.comm = entry.name(),
			.pid = entry.pid,
			.rss_kb = entry.rss_kb,
			.cpu = percent(entry.ticks - tickOf(before.processes, entry.pid), seconds),
		});
	}

	std.mem.sort(Hog, hogs.items, {}, byRss);

	const report = Report{
		.binaryBytes = binarySize(io),
		.bootMs = boot,
		.listenMs = listen,
		.idleRssKb = daemon_rss,
		.idleCpu = idle_cpu,
		.threads = threads,
		.shellRssKb = after.shell_rss,
		.daemonPid = daemon_pid,
		.hogs = hogs.items[0..@min(10, hogs.items.len)],
		.buildMs = lastBuild(io, allocator).ms,
		.cacheMb = lastBuild(io, allocator).cache_mb,
	};

	var buffer: [16384]u8 = undefined;
	var writer = std.Io.File.stdout().writer(io, &buffer);
	const w = &writer.interface;

	if (as_json) {
		try w.print("{f}\n", .{std.json.fmt(report, .{})});
		try w.flush();
		return;
	}

	try w.print("build        {d}ms  cache {d}MB\n", .{ report.buildMs, report.cacheMb });
	try w.print("binary       {d}B\n", .{report.binaryBytes});
	try w.print("start        {d}ms (boot to socket ready)\n", .{report.listenMs});
	try w.print("idle rss     {d}kB\n", .{report.idleRssKb});
	try w.print("idle cpu     {d:.2}% over {d}s\n", .{ report.idleCpu, seconds });
	try w.print("threads      {d}\n", .{report.threads});
	try w.print("shell rss    {d}kB\n", .{report.shellRssKb});
	try w.print("hoggers      kB     cpu%\n", .{});

	for (report.hogs) |hog| {
		try w.print("  {d:>8}  {d:>5.1}  {s} ({d})\n", .{ hog.rss_kb, hog.cpu, hog.comm, hog.pid });
	}

	try w.flush();
}

fn percent(ticks: i64, seconds: u64) f64 {
	if (ticks <= 0 or seconds == 0) return 0;

	return @as(f64, @floatFromInt(ticks)) / 100.0 / @as(f64, @floatFromInt(seconds)) * 100.0;
}

fn byRss(_: void, a: Hog, b: Hog) bool {
	return a.rss_kb > b.rss_kb;
}

fn tickOf(list: []const proc.ProcessInfo, pid: i32) i64 {
	for (list) |entry| if (entry.pid == pid) return entry.ticks;
	return 0;
}

fn rssOf(list: []const proc.ProcessInfo, pid: i32) i64 {
	for (list) |entry| if (entry.pid == pid) return entry.rss_kb;
	return 0;
}

fn snapshot(io: Io, allocator: std.mem.Allocator) !Snapshot {
	const processes = try proc.listProcesses(io, allocator);

	var shell_rss: i64 = 0;
	for (processes) |*entry| {
		if (std.mem.eql(u8, entry.name(), "quickshell")) shell_rss += entry.rss_kb;
	}

	return .{ .processes = processes, .shell_rss = shell_rss };
}

fn fetch(io: Io, allocator: std.mem.Allocator) ?json.Value {
	const path = proc.socketPath(io, allocator) catch return null;
	var buffer: [65536]u8 = undefined;
	var connection = sock.Connection.connect(path, &buffer) catch return null;
	defer connection.close();

	const line = connection.readLine() catch return null;
	const body = line orelse return null;

	const parsed = json.parse(allocator, body) catch return null;
	return parsed.value;
}

fn binarySize(io: Io) i64 {
	const stat = std.Io.Dir.cwd().statFile(io, "/proc/self/exe", .{}) catch return 0;
	return @intCast(stat.size);
}

const Build = struct {
	ms: i64 = 0,
	cache_mb: i64 = 0,
};

fn lastBuild(io: Io, allocator: std.mem.Allocator) Build {
	const path = std.fmt.allocPrint(allocator, "{s}/.config/quickshell/yudaemond/bench/build.jsonl", .{proc.home(io, allocator)}) catch return .{};
	const body = proc.readFile(io, allocator, path) catch return .{};

	var out: Build = .{};
	var lines = std.mem.splitScalar(u8, body, '\n');

	while (lines.next()) |line| {
		if (line.len == 0) continue;

		const parsed = json.parse(allocator, line) catch continue;
		out.ms = json.integer(json.field(parsed.value, "ms"));
		out.cache_mb = json.integer(json.field(parsed.value, "cache_mb"));
	}

	return out;
}
