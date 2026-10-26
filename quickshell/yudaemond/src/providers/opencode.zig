const std = @import("std");
const hubmod = @import("../hub.zig");
const http = @import("../primitives/http.zig");
const json = @import("../primitives/json.zig");
const proc = @import("../primitives/proc.zig");
const watch = @import("../primitives/watch.zig");
const limitmod = @import("../primitives/limits.zig");
const fmt = @import("../primitives/fmt.zig");
const sleep = @import("../primitives/sleep.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const Session = struct {
	id: []u8,
	title: []u8 = &.{},
	provider: []u8 = &.{},
	parent: []u8 = &.{},
	directory: []u8 = &.{},
	status: []u8 = &.{},
	blocked: []u8 = &.{},
	failure: []u8 = &.{},
	updated: i64 = 0,
};

const Done = struct {
	id: []u8,
	title: []u8,
	at: i64,
};

const Limit = struct {
	title: []u8,
	percent: f64,
	resets_at: []u8,
};

const SessionOut = struct {
	id: []const u8,
	title: []const u8,
	provider: []const u8,
	parent: []const u8,
	directory: []const u8,
	status: []const u8,
	blocked: []const u8,
	failure: []const u8,
	updated: i64,
};

const DoneOut = struct {
	id: []const u8,
	title: []const u8,
	at: i64,
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
	connected: bool,
	state: []const u8,
	detail: []const u8,
	failure: []const u8,
	usageError: []const u8,
	sessions: []SessionOut,
	running: [][]const u8,
	asking: [][]const u8,
	done: []DoneOut,
	plan: ?PlanOut,
};

pub const Opencode = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	http: *http.Client,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	sessions: std.StringHashMapUnmanaged(*Session) = .empty,
	running: std.ArrayListUnmanaged([]u8) = .empty,
	asking: std.ArrayListUnmanaged([]u8) = .empty,
	asked: std.StringHashMapUnmanaged(void) = .empty,
	done: std.ArrayListUnmanaged(Done) = .empty,
	limits: std.ArrayListUnmanaged(Limit) = .empty,
	url: []u8 = &.{},
	password: []u8 = &.{},
	access_token: []u8 = &.{},
	connect_error: []u8 = &.{},
	usage_error: []u8 = &.{},
	plan_title: []u8 = &.{},
	resync: std.atomic.Value(bool) = .init(false),

	pub fn create(allocator: Allocator, io: Io, hub: *Hub, client: *http.Client) !*Opencode {
		const self = try allocator.create(Opencode);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.http = client,
			.scratch = std.heap.ArenaAllocator.init(allocator),
			.plan_title = try allocator.dupe(u8, "OpenCode"),
		};

		return self;
	}

	pub fn provider(self: *Opencode) hubmod.Provider {
		return .{ .key = "opencode", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Opencode = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn start(self: *Opencode) !void {
		const watcher = try std.Thread.spawn(.{}, watchLoop, .{self});
		watcher.detach();

		const stream = try std.Thread.spawn(.{}, streamLoop, .{self});
		stream.detach();

		const poll = try std.Thread.spawn(.{}, pollLoop, .{self});
		poll.detach();
	}

	pub fn refreshAll(self: *Opencode) void {
		self.refreshSessions();
		self.refreshRunning();
		self.refreshQuestions();
		self.refreshUsage();
	}

	pub fn dismiss(self: *Opencode, id: []const u8) void {
		self.mutex.lockUncancelable(self.io);

		var index: usize = 0;
		while (index < self.done.items.len) {
			if (std.mem.eql(u8, self.done.items[index].id, id)) {
				const entry = self.done.orderedRemove(index);
				self.allocator.free(entry.id);
				self.allocator.free(entry.title);
				continue;
			}

			index += 1;
		}

		self.mutex.unlock(self.io);
		self.hub.publish();
	}

	fn watchLoop(self: *Opencode) void {
		self.reloadService();
		watch.watchFile(self.io, self.allocator, self.servicePath(), self, reloadThunk) catch {};
	}

	fn reloadThunk(ctx: *anyopaque) void {
		const self: *Opencode = @ptrCast(@alignCast(ctx));
		self.reloadService();
	}

	fn servicePath(self: *Opencode) []const u8 {
		return std.fmt.allocPrint(self.allocator, "{s}/opencode/service.json", .{proc.stateHome(self.io, self.allocator)}) catch "/nonexistent";
	}

	fn reloadService(self: *Opencode) void {
		const path = self.servicePath();
		defer self.allocator.free(path);

		const body = proc.readFile(self.io, self.allocator, path) catch "";
		defer if (body.len > 0) self.allocator.free(body);

		if (body.len == 0) return;

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const parsed = json.parse(arena.allocator(), body) catch return;
		const url = json.textAt(parsed.value, "url");
		const password = json.textAt(parsed.value, "password");

		if (url.len == 0 or password.len == 0) return;

		self.mutex.lockUncancelable(self.io);
		setStr(self.allocator, &self.url, url) catch {};
		setStr(self.allocator, &self.password, password) catch {};
		self.mutex.unlock(self.io);

		self.refreshSessions();
		self.hub.publish();
	}

	fn authHeader(self: *Opencode) ?[]u8 {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		if (self.url.len == 0 or self.password.len == 0) return null;

		const user = "opencode";
		const pair = std.fmt.allocPrint(self.allocator, "{s}:{s}", .{ user, self.password }) catch return null;
		defer self.allocator.free(pair);

		const encoder = std.base64.standard.Encoder;
		const out = self.allocator.alloc(u8, 6 + encoder.calcSize(pair.len)) catch return null;
		@memcpy(out[0..6], "Basic ");
		_ = encoder.encode(out[6..], pair);

		return out;
	}

	fn baseUrl(self: *Opencode, allocator: Allocator) ?[]u8 {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		if (self.url.len == 0) return null;
		return allocator.dupe(u8, self.url) catch null;
	}

	fn streamLoop(self: *Opencode) void {
		while (true) {
			const url = self.baseUrl(self.allocator) orelse {
				sleep.ms(1000);
				continue;
			};
			defer self.allocator.free(url);

			const auth = self.authHeader() orelse {
				sleep.ms(1000);
				continue;
			};
			defer self.allocator.free(auth);

			const target = std.fmt.allocPrint(self.allocator, "{s}/api/event", .{url}) catch continue;
			defer self.allocator.free(target);

			self.http.stream(target, auth, self, eventThunk) catch {
				sleep.ms(2000);
				continue;
			};

			sleep.ms(500);
		}
	}

	fn eventThunk(ctx: *anyopaque, line: []const u8) void {
		const self: *Opencode = @ptrCast(@alignCast(ctx));

		const trimmed = std.mem.trim(u8, line, " \r");
		if (!std.mem.startsWith(u8, trimmed, "data: ")) return;

		self.handleEvent(trimmed[6..]);
	}

	pub fn handleEvent(self: *Opencode, body: []const u8) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const parsed = json.parse(arena.allocator(), body) catch return;
		const root = parsed.value;
		const kind = json.textAt(root, "type");

		if (std.mem.eql(u8, kind, "server.connected")) {
			self.resync.store(true, .release);
			return;
		}

		const data = json.field(root, "data") orelse json.field(root, "properties") orelse return;

		var id = json.textAt(data, "sessionID");
		if (id.len == 0) id = json.textAt(data, "sessionId");

		if (std.mem.eql(u8, kind, "session.created") or std.mem.eql(u8, kind, "session.renamed")) {
			if (id.len == 0) return;

			self.mutex.lockUncancelable(self.io);
			const session = self.sessionFor(id) catch {
				self.mutex.unlock(self.io);
				return;
			};
			const title = json.textAt(data, "title");
			if (title.len > 0) setStr(self.allocator, &session.title, title) catch {};
			const provider_id = json.textDeep(data, &.{ "model", "providerID" });
			if (provider_id.len > 0) setStr(self.allocator, &session.provider, provider_id) catch {};
			const parent = json.textAt(data, "parentID");
			if (parent.len > 0) setStr(self.allocator, &session.parent, parent) catch {};
			const directory = json.textAt(data, "directory");
			if (directory.len == 0) {
				const nested = json.textDeep(data, &.{ "location", "directory" });
				if (nested.len > 0) setStr(self.allocator, &session.directory, nested) catch {};
			} else {
				setStr(self.allocator, &session.directory, directory) catch {};
			}
			session.updated = fmt.nowMs(self.io);
			self.mutex.unlock(self.io);

			self.hub.publish();
			return;
		}

		if (id.len == 0) return;

		if (std.mem.eql(u8, kind, "permission.asked")) {
			self.patch(id, .{ .blocked = permissionText(data) });
			return;
		}

		if (std.mem.eql(u8, kind, "form.created")) {
			var title = json.textAt(data, "title");
			if (title.len == 0) title = "question";
			self.patch(id, .{ .blocked = title });
			return;
		}

		if (std.mem.eql(u8, kind, "permission.replied") or std.mem.eql(u8, kind, "form.replied") or std.mem.eql(u8, kind, "form.cancelled")) {
			self.patch(id, .{ .blocked = "" });
			return;
		}

		if (std.mem.eql(u8, kind, "session.status")) {
			const status = json.textDeep(data, &.{ "status", "type" });
			self.patch(id, .{ .status = if (status.len == 0) "idle" else status });
			return;
		}

		if (std.mem.eql(u8, kind, "session.execution.started")) {
			self.patch(id, .{ .status = "busy", .failure = "" });
			return;
		}

		if (std.mem.eql(u8, kind, "session.execution.failed")) {
			var message = json.textDeep(data, &.{ "error", "message" });
			if (message.len == 0) message = "failed";
			self.patch(id, .{ .status = "idle", .failure = message });
			return;
		}

		if (std.mem.eql(u8, kind, "session.execution.succeeded")) {
			self.patch(id, .{ .status = "idle" });
			self.finish(id);
			return;
		}

		if (std.mem.eql(u8, kind, "session.execution.interrupted") or std.mem.eql(u8, kind, "session.idle")) {
			self.patch(id, .{ .status = "idle" });
			return;
		}
	}

	fn finish(self: *Opencode, id: []const u8) void {
		self.mutex.lockUncancelable(self.io);

		const title = self.titleLocked(id);
		const copy_id = self.allocator.dupe(u8, id) catch {
			self.mutex.unlock(self.io);
			return;
		};
		const copy_title = self.allocator.dupe(u8, if (title.len == 0) "agent" else title) catch {
			self.allocator.free(copy_id);
			self.mutex.unlock(self.io);
			return;
		};

		self.done.insert(self.allocator, 0, .{ .id = copy_id, .title = copy_title, .at = fmt.nowMs(self.io) }) catch {
			self.allocator.free(copy_id);
			self.allocator.free(copy_title);
			self.mutex.unlock(self.io);
			return;
		};

		while (self.done.items.len > 20) {
			const entry = self.done.pop().?;
			self.allocator.free(entry.id);
			self.allocator.free(entry.title);
		}

		self.mutex.unlock(self.io);
		self.hub.publish();
	}

	const Patch = struct {
		status: ?[]const u8 = null,
		blocked: ?[]const u8 = null,
		failure: ?[]const u8 = null,
	};

	fn patch(self: *Opencode, id: []const u8, changes: Patch) void {
		self.mutex.lockUncancelable(self.io);
		const session = self.sessionFor(id) catch {
			self.mutex.unlock(self.io);
			return;
		};

		if (changes.status) |status| setStr(self.allocator, &session.status, status) catch {};
		if (changes.blocked) |blocked| setStr(self.allocator, &session.blocked, blocked) catch {};
		if (changes.failure) |err| setStr(self.allocator, &session.failure, err) catch {};
		session.updated = fmt.nowMs(self.io);
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn sessionFor(self: *Opencode, id: []const u8) !*Session {
		if (self.sessions.get(id)) |session| return session;

		const session = try self.allocator.create(Session);
		session.* = .{ .id = try self.allocator.dupe(u8, id) };
		try self.sessions.put(self.allocator, session.id, session);

		return session;
	}

	fn titleLocked(self: *Opencode, id: []const u8) []const u8 {
		if (self.sessions.get(id)) |session| {
			if (session.title.len > 0) return session.title;
		}

		return "";
	}

	fn pollLoop(self: *Opencode) void {
		var tick: usize = 0;

		while (true) {
			sleep.ms(1000);
			tick += 1;

			if (self.resync.swap(false, .acquire)) {
				self.refreshSessions();
				self.refreshRunning();
				self.refreshQuestions();
			} else if (tick % 10 == 0) {
				self.refreshRunning();
				self.refreshQuestions();
			}

			if (tick % 30 == 0) self.refreshSessions();
			if (tick % 300 == 0) self.refreshUsage();
		}
	}

	fn refreshSessions(self: *Opencode) void {
		const url = self.baseUrl(self.allocator) orelse return;
		defer self.allocator.free(url);

		const auth = self.authHeader() orelse return;
		defer self.allocator.free(auth);

		const target = std.fmt.allocPrint(self.allocator, "{s}/api/session?order=desc&limit=50", .{url}) catch return;
		defer self.allocator.free(target);

		const parsed = self.http.getJson(self.allocator, target, auth, &.{}) catch return;
		defer parsed.deinit();

		self.mutex.lockUncancelable(self.io);
		for (json.listAt(parsed.value, "data")) |entry| {
			const id = json.textAt(entry, "id");
			if (id.len == 0) continue;

			const session = self.sessionFor(id) catch continue;
			const title = json.textAt(entry, "title");
			if (title.len > 0) setStr(self.allocator, &session.title, title) catch {};
			const provider_id = json.textDeep(entry, &.{ "model", "providerID" });
			if (provider_id.len > 0) setStr(self.allocator, &session.provider, provider_id) catch {};
			const parent = json.textAt(entry, "parentID");
			if (parent.len > 0) setStr(self.allocator, &session.parent, parent) catch {};
			const directory = json.textDeep(entry, &.{ "location", "directory" });
			if (directory.len > 0) setStr(self.allocator, &session.directory, directory) catch {};
		}
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn refreshRunning(self: *Opencode) void {
		const url = self.baseUrl(self.allocator) orelse return;
		defer self.allocator.free(url);

		const auth = self.authHeader() orelse return;
		defer self.allocator.free(auth);

		const target = std.fmt.allocPrint(self.allocator, "{s}/api/session/active", .{url}) catch return;
		defer self.allocator.free(target);

		const parsed = self.http.getJson(self.allocator, target, auth, &.{}) catch return;
		defer parsed.deinit();

		const data = json.field(parsed.value, "data") orelse return;
		const entries = switch (data) {
			.object => |map| map,
			else => return,
		};

		var next: std.ArrayListUnmanaged([]u8) = .empty;

		self.mutex.lockUncancelable(self.io);

		var it = entries.iterator();
		while (it.next()) |entry| {
			const id = entry.key_ptr.*;

			const copy = self.allocator.dupe(u8, id) catch continue;
			next.append(self.allocator, copy) catch {
				self.allocator.free(copy);
				continue;
			};
		}

		var changed = self.running.items.len != next.items.len;

		if (!changed) {
			for (next.items) |id| {
				if (inList(self.running.items, id)) continue;
				changed = true;
				break;
			}
		}

		if (self.clearStaleBusyLocked(next.items)) changed = true;

		for (self.running.items) |old| self.allocator.free(old);
		self.running.deinit(self.allocator);
		self.running = next;
		self.mutex.unlock(self.io);

		if (changed) {
			self.refreshSessions();
			self.hub.publish();
		}
	}

	fn clearStaleBusyLocked(self: *Opencode, running: []const []u8) bool {
		var changed = false;

		var it = self.sessions.iterator();
		while (it.next()) |entry| {
			const session = entry.value_ptr.*;
			if (!isBusy(session.status)) continue;
			if (inList(running, session.id)) continue;

			setStr(self.allocator, &session.status, "idle") catch {};
			changed = true;
		}

		return changed;
	}

	fn refreshQuestions(self: *Opencode) void {
		const url = self.baseUrl(self.allocator) orelse return;
		defer self.allocator.free(url);

		const auth = self.authHeader() orelse return;
		defer self.allocator.free(auth);

		const dirs = self.questionDirs();
		defer {
			for (dirs) |dir| self.allocator.free(dir);
			self.allocator.free(dirs);
		}

		if (dirs.len == 0) return;

		var next: std.ArrayListUnmanaged([]u8) = .empty;
		var seen: std.StringHashMapUnmanaged(void) = .empty;
		defer seen.deinit(self.allocator);

		for (dirs) |dir| {
			const encoded = http.encodeQuery(self.allocator, dir) catch continue;
			defer self.allocator.free(encoded);

			const endpoints = [_][]const u8{ "form", "permission/request" };
			for (endpoints) |endpoint| {
				const target = std.fmt.allocPrint(self.allocator, "{s}/api/{s}?location[directory]={s}", .{ url, endpoint, encoded }) catch continue;
				defer self.allocator.free(target);

				const parsed = self.http.getJson(self.allocator, target, auth, &.{}) catch continue;
				defer parsed.deinit();

				for (json.listAt(parsed.value, "data")) |entry| {
					const id = json.textAt(entry, "sessionID");
					if (id.len == 0) continue;
					if (seen.contains(id)) continue;

					seen.put(self.allocator, id, {}) catch continue;
					const copy = self.allocator.dupe(u8, id) catch continue;
					next.append(self.allocator, copy) catch continue;
				}
			}
		}

		self.mutex.lockUncancelable(self.io);
		for (self.asking.items) |old| self.allocator.free(old);
		self.asking.deinit(self.allocator);
		self.asking = next;
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn questionDirs(self: *Opencode) [][]u8 {
		var out: std.ArrayListUnmanaged([]u8) = .empty;
		errdefer out.deinit(self.allocator);

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		var it = self.sessions.iterator();
		while (it.next()) |entry| {
			const session = entry.value_ptr.*;
			if (session.directory.len == 0) continue;

			var present = false;
			for (out.items) |dir| {
				if (std.mem.eql(u8, dir, session.directory)) {
					present = true;
					break;
				}
			}

			if (present) continue;

			out.append(self.allocator, self.allocator.dupe(u8, session.directory) catch continue) catch continue;
		}

		return out.toOwnedSlice(self.allocator) catch &.{};
	}

	pub fn refreshPlan(self: *Opencode) void {
		self.refreshUsage();
	}

	pub fn planOut(self: *Opencode, arena: Allocator) limitmod.Plan {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		return limitmod.copy(arena, self.plan_title, self.usage_error, self.limits.items) catch .{};
	}

	fn refreshUsage(self: *Opencode) void {
		const url = self.baseUrl(self.allocator) orelse {
			self.setUsageError("OpenCode offline");
			return;
		};
		defer self.allocator.free(url);

		const auth = self.authHeader() orelse return;
		defer self.allocator.free(auth);

		const target = std.fmt.allocPrint(self.allocator, "{s}/api/credential", .{url}) catch return;
		defer self.allocator.free(target);

		const parsed = self.http.getJson(self.allocator, target, auth, &.{}) catch {
			self.setUsageError("credential unreadable");
			return;
		};
		defer parsed.deinit();

		var token: []const u8 = "";

		for (json.listAt(parsed.value, "data")) |entry| {
			if (!json.flag(entry, "active")) continue;
			const value = json.deep(entry, &.{ "value", "access" }) orelse continue;
			token = json.text(value);
		}

		if (token.len == 0) {
			self.setUsageError("not signed in");
			return;
		}

		self.mutex.lockUncancelable(self.io);
		setStr(self.allocator, &self.access_token, token) catch {};
		self.mutex.unlock(self.io);

		const bearer = http.bearer(self.allocator, token) catch return;
		defer self.allocator.free(bearer);

		const parsed_usage = self.http.getJson(self.allocator, "https://opencode.ai/zen/go/v1/usage", bearer, &.{}) catch {
			self.setUsageError("plan unreachable");
			return;
		};
		defer parsed_usage.deinit();

		const windows = [_]struct { key: []const u8, title: []const u8 }{
			.{ .key = "rolling", .title = "Session" },
			.{ .key = "weekly", .title = "Weekly" },
			.{ .key = "monthly", .title = "Monthly" },
		};

		var next: std.ArrayListUnmanaged(Limit) = .empty;
		const usage = json.field(parsed_usage.value, "usage") orelse json.Value{ .null = {} };

		for (windows) |window| {
			const entry = json.field(usage, window.key) orelse continue;

			next.append(self.allocator, .{
				.title = self.allocator.dupe(u8, window.title) catch continue,
				.percent = json.numberAt(entry, "percent"),
				.resets_at = self.allocator.dupe(u8, json.textAt(entry, "resetsAt")) catch continue,
			}) catch continue;
		}

		self.mutex.lockUncancelable(self.io);
		for (self.limits.items) |old| {
			self.allocator.free(old.title);
			self.allocator.free(old.resets_at);
		}
		self.limits.deinit(self.allocator);
		self.limits = next;
		setStr(self.allocator, &self.usage_error, if (next.items.len == 0) "no plan" else "") catch {};
		self.mutex.unlock(self.io);

		self.hub.publish();
	}

	fn setUsageError(self: *Opencode, message: []const u8) void {
		self.mutex.lockUncancelable(self.io);
		setStr(self.allocator, &self.usage_error, message) catch {};
		self.mutex.unlock(self.io);
	}

	fn aggregateLocked(self: *Opencode) []const u8 {
		if (self.asking.items.len > 0) return "blocked";

		var working = false;
		var failure = false;

		var it = self.sessions.iterator();
		while (it.next()) |entry| {
			const session = entry.value_ptr.*;

			if (session.blocked.len > 0) return "blocked";
			if (session.failure.len > 0) failure = true;
			if (isBusy(session.status)) working = true;
		}

		if (failure) return "error";

		if (self.running.items.len > 0) working = true;

		return if (working) "working" else "idle";
	}

	fn detailLocked(self: *Opencode) []const u8 {
		var it = self.sessions.iterator();
		while (it.next()) |entry| {
			const session = entry.value_ptr.*;
			if (session.blocked.len > 0) return session.blocked;
			if (session.failure.len > 0) return session.failure;
		}

		return "";
	}

	pub fn faceState(self: *Opencode) []const u8 {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		return self.aggregateLocked();
	}

	pub fn detail(self: *Opencode) []const u8 {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		return self.detailLocked();
	}

	pub fn render(self: *Opencode, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);
		const arena = self.scratch.allocator();

		var sessions: std.ArrayListUnmanaged(SessionOut) = .empty;
		var it = self.sessions.iterator();
		while (it.next()) |entry| {
			const session = entry.value_ptr.*;
			try sessions.append(arena, .{
				.id = session.id,
				.title = session.title,
				.provider = session.provider,
				.parent = session.parent,
				.directory = session.directory,
				.status = session.status,
				.blocked = session.blocked,
				.failure = session.failure,
				.updated = session.updated,
			});
		}

		var done: std.ArrayListUnmanaged(DoneOut) = .empty;
		for (self.done.items) |entry| {
			try done.append(arena, .{ .id = entry.id, .title = entry.title, .at = entry.at });
		}

		var limits: std.ArrayListUnmanaged(LimitOut) = .empty;
		for (self.limits.items) |entry| {
			try limits.append(arena, .{ .title = entry.title, .percent = entry.percent, .resetsAt = entry.resets_at });
		}

		const out = Out{
			.connected = self.url.len > 0,
			.state = self.aggregateLocked(),
			.detail = self.detailLocked(),
			.failure = "",
			.usageError = self.usage_error,
			.sessions = sessions.items,
			.running = @ptrCast(self.running.items),
			.asking = @ptrCast(self.asking.items),
			.done = done.items,
			.plan = if (limits.items.len == 0) null else PlanOut{ .title = self.plan_title, .limits = limits.items },
		};

		try writer.print("{f}", .{std.json.fmt(out, .{})});
	}
};

fn isBusy(status: []const u8) bool {
	return std.mem.eql(u8, status, "busy") or std.mem.eql(u8, status, "retry");
}

fn inList(items: []const []u8, id: []const u8) bool {
	for (items) |item| {
		if (std.mem.eql(u8, item, id)) return true;
	}

	return false;
}

fn permissionText(data: json.Value) []const u8 {
	const message = json.textAt(data, "message");
	if (message.len > 0) return message;

	const action = json.textAt(data, "action");
	if (action.len > 0) return action;

	return "permission needed";
}

pub fn setStr(allocator: Allocator, slot: *[]u8, value: []const u8) !void {
	const copy = try allocator.dupe(u8, value);
	allocator.free(slot.*);
	slot.* = copy;
}

test "setStr replaces and frees" {
	var slot: []u8 = try std.testing.allocator.dupe(u8, "old");
	defer std.testing.allocator.free(slot);

	try setStr(std.testing.allocator, &slot, "new");
	try std.testing.expectEqualStrings("new", slot);
}

test "a running session wins over a stale status" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();
	const io = std.testing.io;

	var hub: hubmod.Hub = .{ .allocator = allocator, .io = io };
	var client = http.Client.init(allocator, io);
	const self = try Opencode.create(allocator, io, &hub, &client);

	try self.running.append(allocator, try allocator.dupe(u8, "ses_a"));
	const session = try self.sessionFor("ses_a");
	try setStr(allocator, &session.status, "idle");

	try std.testing.expectEqualStrings("working", self.faceState());
}

test "the active list clears a stale busy status" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();
	const io = std.testing.io;

	var hub: hubmod.Hub = .{ .allocator = allocator, .io = io };
	var client = http.Client.init(allocator, io);
	const self = try Opencode.create(allocator, io, &hub, &client);

	const stale = try self.sessionFor("ses_stale");
	try setStr(allocator, &stale.status, "busy");
	const live = try self.sessionFor("ses_live");
	try setStr(allocator, &live.status, "busy");

	const running = [_][]u8{@constCast("ses_live")};
	try std.testing.expect(self.clearStaleBusyLocked(&running));
	try std.testing.expectEqualStrings("idle", stale.status);
	try std.testing.expectEqualStrings("busy", live.status);
	try std.testing.expectEqualStrings("working", self.faceState());
}
