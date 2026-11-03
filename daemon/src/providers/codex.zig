const std = @import("std");
const hubmod = @import("../hub.zig");
const http = @import("../primitives/http.zig");
const json = @import("../primitives/json.zig");
const proc = @import("../primitives/proc.zig");
const watch = @import("../primitives/watch.zig");
const limitmod = @import("../primitives/limits.zig");
const fmt = @import("../primitives/fmt.zig");
const sleep = @import("../primitives/sleep.zig");
const setStr = @import("opencode.zig").setStr;

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const Limit = struct {
	title: []u8,
	percent: f64,
	resets_at: []u8,
};

const LimitOut = struct {
	title: []const u8,
	percent: f64,
	resetsAt: []const u8,
};

const PlanOut = struct {
	title: []const u8,
	limits: []LimitOut,
};

const Out = struct {
	signedIn: bool,
	plan: []const u8,
	failure: []const u8,
	limits: []LimitOut,
};

pub const Codex = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	http: *http.Client,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	token: []u8 = &.{},
	account: []u8 = &.{},
	plan: []u8 = &.{},
	failure: []u8 = &.{},
	limits: std.ArrayListUnmanaged(Limit) = .empty,

	pub fn create(allocator: Allocator, io: Io, hub: *Hub, client: *http.Client) !*Codex {
		const self = try allocator.create(Codex);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.http = client,
			.scratch = std.heap.ArenaAllocator.init(allocator),
		};

		return self;
	}

	pub fn provider(self: *Codex) hubmod.Provider {
		return .{ .key = "codex", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Codex = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn start(self: *Codex) !void {
		const watcher = try std.Thread.spawn(.{}, watchLoop, .{self});
		watcher.detach();

		const poll = try std.Thread.spawn(.{}, pollLoop, .{self});
		poll.detach();
	}

	pub fn refreshPlan(self: *Codex) void {
		self.refresh();
	}

	pub fn planOut(self: *Codex, arena: Allocator) limitmod.Plan {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		return limitmod.copy(arena, self.plan, self.failure, self.limits.items) catch .{};
	}

	pub fn refresh(self: *Codex) void {
		self.readAuth();
		self.fetchUsage();
	}

	fn authPath(self: *Codex) []const u8 {
		const home = proc.env(self.io, self.allocator, "CODEX_HOME") orelse
			std.fmt.allocPrint(self.allocator, "{s}/.codex", .{proc.home(self.io, self.allocator)}) catch return "/nonexistent";

		return std.fmt.allocPrint(self.allocator, "{s}/auth.json", .{home}) catch "/nonexistent";
	}

	fn watchLoop(self: *Codex) void {
		self.refresh();
		watch.watchFile(self.io, self.allocator, self.authPath(), self, reloadThunk) catch {};
	}

	fn reloadThunk(ctx: *anyopaque) void {
		const self: *Codex = @ptrCast(@alignCast(ctx));
		self.refresh();
	}

	fn readAuth(self: *Codex) void {
		const path = self.authPath();
		defer self.allocator.free(path);

		const body = proc.readFile(self.io, self.allocator, path) catch "";
		defer if (body.len > 0) self.allocator.free(body);

		if (body.len == 0) {
			self.setSignedOut();
			return;
		}

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const parsed = json.parse(arena.allocator(), body) catch return;
		const root = parsed.value;

		if (!std.mem.eql(u8, json.textAt(root, "auth_mode"), "chatgpt")) {
			self.setSignedOut();
			return;
		}

		const token = json.textDeep(root, &.{ "tokens", "access_token" });
		const account = json.textDeep(root, &.{ "tokens", "account_id" });

		if (token.len == 0) {
			self.setSignedOut();
			return;
		}

		self.mutex.lockUncancelable(self.io);
		setStr(self.allocator, &self.token, token) catch {};
		setStr(self.allocator, &self.account, account) catch {};
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn setSignedOut(self: *Codex) void {
		self.mutex.lockUncancelable(self.io);
		setStr(self.allocator, &self.token, "") catch {};
		self.clearLimits();
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn clearLimits(self: *Codex) void {
		for (self.limits.items) |entry| {
			self.allocator.free(entry.title);
			self.allocator.free(entry.resets_at);
		}

		self.limits.deinit(self.allocator);
		self.limits = .empty;
	}

	fn fetchUsage(self: *Codex) void {
		self.mutex.lockUncancelable(self.io);
		const token = self.allocator.dupe(u8, self.token) catch {
			self.mutex.unlock(self.io);
			return;
		};
		const account = self.allocator.dupe(u8, self.account) catch {
			self.mutex.unlock(self.io);
			return;
		};
		self.mutex.unlock(self.io);

		defer self.allocator.free(token);
		defer self.allocator.free(account);

		if (token.len == 0) return;

		const auth = http.bearer(self.allocator, token) catch return;
		defer self.allocator.free(auth);

		const account_header = std.fmt.allocPrint(self.allocator, "{s}", .{account}) catch return;
		defer self.allocator.free(account_header);

		const extra = [_]std.http.Header{
			.{ .name = "chatgpt-account-id", .value = account_header },
		};

		const parsed = self.http.getJson(self.allocator, "https://chatgpt.com/backend-api/wham/usage", auth, &extra) catch {
			self.setFailure("plan unreachable");
			return;
		};
		defer parsed.deinit();

		const root = parsed.value;
		const rate = json.field(root, "rate_limit") orelse json.Value{ .null = {} };

		var next: std.ArrayListUnmanaged(Limit) = .empty;

		const windows = [_]struct { key: []const u8, fallback: []const u8 }{
			.{ .key = "primary_window", .fallback = "Session" },
			.{ .key = "secondary_window", .fallback = "Weekly" },
		};

		for (windows) |window| {
			const entry = json.field(rate, window.key) orelse continue;

			next.append(self.allocator, .{
				.title = self.allocator.dupe(u8, windowTitle(json.integer(json.field(entry, "limit_window_seconds")), window.fallback)) catch continue,
				.percent = json.numberAt(entry, "used_percent"),
				.resets_at = self.allocator.dupe(u8, resetText(self.allocator, json.integer(json.field(entry, "reset_at")))) catch continue,
			}) catch continue;
		}

		self.mutex.lockUncancelable(self.io);
		self.clearLimits();
		self.limits = next;
		setStr(self.allocator, &self.plan, json.textAt(root, "plan_type")) catch {};
		setStr(self.allocator, &self.failure, if (next.items.len == 0) "no plan" else "") catch {};
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn setFailure(self: *Codex, message: []const u8) void {
		self.mutex.lockUncancelable(self.io);
		setStr(self.allocator, &self.failure, message) catch {};
		self.mutex.unlock(self.io);
	}

	fn pollLoop(self: *Codex) void {
		while (true) {
			sleep.ms(300_000);
			self.fetchUsage();
		}
	}

	fn render(self: *Codex, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);
		const arena = self.scratch.allocator();

		var limits: std.ArrayListUnmanaged(LimitOut) = .empty;
		for (self.limits.items) |entry| {
			try limits.append(arena, .{ .title = entry.title, .percent = entry.percent, .resetsAt = entry.resets_at });
		}

		const out = Out{
			.signedIn = self.token.len > 0,
			.plan = self.plan,
			.failure = self.failure,
			.limits = limits.items,
		};

		try writer.print("{f}", .{std.json.fmt(out, .{})});
	}
};

fn windowTitle(seconds: i64, fallback: []const u8) []const u8 {
	if (seconds >= 7 * 86400) return "Monthly";
	if (seconds >= 86400) return "Weekly";
	if (seconds > 0) return "Session";

	return fallback;
}

fn resetText(allocator: Allocator, seconds: i64) []const u8 {
	if (seconds <= 0) return "";
	return fmt.isoFromMs(allocator, seconds * 1000) catch "";
}

test "window titles follow the window length" {
	try std.testing.expectEqualStrings("Monthly", windowTitle(30 * 86400, "Session"));
	try std.testing.expectEqualStrings("Monthly", windowTitle(7 * 86400, "Session"));
	try std.testing.expectEqualStrings("Weekly", windowTitle(6 * 86400, "Session"));
	try std.testing.expectEqualStrings("Session", windowTitle(3600, "Weekly"));
	try std.testing.expectEqualStrings("Weekly", windowTitle(0, "Weekly"));
}
