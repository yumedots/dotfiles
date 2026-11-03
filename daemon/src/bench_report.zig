const std = @import("std");

const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

pub const Status = enum { ok, na, fail };

pub const Row = struct {
	widget: []const u8,
	status: Status,
	reason: []const u8 = "",
	openMs: ?f64 = null,
	ipcMs: ?f64 = null,
	shellRssDeltaKb: ?i64 = null,
	shellCpuPct: ?f64 = null,
	daemonRssDeltaKb: ?i64 = null,
	daemonCpuPct: ?f64 = null,
	shellPid: ?i32 = null,
	shellRssPeakKb: ?i64 = null,
	daemonRssPeakKb: ?i64 = null,
	notes: []const u8 = "",
};

pub const Report = struct {
	at: []const u8,
	instance: struct {
		id: []const u8,
		reused: bool,
		shellPid: i32,
		worktree: []const u8,
		signature: []const u8,
		wayland: []const u8,
	},
	launcherPid: i32,
	daemonPid: i32,
	daemonSocket: []const u8,
	daemonShared: bool,
	holdSeconds: f64,
	worst: ?[]const u8,
	widgets: []Row,
};

pub fn byRank(_: void, a: Row, b: Row) bool {
	const rank_a = if (a.status == .ok) @as(u8, 0) else 1;
	const rank_b = if (b.status == .ok) @as(u8, 0) else 1;
	if (rank_a != rank_b) return rank_a < rank_b;

	const open_a = a.openMs orelse 0;
	const open_b = b.openMs orelse 0;
	if (open_a != open_b) return open_a < open_b;

	return cpuOf(a) < cpuOf(b);
}

fn cpuOf(row: Row) f64 {
	return (row.shellCpuPct orelse 0) + (row.daemonCpuPct orelse 0);
}

fn rssOf(row: Row) i64 {
	return (row.shellRssDeltaKb orelse 0) + (row.daemonRssDeltaKb orelse 0);
}

pub fn pickWorst(rows: []const Row) ?Row {
	var out: ?Row = null;
	var best_cpu: f64 = 0;
	var best_rss: i64 = 0;
	var best_open: f64 = 0;

	for (rows) |row| {
		if (row.status != .ok) continue;

		const cpu = cpuOf(row);
		const rss = rssOf(row);
		const open = row.openMs orelse 0;

		if (out == null or cpu > best_cpu or
			(cpu == best_cpu and (rss > best_rss or (rss == best_rss and open > best_open)))) {
			out = row;
			best_cpu = cpu;
			best_rss = rss;
			best_open = open;
		}
	}

	return out;
}

pub fn table(w: *Writer, allocator: Allocator, rows: []const Row) !void {
	try w.print("{s:<14} {s:>8} {s:>11} {s:>10} {s:>11} {s:>12}  {s}\n", .{
		"widget", "open ms", "shell rssΔ", "shell cpu%", "daemon rssΔ", "daemon cpu%", "notes",
	});

	for (rows) |row| {
		if (row.status == .ok) {
			const open = try std.fmt.allocPrint(allocator, "{d:.1}", .{row.openMs orelse 0});
			const shell_rss = try mb(allocator, row.shellRssDeltaKb);
			const shell_cpu = try pctText(allocator, row.shellCpuPct);
			const daemon_rss = try mb(allocator, row.daemonRssDeltaKb);
			const daemon_cpu = try pctText(allocator, row.daemonCpuPct);

			try w.print("{s:<14} {s:>8} {s:>11} {s:>10} {s:>11} {s:>12}  {s}\n", .{
				row.widget, open, shell_rss, shell_cpu, daemon_rss, daemon_cpu, row.notes,
			});
			continue;
		}

		const label = if (row.status == .na) "n/a" else "FAIL";

		try w.print("{s:<14} {s:>8} {s:>11} {s:>10} {s:>11} {s:>12}  {s}\n", .{
			row.widget, label, "", "", "", "", row.reason,
		});
	}
}

fn mb(allocator: Allocator, value: ?i64) ![]const u8 {
	const kb = value orelse return "n/a";
	const sign: []const u8 = if (kb < 0) "-" else "+";
	const size: i64 = if (kb < 0) -kb else kb;

	return std.fmt.allocPrint(allocator, "{s}{d:.1}MB", .{ sign, @as(f64, @floatFromInt(size)) / 1024.0 });
}

fn pctText(allocator: Allocator, value: ?f64) ![]const u8 {
	const number = value orelse return "n/a";

	return std.fmt.allocPrint(allocator, "{d:.1}%", .{number});
}

pub fn stamp(allocator: Allocator, ms: i64) ![]u8 {
	const secs: u64 = if (ms <= 0) 0 else @intCast(@divTrunc(ms, 1000));
	const epoch = std.time.epoch.EpochSeconds{ .secs = secs };
	const day = epoch.getEpochDay();
	const year_day = day.calculateYearDay();
	const month_day = year_day.calculateMonthDay();
	const day_seconds = epoch.getDaySeconds();

	return std.fmt.allocPrint(allocator, "{d:0>4}{d:0>2}{d:0>2}-{d:0>2}{d:0>2}{d:0>2}", .{
		year_day.year,
		month_day.month.numeric(),
		month_day.day_index + 1,
		day_seconds.getHoursIntoDay(),
		day_seconds.getMinutesIntoHour(),
		day_seconds.getSecondsIntoMinute(),
	});
}


test "worst picks cpu then rss then open time" {
	const rows = [_]Row{
		.{ .widget = "a", .status = .ok, .openMs = 90, .shellCpuPct = 4, .shellRssDeltaKb = 100 },
		.{ .widget = "b", .status = .ok, .openMs = 10, .shellCpuPct = 9, .daemonCpuPct = 1, .shellRssDeltaKb = 10 },
		.{ .widget = "c", .status = .na, .reason = "control" },
	};

	try std.testing.expectEqualStrings("b", pickWorst(&rows).?.widget);

	const tie = [_]Row{
		.{ .widget = "a", .status = .ok, .openMs = 90, .shellCpuPct = 3, .shellRssDeltaKb = 500 },
		.{ .widget = "b", .status = .ok, .openMs = 10, .shellCpuPct = 3, .shellRssDeltaKb = 10 },
	};

	try std.testing.expectEqualStrings("a", pickWorst(&tie).?.widget);
	try std.testing.expect(pickWorst(&[_]Row{.{ .widget = "a", .status = .na, .reason = "x" }}) == null);
}

test "ranking puts measured rows first by open time" {
	var rows = [_]Row{
		.{ .widget = "na", .status = .na, .reason = "control" },
		.{ .widget = "slow", .status = .ok, .openMs = 80, .shellCpuPct = 1 },
		.{ .widget = "fast", .status = .ok, .openMs = 8, .shellCpuPct = 30 },
	};

	std.mem.sort(Row, &rows, {}, byRank);

	try std.testing.expectEqualStrings("fast", rows[0].widget);
	try std.testing.expectEqualStrings("slow", rows[1].widget);
	try std.testing.expectEqualStrings("na", rows[2].widget);
}

