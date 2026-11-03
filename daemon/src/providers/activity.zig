const std = @import("std");
const proc = @import("../primitives/proc.zig");
const sleep = @import("../primitives/sleep.zig");
const Opencode = @import("opencode.zig").Opencode;

const Allocator = std.mem.Allocator;
const Io = std.Io;

const stale_ms: i64 = 600_000;
const recent_ms: i64 = 3_600_000;
const tail_bytes: u64 = 524_288;

const Kind = enum { claude, codex };

const Seen = struct {
	working: bool,
	blocked: bool,
	mtime: i64,
};

pub const Activity = struct {
	allocator: Allocator,
	io: Io,
	opencode: *Opencode,
	known: std.StringHashMapUnmanaged(Seen) = .empty,

	pub fn create(allocator: Allocator, io: Io, opencode: *Opencode) !*Activity {
		const self = try allocator.create(Activity);
		self.* = .{ .allocator = allocator, .io = io, .opencode = opencode };
		return self;
	}

	pub fn start(self: *Activity) !void {
		const thread = try std.Thread.spawn(.{}, loop, .{self});
		thread.detach();
	}

	fn loop(self: *Activity) void {
		const home = proc.home(self.io, self.allocator);

		while (true) {
			self.scanClaude(home);
			self.scanCodex(home);
			sleep.ms(2000);
		}
	}

	fn report(self: *Activity, id: []const u8, title: []const u8, provider: []const u8, path: []const u8, kind: Kind) void {
		const stat = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch return;
		const mtime: i64 = @intCast(@divTrunc(stat.mtime.nanoseconds, 1_000_000));
		const now = std.Io.Clock.real.now(self.io).toMilliseconds();
		const age = now - mtime;
		const last = self.known.get(id);

		if (last == null and age > recent_ms) return;

		const working = if (age >= stale_ms)
			false
		else if (last != null and last.?.mtime == mtime)
			last.?.working
		else
			self.decide(path, stat.size, kind);

		const blocked = working and kind == .claude and self.hookBlocked(id);

		if (last == null and !working) return;
		if (last != null and last.?.working == working and last.?.blocked == blocked) {
			self.known.getPtr(id).?.mtime = mtime;
			return;
		}

		if (last == null) {
			const key = self.allocator.dupe(u8, id) catch return;
			self.known.put(self.allocator, key, .{ .working = working, .blocked = blocked, .mtime = mtime }) catch return;
		} else {
			self.known.getPtr(id).?.* = .{ .working = working, .blocked = blocked, .mtime = mtime };
		}

		self.opencode.track(id, title, provider, working, blocked, mtime);
	}

	fn hookBlocked(self: *Activity, id: []const u8) bool {
		const path = std.fmt.allocPrint(self.allocator, "{s}/yudae-claude/{s}", .{ proc.runtimeDir(self.io, self.allocator), id }) catch return false;
		defer self.allocator.free(path);

		const body = proc.readFile(self.io, self.allocator, path) catch return false;
		defer self.allocator.free(body);

		return std.mem.startsWith(u8, body, "blocked");
	}

	fn decide(self: *Activity, path: []const u8, size: u64, kind: Kind) bool {
		var file = std.Io.Dir.cwd().openFile(self.io, path, .{}) catch return false;
		defer file.close(self.io);

		const length: usize = @intCast(@min(size, tail_bytes));
		const buffer = self.allocator.alloc(u8, length) catch return false;
		defer self.allocator.free(buffer);

		var scratch: [4096]u8 = undefined;
		var reader = file.reader(self.io, &scratch);
		reader.seekTo(size - length) catch return false;
		const count = reader.interface.readSliceShort(buffer) catch return false;
		const tail = buffer[0..count];

		return switch (kind) {
			.claude => claudeWorking(tail),
			.codex => codexWorking(tail),
		};
	}

	fn scanClaude(self: *Activity, home: []const u8) void {
		const base = std.fmt.allocPrint(self.allocator, "{s}/.claude/projects", .{home}) catch return;
		defer self.allocator.free(base);

		var projects = std.Io.Dir.cwd().openDir(self.io, base, .{ .iterate = true }) catch return;
		defer projects.close(self.io);

		const prefix = std.fmt.allocPrint(self.allocator, "{s}-", .{std.mem.replaceOwned(u8, self.allocator, home, "/", "-") catch return}) catch return;
		defer self.allocator.free(prefix);

		var outer = projects.iterate();
		while (outer.next(self.io) catch null) |project| {
			if (project.kind != .directory) continue;

			const folder = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ base, project.name }) catch continue;
			defer self.allocator.free(folder);

			var title: []const u8 = project.name;
			if (std.mem.startsWith(u8, title, prefix)) title = title[prefix.len..];
			title = std.mem.trimStart(u8, title, "-");
			if (title.len == 0) title = "home";

			var dir = std.Io.Dir.cwd().openDir(self.io, folder, .{ .iterate = true }) catch continue;
			defer dir.close(self.io);

			var inner = dir.iterate();
			while (inner.next(self.io) catch null) |item| {
				if (item.kind != .file or !std.mem.endsWith(u8, item.name, ".jsonl")) continue;

				const path = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ folder, item.name }) catch continue;
				defer self.allocator.free(path);
				self.report(item.name[0 .. item.name.len - 6], title, "claude", path, .claude);
			}
		}
	}

	fn scanCodex(self: *Activity, home: []const u8) void {
		var path = std.fmt.allocPrint(self.allocator, "{s}/.codex/sessions", .{home}) catch return;

		var level: usize = 0;
		while (level < 3) : (level += 1) {
			const next = self.greatest(path) orelse {
				self.allocator.free(path);
				return;
			};
			self.allocator.free(path);
			path = next;
		}
		defer self.allocator.free(path);

		var dir = std.Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true }) catch return;
		defer dir.close(self.io);

		var it = dir.iterate();
		while (it.next(self.io) catch null) |item| {
			if (item.kind != .file or !std.mem.endsWith(u8, item.name, ".jsonl")) continue;

			const file = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ path, item.name }) catch continue;
			defer self.allocator.free(file);
			self.report(item.name[0 .. item.name.len - 6], "codex", "openai", file, .codex);
		}
	}

	fn greatest(self: *Activity, path: []const u8) ?[]u8 {
		var dir = std.Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true }) catch return null;
		defer dir.close(self.io);

		var top: [64]u8 = undefined;
		var top_len: usize = 0;
		var it = dir.iterate();
		while (it.next(self.io) catch null) |item| {
			if (item.kind != .directory or item.name.len > top.len) continue;
			if (top_len == 0 or std.mem.order(u8, item.name, top[0..top_len]) == .gt) {
				@memcpy(top[0..item.name.len], item.name);
				top_len = item.name.len;
			}
		}

		if (top_len == 0) return null;
		return std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ path, top[0..top_len] }) catch null;
	}
};

fn claudeWorking(tail: []const u8) bool {
	var end = tail.len;

	while (end > 0) {
		const start = if (std.mem.lastIndexOfScalar(u8, tail[0..end], '\n')) |at| at + 1 else 0;
		const line = tail[start..end];
		end = if (start == 0) 0 else start - 1;

		if (std.mem.indexOf(u8, line, "\"subtype\":\"turn_duration\"") != null) return false;
		if (std.mem.indexOf(u8, line, "\"subtype\":\"local_command\"") != null) return false;

		if (std.mem.indexOf(u8, line, "\"type\":\"assistant\"") != null)
			return std.mem.indexOf(u8, line, "\"stop_reason\":\"end_turn\"") == null;

		if (std.mem.indexOf(u8, line, "\"type\":\"user\"") != null)
			return std.mem.indexOf(u8, line, "Request interrupted") == null and
				std.mem.indexOf(u8, line, "<local-command") == null and
				std.mem.indexOf(u8, line, "<command-name>") == null;
	}

	return false;
}

fn codexWorking(tail: []const u8) bool {
	const started = std.mem.lastIndexOf(u8, tail, "\"type\":\"task_started\"") orelse return false;
	const done = std.mem.lastIndexOf(u8, tail, "\"type\":\"task_complete\"") orelse 0;
	const aborted = std.mem.lastIndexOf(u8, tail, "\"type\":\"turn_aborted\"") orelse 0;

	return started > done and started > aborted;
}

test "claude is working until the turn ends" {
	try std.testing.expect(claudeWorking("{\"type\":\"user\",\"message\":\"hi\"}\n{\"type\":\"assistant\",\"message\":{\"stop_reason\":\"tool_use\"}}\n{\"type\":\"attachment\"}\n"));
	try std.testing.expect(!claudeWorking("{\"type\":\"assistant\",\"message\":{\"stop_reason\":\"end_turn\"}}\n{\"type\":\"mode\"}\n"));
	try std.testing.expect(!claudeWorking("{\"type\":\"assistant\"}\n{\"type\":\"user\",\"message\":\"[Request interrupted by user]\"}\n"));
}

test "a slash command is not work" {
	try std.testing.expect(!claudeWorking("{\"type\":\"user\",\"message\":\"<command-name>/reload-plugins</command-name>\"}\n{\"type\":\"system\",\"subtype\":\"local_command\"}\n"));
}

test "codex is working between started and complete" {
	try std.testing.expect(codexWorking("{\"type\":\"task_started\"}\n"));
	try std.testing.expect(!codexWorking("{\"type\":\"task_started\"}\n{\"type\":\"task_complete\"}\n"));
}
