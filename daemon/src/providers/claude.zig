const std = @import("std");
const http = @import("../primitives/http.zig");
const json = @import("../primitives/json.zig");
const proc = @import("../primitives/proc.zig");
const limitmod = @import("../primitives/limits.zig");
const watch = @import("../primitives/watch.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const usage_url = "https://api.anthropic.com/api/oauth/usage";
const normal_refresh_ms = 240_000;
const error_refresh_ms = 300_000;
const rate_limit_refresh_ms = 3_600_000;
const cache_max_age_ms = 86_400_000;

pub const Claude = struct {
	allocator: Allocator,
	io: Io,
	http: *http.Client,
	mutex: std.Io.Mutex = .init,
	plan: []u8 = &.{},
	failure: []u8 = &.{},
	limits: std.ArrayListUnmanaged(Limit) = .empty,
	fetching: bool = false,
	next_refresh: i64 = 0,

	const Limit = struct {
		title: []u8,
		percent: f64,
		resets_at: []u8,
	};

	const CachedLimit = struct {
		title: []const u8,
		percent: f64,
		resetsAt: []const u8,
	};

	const Cache = struct {
		plan: []const u8,
		savedAt: i64,
		limits: []CachedLimit,
	};

	pub fn create(allocator: Allocator, io: Io, client: *http.Client) !*Claude {
		const self = try allocator.create(Claude);
		self.* = .{ .allocator = allocator, .io = io, .http = client };
		return self;
	}

	pub fn start(self: *Claude) !void {
		self.loadCache();

		const thread = try std.Thread.spawn(.{}, watchLoop, .{self});
		thread.detach();
	}

	fn watchLoop(self: *Claude) void {
		self.refreshPlan();
		const path = self.credentialsPath() catch return;
		defer self.allocator.free(path);
		watch.watchFile(self.io, self.allocator, path, self, reloadThunk) catch {};
	}

	fn reloadThunk(ctx: *anyopaque) void {
		const self: *Claude = @ptrCast(@alignCast(ctx));
		self.refreshPlan();
	}

	fn credentialsPath(self: *Claude) ![]u8 {
		const home = proc.home(self.io, self.allocator);
		return std.fmt.allocPrint(self.allocator, "{s}/.claude/.credentials.json", .{home});
	}

	pub fn planOut(self: *Claude, arena: Allocator) limitmod.Plan {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		return limitmod.copy(arena, self.plan, self.failure, self.limits.items) catch .{};
	}

	pub fn refreshPlan(self: *Claude) void {
		if (!self.beginRefresh())
			return;

		var cooldown: i64 = normal_refresh_ms;
		defer self.endRefresh(cooldown);

		const path = self.credentialsPath() catch return;
		defer self.allocator.free(path);

		const body = proc.readFile(self.io, self.allocator, path) catch {
			self.clear();
			cooldown = error_refresh_ms;
			return;
		};
		defer self.allocator.free(body);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const creds = json.parse(arena.allocator(), body) catch {
			cooldown = error_refresh_ms;
			return;
		};
		const token = json.textDeep(creds.value, &.{ "claudeAiOauth", "accessToken" });
		const plan = json.textDeep(creds.value, &.{ "claudeAiOauth", "subscriptionType" });

		if (token.len == 0) {
			self.clear();
			cooldown = error_refresh_ms;
			return;
		}

		const expires = json.integer(json.deep(creds.value, &.{ "claudeAiOauth", "expiresAt" }));
		if (expires > 0 and expires <= std.Io.Clock.real.now(self.io).toMilliseconds()) {
			self.setFailure(plan, "plan expired");
			cooldown = rate_limit_refresh_ms;
			return;
		}

		const auth = http.bearer(self.allocator, token) catch return;
		defer self.allocator.free(auth);

		const extra = [_]std.http.Header{.{ .name = "anthropic-beta", .value = "oauth-2025-04-20" }};

		const reply = self.http.get(self.allocator, usage_url, auth, &extra) catch {
			self.setTransientFailure(plan, "plan unreachable");
			cooldown = error_refresh_ms;
			return;
		};
		defer reply.deinit(self.allocator);

		if (!reply.ok()) {
			const limited = reply.status == .too_many_requests;

			self.setTransientFailure(plan, if (limited) "rate limited" else "plan unavailable");
			cooldown = if (limited) rate_limit_refresh_ms else error_refresh_ms;
			return;
		}

		const parsed = json.parse(arena.allocator(), reply.body) catch {
			self.setTransientFailure(plan, "plan unavailable");
			cooldown = error_refresh_ms;
			return;
		};

		var next: std.ArrayListUnmanaged(Limit) = .empty;

		const windows = [_]struct { key: []const u8, title: []const u8 }{
			.{ .key = "five_hour", .title = "Session" },
			.{ .key = "seven_day", .title = "Weekly" },
		};

		for (windows) |window| {
			const entry = json.field(parsed.value, window.key) orelse continue;
			if (entry == .null) continue;

			const title = self.allocator.dupe(u8, window.title) catch continue;
			const resets = self.allocator.dupe(u8, json.textAt(entry, "resets_at")) catch {
				self.allocator.free(title);
				continue;
			};

			next.append(self.allocator, .{ .title = title, .percent = json.numberAt(entry, "utilization"), .resets_at = resets }) catch {
				self.allocator.free(title);
				self.allocator.free(resets);
			};
		}

		{
			self.mutex.lockUncancelable(self.io);
			defer self.mutex.unlock(self.io);

			self.freeLimits();
			self.limits = next;
			self.replace(&self.plan, plan);
			self.replace(&self.failure, if (next.items.len == 0) "no plan" else "");
		}

		if (next.items.len > 0)
			self.saveCache();
	}

	fn beginRefresh(self: *Claude) bool {
		const now = std.Io.Clock.real.now(self.io).toMilliseconds();

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		if (self.fetching or now < self.next_refresh)
			return false;

		self.fetching = true;
		return true;
	}

	fn endRefresh(self: *Claude, cooldown: i64) void {
		const now = std.Io.Clock.real.now(self.io).toMilliseconds();

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		self.fetching = false;
		self.next_refresh = now + cooldown;
	}

	fn setTransientFailure(self: *Claude, plan: []const u8, message: []const u8) void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		self.replace(&self.plan, plan);
		self.replace(&self.failure, if (self.limits.items.len == 0) message else "");
	}

	fn setFailure(self: *Claude, plan: []const u8, message: []const u8) void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		self.replace(&self.plan, plan);
		self.replace(&self.failure, message);
	}

	fn clear(self: *Claude) void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		self.freeLimits();
		self.limits = .empty;
		self.replace(&self.failure, "");
	}

	fn freeLimits(self: *Claude) void {
		for (self.limits.items) |entry| {
			self.allocator.free(entry.title);
			self.allocator.free(entry.resets_at);
		}

		self.limits.deinit(self.allocator);
	}

	fn replace(self: *Claude, slot: *[]u8, value: []const u8) void {
		const copy = self.allocator.dupe(u8, value) catch return;
		if (slot.len > 0) self.allocator.free(slot.*);
		slot.* = copy;
	}

	fn cachePath(self: *Claude) ![]u8 {
		const home = proc.home(self.io, self.allocator);
		return std.fmt.allocPrint(self.allocator, "{s}/dotfiles/shell/cache/claude-plan.json", .{home});
	}

	fn loadCache(self: *Claude) void {
		const path = self.cachePath() catch return;
		defer self.allocator.free(path);

		const body = proc.readFile(self.io, self.allocator, path) catch return;
		defer self.allocator.free(body);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const parsed = json.parse(arena.allocator(), body) catch return;
		const saved = json.integer(json.field(parsed.value, "savedAt"));
		const now = std.Io.Clock.real.now(self.io).toMilliseconds();

		if (saved > 0 and now - saved > cache_max_age_ms)
			return;

		const plan = json.textAt(parsed.value, "plan");
		const rows = json.listAt(parsed.value, "limits");

		if (rows.len == 0)
			return;

		var next: std.ArrayListUnmanaged(Limit) = .empty;

		for (rows) |row| {
			const title = json.textAt(row, "title");
			if (title.len == 0) continue;

			const title_copy = self.allocator.dupe(u8, title) catch continue;
			const resets = self.allocator.dupe(u8, json.textAt(row, "resetsAt")) catch {
				self.allocator.free(title_copy);
				continue;
			};

			next.append(self.allocator, .{ .title = title_copy, .percent = json.numberAt(row, "percent"), .resets_at = resets }) catch {
				self.allocator.free(title_copy);
				self.allocator.free(resets);
			};
		}

		if (next.items.len == 0) {
			next.deinit(self.allocator);
			return;
		}

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		self.freeLimits();
		self.limits = next;
		self.replace(&self.plan, plan);
		self.replace(&self.failure, "");
	}

	fn saveCache(self: *Claude) void {
		const path = self.cachePath() catch return;
		defer self.allocator.free(path);

		std.Io.Dir.cwd().createDirPath(self.io, std.fs.path.dirname(path) orelse ".") catch {};

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		var out: std.Io.Writer.Allocating = .init(self.allocator);
		defer out.deinit();

		{
			self.mutex.lockUncancelable(self.io);
			defer self.mutex.unlock(self.io);

			var limits: std.ArrayListUnmanaged(CachedLimit) = .empty;

			for (self.limits.items) |entry| {
				limits.append(arena.allocator(), .{
					.title = entry.title,
					.percent = entry.percent,
					.resetsAt = entry.resets_at,
				}) catch return;
			}

			const cache = Cache{
				.plan = self.plan,
				.savedAt = std.Io.Clock.real.now(self.io).toMilliseconds(),
				.limits = limits.items,
			};

			out.writer.print("{f}", .{std.json.fmt(cache, .{})}) catch return;
		}

		proc.writeFileAtomic(self.io, self.allocator, path, out.written()) catch {};
	}
};

test "a plan rests between fetches and keeps its numbers when a fetch fails" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();
	var client = http.Client.init(allocator, std.testing.io);
	const plan = try Claude.create(allocator, std.testing.io, &client);

	try std.testing.expect(plan.beginRefresh());
	plan.endRefresh(60_000);
	try std.testing.expect(!plan.beginRefresh());

	plan.next_refresh = 0;
	try std.testing.expect(plan.beginRefresh());

	const title = try allocator.dupe(u8, "Weekly");
	const resets = try allocator.dupe(u8, "2026-11-07T23:00:00+00:00");
	try plan.limits.append(allocator, .{ .title = title, .percent = 16, .resets_at = resets });

	plan.setTransientFailure("pro", "rate limited");

	try std.testing.expectEqual(@as(usize, 1), plan.limits.items.len);
	try std.testing.expectEqualStrings("", plan.failure);
}
