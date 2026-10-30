const std = @import("std");
const http = @import("../primitives/http.zig");
const json = @import("../primitives/json.zig");
const proc = @import("../primitives/proc.zig");
const limitmod = @import("../primitives/limits.zig");
const watch = @import("../primitives/watch.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const usage_url = "https://api.anthropic.com/api/oauth/usage";

pub const Claude = struct {
	allocator: Allocator,
	io: Io,
	http: *http.Client,
	mutex: std.Io.Mutex = .init,
	plan: []u8 = &.{},
	failure: []u8 = &.{},
	limits: std.ArrayListUnmanaged(Limit) = .empty,

	const Limit = struct {
		title: []u8,
		percent: f64,
		resets_at: []u8,
	};

	pub fn create(allocator: Allocator, io: Io, client: *http.Client) !*Claude {
		const self = try allocator.create(Claude);
		self.* = .{ .allocator = allocator, .io = io, .http = client };
		return self;
	}

	pub fn start(self: *Claude) !void {
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
		const path = self.credentialsPath() catch return;
		defer self.allocator.free(path);

		const body = proc.readFile(self.io, self.allocator, path) catch {
			self.clear();
			return;
		};
		defer self.allocator.free(body);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const creds = json.parse(arena.allocator(), body) catch return;
		const token = json.textDeep(creds.value, &.{ "claudeAiOauth", "accessToken" });
		const plan = json.textDeep(creds.value, &.{ "claudeAiOauth", "subscriptionType" });

		if (token.len == 0) {
			self.clear();
			return;
		}

		const expires = json.integer(json.deep(creds.value, &.{ "claudeAiOauth", "expiresAt" }));
		if (expires > 0 and expires <= std.Io.Clock.real.now(self.io).toMilliseconds()) {
			self.setFailure(plan, "plan expired");
			return;
		}

		const auth = http.bearer(self.allocator, token) catch return;
		defer self.allocator.free(auth);

		const extra = [_]std.http.Header{.{ .name = "anthropic-beta", .value = "oauth-2025-04-20" }};

		const reply = self.http.get(self.allocator, usage_url, auth, &extra) catch {
			self.setFailure(plan, "plan unreachable");
			return;
		};
		defer reply.deinit(self.allocator);

		if (!reply.ok()) {
			self.setFailure(plan, "plan unavailable");
			return;
		}

		const parsed = json.parse(arena.allocator(), reply.body) catch {
			self.setFailure(plan, "plan unavailable");
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

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		self.freeLimits();
		self.limits = next;
		self.replace(&self.plan, plan);
		self.replace(&self.failure, if (next.items.len == 0) "no plan" else "");
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
};
