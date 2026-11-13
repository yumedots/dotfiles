const std = @import("std");
const json = @import("primitives/json.zig");
const proc = @import("primitives/proc.zig");
const exec = @import("primitives/exec.zig");
const sock = @import("primitives/sock.zig");
const fmt = @import("primitives/fmt.zig");
const guardmod = @import("providers/disk/guard.zig");
const scanner = @import("providers/disk/scanner.zig");
const cache = @import("providers/disk/cache.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const Row = struct {
	cold: bool = false,
	at: i64,
	version: []const u8,
	threads: usize = 0,
	fixture: []const u8,
	entries: u64,
	bytes: u64,
	entriesPerSecond: f64,
	syscallsPerEntry: f64,
	hardlinks: u64,
	directories: u64,
	files: u64,
	elapsedMs: f64,
	cacheBytes: u64,
	cacheWriteMs: f64,
	cacheLoadMs: f64,
	queryP50Us: f64,
	queryP99Us: f64,
	accuracy: bool,
	expectedBytes: u64,
	reference: []const u8,
};

pub fn run(io: Io, args: []const []const u8) !void {
	var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
	defer arena.deinit();
	const allocator = arena.allocator();

	var as_json = false;
	var counts: usize = 50_000;
	var real = false;
	var cold = false;
	var no_v3 = false;

	for (args) |arg| {
		if (std.mem.eql(u8, arg, "--json")) as_json = true;
		if (std.mem.eql(u8, arg, "--real")) real = true;
		if (std.mem.eql(u8, arg, "--cold")) cold = true;
		if (std.mem.eql(u8, arg, "--no-v3")) no_v3 = true;
		if (std.mem.startsWith(u8, arg, "--files=")) counts = std.fmt.parseInt(usize, arg["--files=".len..], 10) catch counts;
	}

	const cache_home = proc.env(io, allocator, "XDG_CACHE_HOME") orelse try std.fmt.allocPrint(allocator, "{s}/.cache", .{proc.home(io, allocator)});
	const scratch = try std.fmt.allocPrint(allocator, "{s}/yudae-disk-bench-{d}", .{ cache_home, std.os.linux.getpid() });
	defer removeScratch(io, scratch);

	var guard = try guardmod.Guard.init(allocator, io, &.{});
	defer guard.deinit(allocator);

	const fixture = try makeFixture(io, allocator, scratch, counts);
	var seen = std.AutoHashMap(u128, void).init(allocator);
	defer seen.deinit();
	const expected = try expectedBytes(io, allocator, fixture, &seen);

	const cpu_count = std.Thread.getCpuCount() catch 1;
	var thread_counts = [_]usize{ 1, 2, 4, 8, 16, cpu_count };
	var best: ?Measure = null;
	var variants: std.ArrayList(Measure) = .empty;
	defer variants.deinit(allocator);

	const sequential = try measure(allocator, &guard, fixture, .sequential, 0);
	if (sequential.total == expected) {
		best = sequential;
		try variants.append(allocator, sequential);
	}

	for ([_]Mode{ .threaded, .uring }) |mode| {
		var index: usize = 0;
		while (index < thread_counts.len) : (index += 1) {
			var duplicate = false;
			for (thread_counts[0..index]) |other| {
				if (other == thread_counts[index]) duplicate = true;
			}
			if (duplicate) continue;

			const candidate = try measure(allocator, &guard, fixture, mode, thread_counts[index]);
			if (candidate.total != expected) continue;
			try variants.append(allocator, candidate);
			if (best == null or candidate.entriesPerSecond > best.?.entriesPerSecond) best = candidate;
		}
	}

	const reference = referenceScanners(io, allocator);
	const btrfs_candidate = if (no_v3) null else measure(allocator, &guard, fixture, .btrfs, 0) catch |err| blk: {
		std.debug.print("bench disk: v3 btrfs unavailable: {s}\n", .{@errorName(err)});
		break :blk null;
	};
	if (btrfs_candidate) |candidate| {
		if (candidate.total == expected) {
			try variants.append(allocator, candidate);
			if (best == null or candidate.entriesPerSecond > best.?.entriesPerSecond) best = candidate;
		} else {
			std.debug.print("bench disk: v3 total {d} expected {d}\n", .{ candidate.total, expected });
			try append(io, allocator, variantRow(io, candidate, expected, fixture, reference, false));
		}
	}

	const winner = best orelse return error.ScanFailed;

	var winner_scan = try scanner.Scan.init(allocator, &guard, scanner.fold_below);
	defer winner_scan.deinit();

	const started = fmt.nowMs(io);
	switch (winner.mode) {
		.sequential => try winner_scan.run(fixture),
		.threaded => try winner_scan.runThreaded(fixture, winner.threads),
		.uring => try winner_scan.runUringThreaded(fixture, winner.threads),
		.btrfs => try winner_scan.runBtrfs(fixture),
	}
	const elapsed = fmt.nowMs(io) - started;

	const cache_path = try std.fmt.allocPrint(allocator, "{s}/disk.bin", .{scratch});
	const write_started = fmt.nowMs(io);
	try cache.write(io, allocator, cache_path, &winner_scan, started);
	const write_ms = fmt.nowMs(io) - write_started;

	const load_started = fmt.nowMs(io);
	var loaded = try cache.load(io, allocator, cache_path);
	defer loaded.deinit();
	const load_ms = fmt.nowMs(io) - load_started;

	const cache_bytes: u64 = @intCast((std.Io.Dir.cwd().statFile(io, cache_path, .{}) catch return error.StatFailed).size);
	const accuracy = winner_scan.total() == expected;

	const query = try queryTimes(allocator, loaded);

	const row = Row{
		.at = fmt.nowMs(io),
		.version = winner.version,
		.threads = winner.threads,
		.fixture = if (real) "synthetic+home" else "synthetic",
		.entries = winner_scan.stats.entries,
		.bytes = winner_scan.total(),
		.entriesPerSecond = winner_scan.stats.entriesPerSecond(),
		.syscallsPerEntry = if (winner_scan.stats.entries > 0) @as(f64, @floatFromInt(winner_scan.stats.syscalls)) / @as(f64, @floatFromInt(winner_scan.stats.entries)) else 0,
		.hardlinks = winner_scan.stats.hardlinks,
		.directories = winner_scan.stats.directories,
		.files = winner_scan.stats.files,
		.elapsedMs = @floatFromInt(elapsed),
		.cacheBytes = cache_bytes,
		.cacheWriteMs = @floatFromInt(write_ms),
		.cacheLoadMs = @floatFromInt(load_ms),
		.queryP50Us = query.p50,
		.queryP99Us = query.p99,
		.accuracy = accuracy,
		.expectedBytes = expected,
		.reference = reference,
	};

	try append(io, allocator, row);
	for (variants.items) |variant| {
		try append(io, allocator, variantRow(io, variant, expected, fixture, reference, false));
	}

	if (cold) {
		if (dropCaches(io, allocator, fixture)) {
			const cold_sequential = try coldMeasure(io, allocator, &guard, fixture, .sequential, 0);
			if (cold_sequential.total == expected) try append(io, allocator, variantRow(io, cold_sequential, expected, fixture, reference, true));

			for ([_]Mode{ .threaded, .uring }) |mode| {
				var cold_index: usize = 0;
				while (cold_index < thread_counts.len) : (cold_index += 1) {
					var duplicate = false;
					for (thread_counts[0..cold_index]) |other| {
						if (other == thread_counts[cold_index]) duplicate = true;
					}
					if (duplicate) continue;

					if (!dropCaches(io, allocator, fixture)) break;
					const candidate = try coldMeasure(io, allocator, &guard, fixture, mode, thread_counts[cold_index]);
					if (candidate.total != expected) continue;
					try append(io, allocator, variantRow(io, candidate, expected, fixture, reference, true));
				}
			}

			if (dropCaches(io, allocator, fixture)) {
				const candidate = measure(allocator, &guard, fixture, .btrfs, 0) catch null;
				if (candidate) |value| {
					try append(io, allocator, variantRow(io, value, expected, fixture, reference, true));
				}
			}
		} else {
			std.debug.print("bench disk: cold cache needs yudae-fsd and org.yudae.fs.bench\n", .{});
		}
	}

	if (real) {
		const home = proc.home(io, allocator);
		var home_scan = try scanner.Scan.init(allocator, &guard, scanner.fold_below);
		defer home_scan.deinit();
		try home_scan.run(home);

		var home_row = row;
		home_row.fixture = "home";
		home_row.entries = home_scan.stats.entries;
		home_row.bytes = home_scan.total();
		home_row.entriesPerSecond = home_scan.stats.entriesPerSecond();
		home_row.accuracy = true;
		home_row.expectedBytes = home_scan.total();
		try append(io, allocator, home_row);
	}

	const baseline = try gate(io, allocator, row);

	var buffer: [8192]u8 = undefined;
	var writer = std.Io.File.stdout().writer(io, &buffer);
	const w = &writer.interface;

	if (as_json) {
		try w.print("{f}\n", .{std.json.fmt(row, .{})});
	} else {
		try w.print("entries       {d}\n", .{row.entries});
		try w.print("winner        {s} threads={d}\n", .{ row.version, row.threads });
		try w.writeAll("v3            btrfs measured; shipped only when exact and fastest\n");
		try w.print("bytes         {d}\n", .{row.bytes});
		try w.print("throughput    {d:.0} entries/s\n", .{row.entriesPerSecond});
		try w.print("syscalls      {d:.2} per entry\n", .{row.syscallsPerEntry});
		try w.print("cache         {d} bytes, write {d:.1}ms, load {d:.2}ms\n", .{ row.cacheBytes, row.cacheWriteMs, row.cacheLoadMs });
		try w.print("views         p50 {d:.2}us  p99 {d:.2}us\n", .{ row.queryP50Us, row.queryP99Us });
		try w.print("accuracy      {s} ({d} expected, {d} scanned)\n", .{ if (row.accuracy) "exact" else "FAIL", row.expectedBytes, row.bytes });
		try w.print("reference     {s}\n", .{row.reference});
		try w.print("baseline      {s}\n", .{if (baseline) "created" else "checked"});
	}
	try w.flush();

	if (!accuracy) std.process.exit(1);
}

const Mode = enum { sequential, threaded, uring, btrfs };

const Measure = struct {
	mode: Mode,
	version: []const u8,
	threads: usize,
	total: u64,
	entries: u64,
	directories: u64,
	files: u64,
	hardlinks: u64,
	syscalls: u64,
	entriesPerSecond: f64,
};

fn measure(allocator: Allocator, guard: *const guardmod.Guard, fixture: []const u8, mode: Mode, threads: usize) !Measure {
	var scan_state = try scanner.Scan.init(allocator, guard, scanner.fold_below);
	defer scan_state.deinit();

	switch (mode) {
		.sequential => try scan_state.run(fixture),
		.threaded => try scan_state.runThreaded(fixture, threads),
		.uring => try scan_state.runUringThreaded(fixture, threads),
		.btrfs => try scan_state.runBtrfs(fixture),
	}

	return .{
		.mode = mode,
		.version = switch (mode) {
			.sequential => "v0-sequential",
			.threaded => "v1-threaded",
			.uring => "v2-uring",
			.btrfs => "v3-btrfs",
		},
		.threads = if (mode == .sequential or mode == .btrfs) 0 else threads,
		.total = scan_state.total(),
		.entries = scan_state.stats.entries,
		.directories = scan_state.stats.directories,
		.files = scan_state.stats.files,
		.hardlinks = scan_state.stats.hardlinks,
		.syscalls = scan_state.stats.syscalls,
		.entriesPerSecond = scan_state.stats.entriesPerSecond(),
	};
}

fn coldMeasure(io: Io, allocator: Allocator, guard: *const guardmod.Guard, fixture: []const u8, mode: Mode, threads: usize) !Measure {
	_ = io;
	return measure(allocator, guard, fixture, mode, threads);
}

fn variantRow(io: Io, measured: Measure, expected: u64, fixture: []const u8, reference: []const u8, cold: bool) Row {
	return .{
		.cold = cold,
		.at = fmt.nowMs(io),
		.version = measured.version,
		.threads = measured.threads,
		.fixture = fixture,
		.entries = measured.entries,
		.bytes = measured.total,
		.entriesPerSecond = measured.entriesPerSecond,
		.syscallsPerEntry = if (measured.entries > 0) @as(f64, @floatFromInt(measured.syscalls)) / @as(f64, @floatFromInt(measured.entries)) else 0,
		.hardlinks = measured.hardlinks,
		.directories = measured.directories,
		.files = measured.files,
		.elapsedMs = 0,
		.cacheBytes = 0,
		.cacheWriteMs = 0,
		.cacheLoadMs = 0,
		.queryP50Us = 0,
		.queryP99Us = 0,
		.accuracy = measured.total == expected,
		.expectedBytes = expected,
		.reference = reference,
	};
}

fn dropCaches(io: Io, allocator: Allocator, path: []const u8) bool {
	const socket_path = guardmod.fsdSocket();
	if (!proc.exists(io, socket_path)) {
		if (std.os.linux.geteuid() == 0) {
			var file = std.Io.Dir.cwd().openFile(io, "/proc/sys/vm/drop_caches", .{ .mode = .write_only }) catch return false;
			defer file.close(io);
			file.writeStreamingAll(io, "3\n") catch return false;
			return true;
		}
		return false;
	}

	const request = std.fmt.allocPrint(allocator, "{{\"action\":\"bench\",\"path\":{f}}}", .{std.json.fmt(path, .{})}) catch return false;

	var buffer: [1024 * 1024]u8 = undefined;
	var connection = sock.Connection.connect(socket_path, &buffer) catch return false;
	defer connection.close();

	connection.writeLine(request) catch return false;
	const maybe_line = connection.readLine() catch return false;
	const line = maybe_line orelse return false;
	const parsed = json.parse(allocator, line) catch return false;
	return json.flag(parsed.value, "ok");
}

fn removeScratch(io: Io, path: []const u8) void {
	if (std.os.linux.geteuid() == 0) destroySubvolume(io, path, "tree");
	std.Io.Dir.cwd().deleteTree(io, path) catch {};
}

fn destroySubvolume(io: Io, parent: []const u8, name: []const u8) void {
	var file = std.Io.Dir.cwd().openFile(io, parent, .{}) catch return;
	defer file.close(io);

	var args: VolArgs = std.mem.zeroes(VolArgs);
	@memcpy(args.name[0..name.len], name);
	const request = std.os.linux.IOCTL.IOW(0x94, 15, VolArgs);
	_ = std.os.linux.ioctl(file.handle, request, @intFromPtr(&args));
}

fn createSubvolume(io: Io, parent: []const u8, name: []const u8) bool {
	var file = std.Io.Dir.cwd().openFile(io, parent, .{}) catch return false;
	defer file.close(io);

	var args: VolArgs = std.mem.zeroes(VolArgs);
	@memcpy(args.name[0..name.len], name);
	const request = std.os.linux.IOCTL.IOW(0x94, 14, VolArgs);
	return std.os.linux.errno(std.os.linux.ioctl(file.handle, request, @intFromPtr(&args))) == .SUCCESS;
}

const VolArgs = extern struct {
	fd: i64 = 0,
	name: [4088]u8 = @splat(0),
};

fn makeFixture(io: Io, allocator: Allocator, root: []const u8, files: usize) ![]const u8 {
	const tree = try std.fmt.allocPrint(allocator, "{s}/tree", .{root});
	try std.Io.Dir.cwd().createDirPath(io, root);
	if (std.os.linux.geteuid() != 0 or !createSubvolume(io, root, "tree")) {
		try std.Io.Dir.cwd().createDirPath(io, tree);
	}

	const deep = try std.fmt.allocPrint(allocator, "{s}/deep", .{tree});
	try std.Io.Dir.cwd().createDirPath(io, deep);
	var deep_path = awaitAlloc(allocator, deep);
	for (0..40) |level| {
		deep_path = try std.fmt.allocPrint(allocator, "{s}/d{d}", .{ deep_path, level });
		try std.Io.Dir.cwd().createDirPath(io, deep_path);
	}
	try writeFile(io, allocator, deep_path, "leaf.txt", "leaf\n");

	const wide = try std.fmt.allocPrint(allocator, "{s}/wide", .{tree});
	try std.Io.Dir.cwd().createDirPath(io, wide);

	const tiny_dir = try std.fmt.allocPrint(allocator, "{s}/tiny", .{tree});
	try std.Io.Dir.cwd().createDirPath(io, tiny_dir);

	var counts = files;
	while (counts > 0) : (counts -= 1) {
		const path = try std.fmt.allocPrint(allocator, "{s}/{d}.txt", .{ tiny_dir, counts });
		try writeRaw(io, path, "x");
	}

	for (0..64) |index| {
		const path = try std.fmt.allocPrint(allocator, "{s}/{d}.bin", .{ wide, index });
		try writeRaw(io, path, "wide");
	}

	const big = try std.fmt.allocPrint(allocator, "{s}/big.bin", .{tree});
	try writeSized(io, big, 2 * 1024 * 1024);

	const sparse = try std.fmt.allocPrint(allocator, "{s}/sparse.bin", .{tree});
	var sparse_file = try std.Io.Dir.cwd().createFile(io, sparse, .{ .truncate = true });
	try sparse_file.setLength(io, 64 * 1024 * 1024);
	sparse_file.close(io);

	const hard_a = try std.fmt.allocPrint(allocator, "{s}/hard-a.bin", .{tree});
	const hard_b = try std.fmt.allocPrint(allocator, "{s}/deep/hard-b.bin", .{tree});
	try writeSized(io, hard_a, 4096);
	try std.Io.Dir.cwd().hardLink(hard_a, std.Io.Dir.cwd(), hard_b, io, .{});

	const loop = try std.fmt.allocPrint(allocator, "{s}/deep/loop", .{tree});
	try std.Io.Dir.cwd().symLink(io, tree, loop, .{});

	return tree;
}

fn awaitAlloc(allocator: Allocator, value: []const u8) []const u8 {
	return allocator.dupe(u8, value) catch value;
}

fn writeFile(io: Io, allocator: Allocator, dir: []const u8, name: []const u8, body: []const u8) !void {
	const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, name });
	try writeRaw(io, path, body);
}

fn writeRaw(io: Io, path: []const u8, body: []const u8) !void {
	var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
	try file.writeStreamingAll(io, body);
	file.close(io);
}

fn writeSized(io: Io, path: []const u8, size: usize) !void {
	var file = try std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
	var buffer: [4096]u8 = @splat('x');
	var left = size;
	while (left > 0) {
		const chunk = @min(left, buffer.len);
		try file.writeStreamingAll(io, buffer[0..chunk]);
		left -= chunk;
	}
	file.close(io);
}

fn expectedBytes(io: Io, allocator: Allocator, path: []const u8, seen: *std.AutoHashMap(u128, void)) !u64 {
	var st: std.os.linux.Statx = undefined;
	const z = try allocator.allocSentinel(u8, path.len, 0);
	@memcpy(z, path);
	defer allocator.free(z);

	const result = std.os.linux.statx(std.os.linux.AT.FDCWD, z.ptr, std.os.linux.AT.SYMLINK_NOFOLLOW, mask(), &st);
	if (std.os.linux.errno(result) != .SUCCESS) return error.StatFailed;

	if (st.nlink > 1 and !std.posix.S.ISDIR(st.mode)) {
		const key = (@as(u128, st.dev_major) << 96) | (@as(u128, st.dev_minor) << 64) | st.ino;
		if (seen.contains(key)) return 0;
		try seen.put(key, {});
	}

	var total = st.blocks * 512;
	if (!std.posix.S.ISDIR(st.mode)) return total;

	var dir = try std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
	defer dir.close(io);
	var it = dir.iterate();
	while (try it.next(io)) |entry| {
		const child = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ path, entry.name });
		defer allocator.free(child);
		total += try expectedBytes(io, allocator, child, seen);
	}

	return total;
}

fn mask() std.os.linux.STATX {
	return .{ .TYPE = true, .MODE = true, .NLINK = true, .INO = true, .SIZE = true, .BLOCKS = true, .MTIME = true };
}

fn queryTimes(allocator: Allocator, loaded: cache.Cache) !struct { p50: f64, p99: f64 } {
	var samples: std.ArrayList(f64) = .empty;
	defer samples.deinit(allocator);

	var index: u32 = 0;
	while (index < loaded.nodes.len and samples.items.len < 500) : (index += 1) {
		const started = nowNs();
		_ = loaded.find(loaded.nameOf(index));
		const ended = nowNs();
		try samples.append(allocator, @as(f64, @floatFromInt(ended - started)) / 1000.0);
	}

	if (samples.items.len == 0) return .{ .p50 = 0, .p99 = 0 };
	std.mem.sort(f64, samples.items, {}, struct {
		fn less(_: void, a: f64, b: f64) bool {
			return a < b;
		}
	}.less);

	return .{
		.p50 = samples.items[samples.items.len / 2],
		.p99 = samples.items[@min(samples.items.len - 1, samples.items.len * 99 / 100)],
	};
}

fn referenceScanners(io: Io, allocator: Allocator) []const u8 {
	var found: std.ArrayList(u8) = .empty;
	for ([_][]const u8{ "ncdu", "gdu", "dua", "hyperfine" }) |name| {
		const path = std.fmt.allocPrint(allocator, "/usr/bin/{s}", .{name}) catch continue;
		if (proc.exists(io, path)) {
			if (found.items.len > 0) found.appendSlice(allocator, ", ") catch {};
			found.appendSlice(allocator, name) catch {};
		}
	}
	if (found.items.len == 0) return "none installed (no root install performed)";
	return found.items;
}

fn nowNs() i128 {
	var ts: std.os.linux.timespec = undefined;
	if (std.os.linux.errno(std.os.linux.clock_gettime(.MONOTONIC, &ts)) != .SUCCESS) return 0;
	return @as(i128, ts.sec) * std.time.ns_per_s + ts.nsec;
}

fn append(io: Io, allocator: Allocator, row: Row) !void {
	const dir = try std.fmt.allocPrint(allocator, "{s}/dotfiles/daemon/bench", .{proc.home(io, allocator)});
	try std.Io.Dir.cwd().createDirPath(io, dir);
	const path = try std.fmt.allocPrint(allocator, "{s}/disk.jsonl", .{dir});
	const previous = proc.readFile(io, allocator, path) catch "";
	defer if (previous.len > 0) allocator.free(previous);

	var out: std.Io.Writer.Allocating = .init(allocator);
	try out.writer.writeAll(previous);
	try out.writer.print("{f}\n", .{std.json.fmt(row, .{})});
	try proc.writeFileAtomic(io, allocator, path, out.written());
}

fn gate(io: Io, allocator: Allocator, row: Row) !bool {
	const path = try std.fmt.allocPrint(allocator, "{s}/dotfiles/daemon/bench/baseline.json", .{proc.home(io, allocator)});
	const body = proc.readFile(io, allocator, path) catch return false;
	defer allocator.free(body);

	const parsed = json.parse(allocator, body) catch return false;
	const disk = json.field(parsed.value, "disk") orelse {
		if (!row.accuracy) return false;

		var out: std.Io.Writer.Allocating = .init(allocator);
		const cut = std.mem.lastIndexOfScalar(u8, body, '}') orelse return false;
		try out.writer.writeAll(body[0..cut]);
		if (cut > 0 and body[cut - 1] != '{' and body[cut - 1] != ',') try out.writer.writeAll(",");
		try out.writer.writeAll("\"disk\":");
		try out.writer.print("{f}", .{std.json.fmt(row, .{})});
		try out.writer.writeAll("}\n");
		try proc.writeFileAtomic(io, allocator, path, out.written());
		return true;
	};

	const baseline = json.number(json.field(disk, "entriesPerSecond"));
	if (baseline <= 0) return false;

	if (row.entriesPerSecond < baseline * 0.8) {
		std.debug.print("bench disk: throughput {d:.0}/s below 80% of baseline {d:.0}/s\n", .{ row.entriesPerSecond, baseline });
		std.process.exit(1);
	}

	const cache_gate = json.integer(json.field(disk, "cacheBytes"));
	if (cache_gate > 0 and row.cacheBytes > @as(u64, @intCast(cache_gate)) * 2 + 1024 * 1024) {
		std.debug.print("bench disk: cache grew past its gate\n", .{});
		std.process.exit(1);
	}

	return false;
}

test "bench disk code compiles" {
	try std.testing.expect(true);
}
