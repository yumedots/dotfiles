const std = @import("std");
const linux = std.os.linux;
const hubmod = @import("../../hub.zig");
const json = @import("../../primitives/json.zig");
const proc = @import("../../primitives/proc.zig");
const sock = @import("../../primitives/sock.zig");
const fmt = @import("../../primitives/fmt.zig");
const exec = @import("../../primitives/exec.zig");
const guardmod = @import("guard.zig");
const scanner = @import("scanner.zig");
const cache = @import("cache.zig");
const packages = @import("packages.zig");
const caches = @import("caches.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const Status = enum { idle, scanning, ready, failed };

pub const Disk = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	state: Status = .idle,
	error_text: []u8 = &.{},
	cache_path: []u8 = &.{},
	marks_path: []u8 = &.{},
	cache: ?cache.Cache = null,
	root: []u8 = &.{},
	focus: []u8 = &.{},
	marks: std.ArrayList([]u8) = .empty,
	scanning_root: []u8 = &.{},
	live_path: []u8 = &.{},
	live_at: i64 = 0,
	live_entries: std.ArrayList(LiveEntry) = .empty,
	watching: bool = false,

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Disk {
		const self = try allocator.create(Disk);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.scratch = std.heap.ArenaAllocator.init(allocator),
		};

		const cache_env = proc.env(io, allocator, "XDG_CACHE_HOME");
		const cache_home = cache_env orelse
			try std.fmt.allocPrint(allocator, "{s}/.cache", .{proc.home(io, allocator)});
		defer if (cache_env == null) allocator.free(cache_home);

		self.cache_path = try cache.cachePath(io, allocator, cache_home);
		self.marks_path = try std.fmt.allocPrint(allocator, "{s}/yudae/marks", .{cache_home});
		self.root = try allocator.dupe(u8, "/");
		self.focus = try allocator.dupe(u8, "/");

		self.loadMarks();
		self.loadCache();

		return self;
	}

	pub fn provider(self: *Disk) hubmod.Provider {
		return .{ .key = "disk", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Disk = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	fn loadCache(self: *Disk) void {
		if (self.cache) |*old| old.deinit();
		self.cache = cache.load(self.io, self.allocator, self.cache_path) catch null;

		if (self.cache) |*loaded| {
			self.state = .ready;
			const root = loaded.root();
			if (self.root.len > 0) self.allocator.free(self.root);
			self.root = self.allocator.dupe(u8, root) catch &.{};
			if (self.focus.len > 0) self.allocator.free(self.focus);
			self.focus = self.allocator.dupe(u8, root) catch &.{};
		}
	}

	fn loadMarks(self: *Disk) void {
		const body = proc.readFile(self.io, self.allocator, self.marks_path) catch return;
		defer self.allocator.free(body);

		var lines = std.mem.splitScalar(u8, body, '\n');
		while (lines.next()) |line| {
			const path = std.mem.trim(u8, line, " \t\r");
			if (path.len == 0) continue;
			const kept = self.allocator.dupe(u8, path) catch continue;
			self.marks.append(self.allocator, kept) catch {
				self.allocator.free(kept);
			};
		}
	}

	fn saveMarks(self: *Disk) void {
		var out: std.Io.Writer.Allocating = .init(self.allocator);
		defer out.deinit();

		for (self.marks.items) |saved| {
			out.writer.writeAll(saved) catch continue;
			out.writer.writeAll("\n") catch continue;
		}

		proc.writeFileAtomic(self.io, self.allocator, self.marks_path, out.written()) catch {};
	}

	pub fn call(self: *Disk, method: []const u8, args: json.Value, alloc: Allocator) anyerror![]u8 {
		if (std.mem.eql(u8, method, "scan")) return self.scan(args, alloc);
		if (std.mem.eql(u8, method, "view")) return self.setView(args, alloc);
		if (std.mem.eql(u8, method, "search")) return self.search(args, alloc);
		if (std.mem.eql(u8, method, "stat")) return self.stat(args, alloc);
		if (std.mem.eql(u8, method, "mark")) return self.mark(args, alloc, true);
		if (std.mem.eql(u8, method, "unmark")) return self.mark(args, alloc, false);
		if (std.mem.eql(u8, method, "trash")) return self.trash(args, alloc);
		if (std.mem.eql(u8, method, "delete") or std.mem.eql(u8, method, "remove")) return self.delete(args, alloc);
		if (std.mem.eql(u8, method, "move")) return self.move(args, alloc, false);
		if (std.mem.eql(u8, method, "rename")) return self.move(args, alloc, true);
		if (std.mem.eql(u8, method, "copy")) return self.copy(args, alloc);
		if (std.mem.eql(u8, method, "packages")) return self.listPackages(args, alloc);
		if (std.mem.eql(u8, method, "uninstall")) return self.uninstall(args, alloc);
		if (std.mem.eql(u8, method, "clean-packages")) return packages.clean(self.io, alloc, args, helperAvailable(self.io));
		if (std.mem.eql(u8, method, "caches")) return self.listCaches(args, alloc);
		if (std.mem.eql(u8, method, "clean")) return self.clean(args, alloc);
		if (std.mem.eql(u8, method, "watch")) return self.startWatch(args, alloc);
		if (std.mem.eql(u8, method, "app")) return self.openApp(alloc);
		return error.UnknownMethod;
	}

	fn scan(self: *Disk, args: json.Value, alloc: Allocator) ![]u8 {
		const requested = json.textAt(args, "path");
		const root = if (requested.len > 0) requested else "/";

		self.mutex.lockUncancelable(self.io);

		if (self.state == .scanning) {
			self.mutex.unlock(self.io);
			return error.ScanRunning;
		}

		if (!helperAvailable(self.io)) {
			self.state = .failed;
			self.setError("root required: yudae-fsd is not installed");
			self.mutex.unlock(self.io);
			self.hub.publish();
			return error.RootRequired;
		}

		if (self.scanning_root.len > 0) self.allocator.free(self.scanning_root);
		self.scanning_root = try self.allocator.dupe(u8, root);
		self.state = .scanning;
		self.setError("");

		const thread = std.Thread.spawn(.{}, scanThread, .{ self, self.scanning_root }) catch |err| {
			self.state = .failed;
			self.setError(@errorName(err));
			self.mutex.unlock(self.io);
			return error.SpawnFailed;
		};
		thread.detach();
		self.mutex.unlock(self.io);
		self.hub.publish();

		return std.fmt.allocPrint(alloc, "{{\"ok\":true,\"root\":{f},\"status\":\"scanning\"}}", .{std.json.fmt(root, .{})});
	}

	fn scanThread(self: *Disk, root: []const u8) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();
		const allocator = arena.allocator();

		var failure: ?[]const u8 = null;
		var finished: ?cache.Cache = null;

		finished = self.scanViaHelper(allocator, root) catch |err| blk: {
			failure = errorText(err);
			break :blk null;
		};

		self.mutex.lockUncancelable(self.io);

		if (finished) |loaded| {
			self.clearLive();
			if (self.cache) |*old| old.deinit();
			self.cache = loaded;
			self.state = .ready;
			self.setError("");

			if (self.root.len > 0) self.allocator.free(self.root);
			self.root = self.allocator.dupe(u8, root) catch &.{};
			if (self.focus.len > 0) self.allocator.free(self.focus);
			self.focus = self.allocator.dupe(u8, root) catch &.{};
		} else {
			self.state = .failed;
			self.setError(failure orelse "scan failed");
		}

		if (self.scanning_root.len > 0) {
			self.allocator.free(self.scanning_root);
			self.scanning_root = &.{};
		}
		self.mutex.unlock(self.io);
		self.hub.publish();
	}

	fn scanViaHelper(self: *Disk, allocator: Allocator, root: []const u8) !cache.Cache {
		const socket_path = helperPath();
		const request = try std.fmt.allocPrint(allocator, "{{\"action\":\"scan\",\"root\":{f}}}", .{std.json.fmt(root, .{})});
		defer allocator.free(request);

		var buffer: [1024 * 1024]u8 = undefined;
		var connection = try sock.Connection.connect(socket_path, &buffer);
		defer connection.close();

		try connection.writeLine(request);
		const line = try connection.readLine() orelse return error.NoReply;
		const parsed = try json.parse(allocator, line);
		if (!json.flag(parsed.value, "ok")) return error.HelperDenied;

		const remote = json.textAt(parsed.value, "path");
		if (remote.len == 0) return error.NoReply;
		defer deleteAbsolute(allocator, remote);

		var helper_file = try std.Io.Dir.cwd().openFile(self.io, remote, .{});
		defer helper_file.close(self.io);

		const helper_stat = try helper_file.stat(self.io);
		const body = try allocator.alloc(u8, @intCast(helper_stat.size));
		_ = try helper_file.readPositionalAll(self.io, body, 0);

		var temp_buffer: [4096]u8 = undefined;
		const temp = try std.fmt.bufPrint(&temp_buffer, "{s}.tmp.{d}", .{ self.cache_path, linux.getpid() });

		if (std.fs.path.dirname(self.cache_path)) |dir| try std.Io.Dir.cwd().createDirPath(self.io, dir);
		var temp_file = try std.Io.Dir.cwd().createFile(self.io, temp, .{ .truncate = true, .permissions = @enumFromInt(0o600) });
		temp_file.writeStreamingAll(self.io, body) catch {
			temp_file.close(self.io);
			return error.WriteFailed;
		};
		temp_file.close(self.io);
		try std.Io.Dir.cwd().rename(temp, std.Io.Dir.cwd(), self.cache_path, self.io);

		return cache.load(self.io, allocator, self.cache_path);
	}

	fn setError(self: *Disk, text: []const u8) void {
		if (self.error_text.len > 0) self.allocator.free(self.error_text);
		self.error_text = self.allocator.dupe(u8, text) catch &.{};
	}

	fn setView(self: *Disk, args: json.Value, alloc: Allocator) ![]u8 {
		const path = json.textAt(args, "path");

		self.mutex.lockUncancelable(self.io);
		errdefer self.mutex.unlock(self.io);

		if (self.cache == null) return error.NoCache;
		const target = if (path.len > 0) path else self.cache.?.root();
		if (self.cache.?.find(target) == null) return error.NoPath;

		if (self.focus.len > 0) self.allocator.free(self.focus);
		self.focus = try self.allocator.dupe(u8, target);
		self.mutex.unlock(self.io);
		self.hub.publish();

		return std.fmt.allocPrint(alloc, "{{\"ok\":true,\"path\":{f}}}", .{std.json.fmt(target, .{})});
	}

	fn search(self: *Disk, args: json.Value, alloc: Allocator) ![]u8 {
		const query = json.textAt(args, "query");
		if (query.len == 0) return alloc.dupe(u8, "{\"ok\":true,\"results\":[]}");

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);
		const loaded = self.cache orelse return error.NoCache;

		var matches: std.ArrayList(usize) = .empty;
		defer matches.deinit(alloc);

		for (loaded.nodes, 0..) |_, index| {
			const name = loaded.nameOf(@intCast(index));
			if (index == 0) continue;
			if (!containsIgnoreCase(name, query)) continue;
			if (matches.items.len >= 200) break;
			try matches.append(alloc, index);
		}

		std.mem.sort(usize, matches.items, loaded, bySize);

		var out: std.Io.Writer.Allocating = .init(alloc);
		try out.writer.writeAll("{\"ok\":true,\"results\":[");
		for (matches.items, 0..) |index, position| {
			if (position > 0) try out.writer.writeAll(",");
			const node = loaded.nodes[index];
			const path = try self.pathOf(alloc, loaded, @intCast(index));
			try out.writer.writeAll("{\"name\":");
			try json.encodeText(&out.writer, loaded.nameOf(@intCast(index)));
			try out.writer.writeAll(",\"path\":");
			try json.encodeText(&out.writer, path);
			try out.writer.print(",\"size\":{d},\"kind\":\"{s}\"}}", .{ node.size, kindName(node.kind) });
		}
		try out.writer.writeAll("]}");
		return out.written();
	}

	fn stat(self: *Disk, args: json.Value, alloc: Allocator) ![]u8 {
		const path = json.textAt(args, "path");
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);
		const loaded = self.cache orelse return error.NoCache;

		const index = loaded.find(path) orelse return error.NoPath;
		const node = loaded.nodes[index];
		const full = try self.pathOf(alloc, loaded, index);

		var out: std.Io.Writer.Allocating = .init(alloc);
		try out.writer.print("{{\"ok\":true,\"path\":{f},\"size\":{d},\"kind\":\"{s}\",\"mtime\":{d},\"children\":{d}}}", .{
			std.json.fmt(full, .{}),
			node.size,
			kindName(node.kind),
			node.mtime,
			childCount(loaded, index),
		});
		return out.written();
	}

	fn mark(self: *Disk, args: json.Value, alloc: Allocator, add: bool) ![]u8 {
		const path = json.textAt(args, "path");
		if (path.len == 0) return error.NoPath;

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		var index: usize = 0;
		while (index < self.marks.items.len) : (index += 1) {
			if (!std.mem.eql(u8, self.marks.items[index], path)) continue;
			if (!add) self.allocator.free(self.marks.swapRemove(index));
			self.saveMarks();
			return alloc.dupe(u8, "{\"ok\":true}");
		}

		if (add) {
			try self.marks.append(self.allocator, try self.allocator.dupe(u8, path));
			self.saveMarks();
		}

		return alloc.dupe(u8, "{\"ok\":true}");
	}

	fn trash(self: *Disk, args: json.Value, alloc: Allocator) ![]u8 {
		const path = json.textAt(args, "path");
		if (path.len == 0) return error.NoPath;

		const home = proc.home(self.io, self.allocator);
		const trash_dir = try std.fmt.allocPrint(alloc, "{s}/.local/share/Trash", .{home});
		const files = try std.fmt.allocPrint(alloc, "{s}/files", .{trash_dir});
		const info = try std.fmt.allocPrint(alloc, "{s}/info", .{trash_dir});

		try std.Io.Dir.cwd().createDirPath(self.io, files);
		try std.Io.Dir.cwd().createDirPath(self.io, info);

		const base = std.fs.path.basename(path);
		var stamp: usize = 0;
		var destination: []const u8 = undefined;
		var info_path: []const u8 = undefined;

		while (stamp < 1000) : (stamp += 1) {
			const name = if (stamp == 0) base else try std.fmt.allocPrint(alloc, "{s}.{d}", .{ base, stamp });
			destination = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ files, name });
			info_path = try std.fmt.allocPrint(alloc, "{s}/{s}.trashinfo", .{ info, name });
			if (!proc.exists(self.io, destination)) break;
		}

		try std.Io.Dir.cwd().rename(path, std.Io.Dir.cwd(), destination, self.io);

		var out: std.Io.Writer.Allocating = .init(alloc);
		try out.writer.print("[Trash Info]\nPath={s}\nDeletionDate={d}\n", .{ path, @divTrunc(fmt.nowMs(self.io), 1000) });
		try proc.writeFileAtomic(self.io, alloc, info_path, out.written());

		return std.fmt.allocPrint(alloc, "{{\"ok\":true,\"path\":{f}}}", .{std.json.fmt(destination, .{})});
	}

	fn delete(self: *Disk, args: json.Value, alloc: Allocator) ![]u8 {
		const path = json.textAt(args, "path");
		if (path.len == 0) return error.NoPath;

		var guard = try guardmod.Guard.init(self.allocator, self.io, &.{});
		defer guard.deinit(self.allocator);

		const root = if (self.root.len > 0) self.root else "/";
		guardmod.removeTree(path, &guard, root) catch |err| switch (err) {
			error.Denied, error.RemoveFailed => {
				if (!helperAvailable(self.io)) return error.Denied;
				try self.helperRemove(alloc, path, root);
			},
			else => return err,
		};

		return std.fmt.allocPrint(alloc, "{{\"ok\":true,\"path\":{f}}}", .{std.json.fmt(path, .{})});
	}

	fn helperRemove(self: *Disk, alloc: Allocator, path: []const u8, root: []const u8) !void {
	_ = self;
		var out: std.Io.Writer.Allocating = .init(alloc);
		try out.writer.writeAll("{\"action\":\"remove\",\"path\":");
		try json.encodeText(&out.writer, path);
		try out.writer.writeAll(",\"root\":");
		try json.encodeText(&out.writer, root);
		try out.writer.writeAll("}");

		var buffer: [1024 * 1024]u8 = undefined;
		var connection = try sock.Connection.connect(helperPath(), &buffer);
		defer connection.close();

		try connection.writeLine(out.written());
		const line = try connection.readLine() orelse return error.NoReply;
		const parsed = try json.parse(alloc, line);
		if (!json.flag(parsed.value, "ok")) return error.HelperDenied;
	}

	fn helperMove(self: *Disk, alloc: Allocator, from: []const u8, to: []const u8) !void {
		_ = self;
		var out: std.Io.Writer.Allocating = .init(alloc);
		try out.writer.writeAll("{\"action\":\"move\",\"from\":");
		try json.encodeText(&out.writer, from);
		try out.writer.writeAll(",\"to\":");
		try json.encodeText(&out.writer, to);
		try out.writer.writeAll("}");

		var buffer: [1024 * 1024]u8 = undefined;
		var connection = try sock.Connection.connect(helperPath(), &buffer);
		defer connection.close();
		try connection.writeLine(out.written());
		const line = try connection.readLine() orelse return error.NoReply;
		const parsed = try json.parse(alloc, line);
		if (!json.flag(parsed.value, "ok")) return error.HelperDenied;
	}

	fn move(self: *Disk, args: json.Value, alloc: Allocator, rename: bool) ![]u8 {
		const from = json.textAt(args, "from");
		const to = json.textAt(args, "to");
		if (from.len == 0 or to.len == 0) return error.NoPath;
		_ = rename;

		std.Io.Dir.cwd().rename(from, std.Io.Dir.cwd(), to, self.io) catch |err| {
			if (!helperAvailable(self.io)) return err;
			try self.helperMove(alloc, from, to);
		};
		return std.fmt.allocPrint(alloc, "{{\"ok\":true,\"from\":{f},\"to\":{f}}}", .{ std.json.fmt(from, .{}), std.json.fmt(to, .{}) });
	}

	fn copy(self: *Disk, args: json.Value, alloc: Allocator) ![]u8 {
		const from = json.textAt(args, "from");
		const to = json.textAt(args, "to");
		if (from.len == 0 or to.len == 0) return error.NoPath;

		try copyPath(self.io, self.allocator, from, to);
		return std.fmt.allocPrint(alloc, "{{\"ok\":true,\"from\":{f},\"to\":{f}}}", .{ std.json.fmt(from, .{}), std.json.fmt(to, .{}) });
	}

	fn listPackages(self: *Disk, args: json.Value, alloc: Allocator) ![]u8 {
		_ = args;
		return packages.render(self.io, alloc);
	}

	fn uninstall(self: *Disk, args: json.Value, alloc: Allocator) ![]u8 {
		return packages.uninstall(self.io, alloc, args, helperAvailable(self.io));
	}

	fn listCaches(self: *Disk, args: json.Value, alloc: Allocator) ![]u8 {
		_ = args;
		return caches.render(self.io, alloc);
	}

	fn clean(self: *Disk, args: json.Value, alloc: Allocator) ![]u8 {
		return caches.clean(self.io, alloc, args, helperAvailable(self.io));
	}

	fn startWatch(self: *Disk, args: json.Value, alloc: Allocator) ![]u8 {
		if (!helperAvailable(self.io)) return error.HelperUnavailable;

		const path = if (json.textAt(args, "path").len > 0) json.textAt(args, "path") else self.focus;
		const seconds: i64 = @min(@max(json.integer(json.field(args, "seconds")), 1), 60);

		self.mutex.lockUncancelable(self.io);
		if (self.watching) {
			self.mutex.unlock(self.io);
			return error.WatchRunning;
		}
		self.watching = true;
		self.clearLive();
		if (self.live_path.len > 0) self.allocator.free(self.live_path);
		self.live_path = try self.allocator.dupe(u8, path);
		self.mutex.unlock(self.io);

		const thread = std.Thread.spawn(.{}, watchThread, .{ self, self.live_path, seconds }) catch {
			self.mutex.lockUncancelable(self.io);
			self.watching = false;
			self.mutex.unlock(self.io);
			return error.SpawnFailed;
		};
		thread.detach();

		return std.fmt.allocPrint(alloc, "{{\"ok\":true,\"path\":{f},\"seconds\":{d}}}", .{ std.json.fmt(path, .{}), seconds });
	}

	fn watchThread(self: *Disk, path: []const u8, seconds: i64) void {
		defer {
			self.mutex.lockUncancelable(self.io);
			self.watching = false;
			self.mutex.unlock(self.io);
			self.hub.publish();
		}

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();
		const allocator = arena.allocator();

		var request: std.Io.Writer.Allocating = .init(allocator);
		request.writer.writeAll("{\"action\":\"watch\",\"path\":") catch return;
		json.encodeText(&request.writer, path) catch return;
		request.writer.print(",\"seconds\":{d}}}", .{seconds}) catch return;

		var buffer: [1024 * 1024]u8 = undefined;
		var connection = sock.Connection.connect(helperPath(), &buffer) catch return;
		defer connection.close();
		connection.writeLine(request.written()) catch return;

		const maybe_line = connection.readLine() catch return;
		const line = maybe_line orelse return;
		const parsed = json.parse(allocator, line) catch return;
		if (!json.flag(parsed.value, "ok")) return;

		self.mutex.lockUncancelable(self.io);
		self.clearLive();
		self.live_at = fmt.nowMs(self.io);
		for (json.listAt(parsed.value, "names")) |item| {
			const name = json.text(item);
			if (name.len == 0 or name.len > 255) continue;
			const entry = liveEntry(self.io, self.allocator, path, name) catch continue;
			self.live_entries.append(self.allocator, entry) catch {};
		}
		self.mutex.unlock(self.io);
	}

	fn clearLive(self: *Disk) void {
		for (self.live_entries.items) |entry| self.allocator.free(entry.name);
		self.live_entries.clearRetainingCapacity();
		self.live_at = 0;
	}

	fn openApp(self: *Disk, alloc: Allocator) ![]u8 {
		const repo = proc.repo(self.io, self.allocator);
		const script = try std.fmt.allocPrint(alloc, "{s}/scripts/yudae", .{repo});
		_ = exec.spawn(self.io, .{
			.argv = &.{ "setsid", script, "app", "open", "disk" },
			.stdin = .ignore,
			.stdout = .ignore,
			.stderr = .ignore,
		}) catch return error.SpawnFailed;

		return alloc.dupe(u8, "{\"ok\":true}");
	}

	fn pathOf(self: *Disk, alloc: Allocator, loaded: cache.Cache, index: u32) ![]const u8 {
		_ = self;
		if (index == 0) return alloc.dupe(u8, loaded.root());

		var names: std.ArrayList([]const u8) = .empty;
		defer names.deinit(alloc);

		var current = index;
		while (current != 0) {
			const node = loaded.nodes[current];
			try names.append(alloc, loaded.nameOf(current));
			current = node.parent;
			if (current == scanner.none) break;
		}

		var out: std.Io.Writer.Allocating = .init(alloc);
		const root = loaded.root();
		if (root.len > 0 and root[root.len - 1] == '/') {
			try out.writer.writeAll(root[0 .. root.len - 1]);
		} else {
			try out.writer.writeAll(root);
		}

		var position = names.items.len;
		while (position > 0) {
			position -= 1;
			try out.writer.writeAll("/");
			try out.writer.writeAll(names.items[position]);
		}

		return out.written();
	}

	fn render(self: *Disk, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		_ = self.scratch.reset(.retain_capacity);
		const allocator = self.scratch.allocator();

		const loaded: ?cache.Cache = if (self.cache) |*value| value.* else null;
		const root = if (loaded) |value| value.root() else self.root;
		const focus_path = if (self.focus.len > 0) self.focus else root;
		const usage = diskUsage(root);

		try writer.print("{{\"status\":\"{s}\",\"error\":{f},\"root\":{f},\"focus\":{f},\"cache\":{f}", .{
			@tagName(self.state),
			std.json.fmt(self.error_text, .{}),
			std.json.fmt(root, .{}),
			std.json.fmt(focus_path, .{}),
			std.json.fmt(self.cache_path, .{}),
		});

		try writer.print(",\"total\":{d},\"deviceTotal\":{d},\"used\":{d},\"free\":{d},\"scanned\":{d}", .{
			if (loaded) |value| value.total else 0,
			usage.total,
			usage.used,
			usage.free,
			if (loaded) |value| value.scanned_ms else 0,
		});

		try writer.writeAll(",\"marks\":[");
		for (self.marks.items, 0..) |saved, index| {
			if (index > 0) try writer.writeAll(",");
			try json.encodeText(writer, saved);
		}
		try writer.writeAll("],\"live\":{\"path\":");
		try json.encodeText(writer, self.live_path);
		try writer.print(",\"at\":{d},\"entries\":[", .{self.live_at});
		for (self.live_entries.items, 0..) |entry, index| {
			if (index > 0) try writer.writeAll(",");
			try writer.writeAll("{\"name\":");
			try json.encodeText(writer, entry.name);
			try writer.print(",\"size\":{d},\"kind\":\"{s}\",\"sizeText\":", .{ entry.size, kindName(entry.kind) });
			const text = try humanSize(allocator, entry.size);
			try json.encodeText(writer, text);
			try writer.writeAll("}");
		}
		try writer.writeAll("]},\"view\":");

		if (loaded) |value| {
			const index = value.find(focus_path) orelse 0;
			try renderView(writer, allocator, value, index, 1, 24);
		} else {
			try writer.writeAll("null");
		}

		try writer.writeAll("}");
	}
};

const LiveEntry = struct {
	name: []u8,
	size: u64,
	kind: scanner.Kind,
};

fn liveEntry(io: Io, allocator: Allocator, base: []const u8, name: []const u8) !LiveEntry {
	_ = io;
	const path = if (std.mem.eql(u8, base, "/"))
		try std.fmt.allocPrint(allocator, "/{s}", .{name})
	else
		try std.fmt.allocPrint(allocator, "{s}/{s}", .{ base, name });
	defer allocator.free(path);

	const z = try allocator.allocSentinel(u8, path.len, 0);
	@memcpy(z, path);
	defer allocator.free(z);

	var st: linux.Statx = undefined;
	const result = linux.statx(linux.AT.FDCWD, z.ptr, linux.AT.SYMLINK_NOFOLLOW, .{
		.TYPE = true,
		.MODE = true,
		.INO = true,
		.SIZE = true,
		.BLOCKS = true,
		.MTIME = true,
	}, &st);
	if (linux.errno(result) != .SUCCESS) return error.StatFailed;

	const kind: scanner.Kind = if (std.posix.S.ISDIR(st.mode)) .directory else if (std.posix.S.ISREG(st.mode)) .file else .other;
	return .{
		.name = try allocator.dupe(u8, name),
		.size = st.blocks * 512,
		.kind = kind,
	};
}

fn helperPath() []const u8 {
	return guardmod.fsdSocket();
}

fn deleteAbsolute(allocator: Allocator, path: []const u8) void {
	const z = allocator.allocSentinel(u8, path.len, 0) catch return;
	defer allocator.free(z);
	@memcpy(z, path);
	_ = linux.unlink(z.ptr);
}

fn errorText(err: anyerror) []const u8 {
	return switch (err) {
		error.AccessDenied, error.PermissionDenied, error.OpenFailed, error.Denied => "permission denied: scan a readable path or install yudae-fsd",
		error.HelperDenied => "polkit denied the scan or no agent is available",
		error.NoReply, error.ConnectFailed => "yudae-fsd did not answer",
		error.RootRequired => "root required: yudae-fsd is not installed",
		error.RingInit, error.SubmitFailed => "io_uring is not available for the scan",
		else => @errorName(err),
	};
}

fn helperAvailable(io: Io) bool {
	return proc.exists(io, helperPath());
}

const Usage = struct { used: u64 = 0, free: u64 = 0, total: u64 = 0 };

const StatFs = extern struct {
	kind: i64,
	bsize: i64,
	blocks: u64,
	bfree: u64,
	bavail: u64,
	files: u64,
	ffree: u64,
	fsid: [2]i32,
	namelen: i64,
	frsize: i64,
	flags: i64,
	spare: [4]i64,
};

fn diskUsage(path: []const u8) Usage {
	const allocator = std.heap.smp_allocator;
	const z = allocator.allocSentinel(u8, path.len, 0) catch return .{};
	defer allocator.free(z);
	@memcpy(z, path);

	var st: StatFs = undefined;
	const result = linux.syscall2(.statfs, @intFromPtr(z.ptr), @intFromPtr(&st));
	if (linux.errno(result) != .SUCCESS) return .{};

	const unit: u64 = if (st.frsize > 0) @intCast(st.frsize) else @intCast(st.bsize);
	return .{
		.total = st.blocks * unit,
		.free = st.bavail * unit,
		.used = (st.blocks - st.bfree) * unit,
	};
}

fn renderView(writer: *Writer, allocator: Allocator, loaded: cache.Cache, index: u32, depth: u32, top_n: u32) !void {
	const node = loaded.nodes[index];
	const path = try pathOfCache(allocator, loaded, index);

	if (depth == 0) {
		try writer.print("{{\"path\":{f},\"size\":{d},\"kind\":\"{s}\",\"children\":[]}}", .{
			std.json.fmt(path, .{}),
			node.size,
			kindName(node.kind),
		});
		return;
	}

	var children: std.ArrayList(Child) = .empty;
	defer children.deinit(allocator);

	var child = node.first_child;
	while (child != scanner.none) : (child = loaded.nodes[child].next_sibling) {
		try children.append(allocator, .{ .index = child, .size = loaded.nodes[child].size });
	}

	std.mem.sort(Child, children.items, {}, byChildSize);

	try writer.print("{{\"path\":{f},\"size\":{d},\"kind\":\"{s}\",\"children\":[", .{
		std.json.fmt(path, .{}),
		node.size,
		kindName(node.kind),
	});

	for (children.items[0..@min(top_n, children.items.len)], 0..) |entry, position| {
		if (position > 0) try writer.writeAll(",");
		const child_node = loaded.nodes[entry.index];
		const child_path = try pathOfCache(allocator, loaded, entry.index);
		const child_size = try humanSize(allocator, child_node.size);
		try writer.print("{{\"name\":{f},\"path\":{f},\"size\":{d},\"sizeText\":{f},\"kind\":\"{s}\",\"children\":{d}",
			.{ std.json.fmt(loaded.nameOf(entry.index), .{}), std.json.fmt(child_path, .{}), child_node.size, std.json.fmt(child_size, .{}), kindName(child_node.kind), childCount(loaded, entry.index) });

		if (depth > 1 and child_node.kind == .directory and child_node.first_child != scanner.none) {
			try writer.writeAll(",\"nested\":");
			try renderView(writer, allocator, loaded, entry.index, depth - 1, top_n);
		}

		try writer.writeAll("}");
	}

	try writer.writeAll("]}");
}

const Child = struct { index: u32, size: u64 };

fn byChildSize(_: void, a: Child, b: Child) bool {
	return a.size > b.size;
}

fn bySize(loaded: cache.Cache, a: usize, b: usize) bool {
	return loaded.nodes[a].size > loaded.nodes[b].size;
}

fn childCount(loaded: cache.Cache, index: u32) u32 {
	var count: u32 = 0;
	var child = loaded.nodes[index].first_child;
	while (child != scanner.none) : (child = loaded.nodes[child].next_sibling) count += 1;
	return count;
}

fn humanSize(allocator: Allocator, size: u64) ![]const u8 {
	if (size >= 1024 * 1024 * 1024 * 1024) return std.fmt.allocPrint(allocator, "{d:.1} TB", .{@as(f64, @floatFromInt(size)) / (1024.0 * 1024.0 * 1024.0 * 1024.0)});
	if (size >= 1024 * 1024 * 1024) return std.fmt.allocPrint(allocator, "{d:.1} GB", .{@as(f64, @floatFromInt(size)) / (1024.0 * 1024.0 * 1024.0)});
	if (size >= 1024 * 1024) return std.fmt.allocPrint(allocator, "{d:.1} MB", .{@as(f64, @floatFromInt(size)) / (1024.0 * 1024.0)});
	if (size >= 1024) return std.fmt.allocPrint(allocator, "{d:.1} kB", .{@as(f64, @floatFromInt(size)) / 1024.0});
	return std.fmt.allocPrint(allocator, "{d} B", .{size});
}

fn kindName(kind: scanner.Kind) []const u8 {
	return switch (kind) {
		.directory => "dir",
		.file => "file",
		.other => "other",
	};
}

fn pathOfCache(allocator: Allocator, loaded: cache.Cache, index: u32) ![]const u8 {
	if (index == 0) return allocator.dupe(u8, loaded.root());

	var names: std.ArrayList([]const u8) = .empty;
	defer names.deinit(allocator);

	var current = index;
	while (current != 0) {
		try names.append(allocator, loaded.nameOf(current));
		current = loaded.nodes[current].parent;
		if (current == scanner.none) break;
	}

	var out: std.Io.Writer.Allocating = .init(allocator);
	const root = loaded.root();
	if (root.len > 0 and root[root.len - 1] == '/') {
		try out.writer.writeAll(root[0 .. root.len - 1]);
	} else {
		try out.writer.writeAll(root);
	}

	var position = names.items.len;
	while (position > 0) {
		position -= 1;
		try out.writer.writeAll("/");
		try out.writer.writeAll(names.items[position]);
	}

	return out.written();
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
	if (needle.len == 0) return true;
	if (needle.len > haystack.len) return false;

	var index: usize = 0;
	while (index + needle.len <= haystack.len) : (index += 1) {
		if (std.ascii.eqlIgnoreCase(haystack[index .. index + needle.len], needle)) return true;
	}
	return false;
}

fn copyPath(io: Io, allocator: Allocator, from: []const u8, to: []const u8) !void {
	const stat = try std.Io.Dir.cwd().statFile(io, from, .{});
	if (stat.kind != .directory) {
		try std.Io.Dir.cwd().copyFile(from, std.Io.Dir.cwd(), to, io, .{});
		return;
	}

	try std.Io.Dir.cwd().createDirPath(io, to);
	var dir = try std.Io.Dir.cwd().openDir(io, from, .{ .iterate = true });
	defer dir.close(io);

	var it = dir.iterate();
	while (try it.next(io)) |entry| {
		const source = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ from, entry.name });
		defer allocator.free(source);
		const destination = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ to, entry.name });
		defer allocator.free(destination);

		try copyPath(io, allocator, source, destination);
	}
}
