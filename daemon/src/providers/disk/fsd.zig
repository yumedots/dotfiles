const std = @import("std");
const linux = std.os.linux;
const sock = @import("../../primitives/sock.zig");
const json = @import("../../primitives/json.zig");
const exec = @import("../../primitives/exec.zig");
const fmt = @import("../../primitives/fmt.zig");
const sleep = @import("../../primitives/sleep.zig");
const guardmod = @import("guard.zig");
const scanner = @import("scanner.zig");
const cache = @import("cache.zig");
const fanotify = @import("fanotify.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const scan_action = "org.yudae.fs.scan";
const remove_action = "org.yudae.fs.remove";
const bench_action = "org.yudae.fs.bench";
const packages_action = "org.yudae.packages.manage";

const Peer = extern struct {
	pid: i32,
	uid: u32,
	gid: u32,
};

extern fn yudae_polkit_check(pidfd: c_int, uid: c_int, gid: c_int, action: [*:0]const u8, detail: [*:0]const u8, error_out: [*]u8, error_len: c_ulong) c_int;

pub fn run(io: Io) !void {
	if (linux.geteuid() != 0) return error.RootRequired;
	const allocator = std.heap.smp_allocator;
	const socket_path = guardmod.fsdSocket();
	const socket_dir = std.fs.path.dirname(socket_path) orelse "/run/yudae";

	std.Io.Dir.cwd().createDirPath(io, socket_dir) catch {};
	if (std.mem.eql(u8, socket_dir, "/run/yudae")) {
		chmodPath(socket_dir, 0o755);
		cleanupScans(io, socket_dir);
	}

	var server: sock.Server = undefined;
	if (std.c.getenv("LISTEN_FDS") != null) {
		server = .{ .fd = 3, .path = socket_path };
	} else {
		server = try sock.Server.init(socket_path);
	}
	defer server.close();

	std.debug.print("yudae-fsd listening on {s}\n", .{socket_path});

	while (true) {
		const fd = server.accept() catch continue;

		const thread = std.Thread.spawn(.{}, serve, .{ io, allocator, fd, socket_dir }) catch {
			_ = linux.close(fd);
			continue;
		};
		thread.detach();
	}
}

fn serve(io: Io, allocator: Allocator, fd: i32, socket_dir: []const u8) void {
	defer _ = linux.close(fd);

	const buffer = allocator.alloc(u8, 1024 * 1024) catch return;
	defer allocator.free(buffer);

	var connection: sock.Connection = .{ .fd = fd, .buffer = buffer };
	const line = connection.readLine() catch return orelse return;

	const peer = peerOf(fd) orelse return;
	const pidfd = linux.pidfd_open(peer.pid, 0);
	if (linux.errno(pidfd) != .SUCCESS) {
		reply(io, fd, "{\"ok\":false,\"error\":\"pidfd\"}");
		return;
	}
	const pid_fd: i32 = @intCast(pidfd);
	defer _ = linux.close(pid_fd);

	var arena = std.heap.ArenaAllocator.init(allocator);
	defer arena.deinit();
	const inner = arena.allocator();

	const parsed = json.parse(inner, line) catch {
		reply(io, fd, "{\"ok\":false,\"error\":\"request\"}");
		return;
	};

	const action = json.textAt(parsed.value, "action");
	const result = dispatch(io, inner, fd, pid_fd, peer, action, parsed.value, socket_dir) catch |err| {
		var out: std.Io.Writer.Allocating = .init(inner);
		out.writer.writeAll("{\"ok\":false,\"error\":") catch return;
		json.encodeText(&out.writer, @errorName(err)) catch return;
		out.writer.writeAll("}") catch return;
		reply(io, fd, out.written());
		return;
	};

	reply(io, fd, result);
}

fn dispatch(
	io: Io,
	allocator: Allocator,
	fd: i32,
	pidfd: i32,
	peer: Peer,
	action: []const u8,
	request: json.Value,
	socket_dir: []const u8,
) ![]const u8 {
	_ = fd;

	if (std.mem.eql(u8, action, "scan")) return scan(io, allocator, pidfd, peer, request, socket_dir);
	if (std.mem.eql(u8, action, "remove")) return remove(io, allocator, pidfd, peer, request);
	if (std.mem.eql(u8, action, "move")) return move(io, allocator, pidfd, peer, request);
	if (std.mem.eql(u8, action, "bench")) return bench(io, allocator, pidfd, peer, request);
	if (std.mem.eql(u8, action, "packages")) return packages(io, allocator, pidfd, peer, request);
	if (std.mem.eql(u8, action, "cache")) return cleanCache(io, allocator, pidfd, peer, request);
	if (std.mem.eql(u8, action, "watch")) return watch(io, allocator, pidfd, peer, request);

	return error.UnknownAction;
}

fn scan(io: Io, allocator: Allocator, pidfd: i32, peer: Peer, request: json.Value, socket_dir: []const u8) ![]const u8 {
	try authorize(pidfd, peer.uid, peer.gid, scan_action, json.textAt(request, "root"));
	cleanupScans(io, socket_dir);

	const root = if (json.textAt(request, "root").len > 0) json.textAt(request, "root") else "/";
	var guard = try guardmod.Guard.init(allocator, io, &.{});
	defer guard.deinit(allocator);

	var scan_state = try scanner.Scan.init(allocator, &guard, scanner.fold_below);
	defer scan_state.deinit();
	scan_state.full_disk = true;
	try scan_state.runUringThreaded(root, 1);

	const stamp = fmt.nowMs(io);
	const path = try std.fmt.allocPrint(allocator, "{s}/scan-{d}-{d}.bin", .{ socket_dir, peer.pid, stamp });
	errdefer std.Io.Dir.cwd().deleteFile(io, path) catch {};

	try cache.write(io, allocator, path, &scan_state, stamp);

	const file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_write });
	defer file.close(io);
	_ = linux.fchown(file.handle, peer.uid, peer.gid);
	_ = linux.fchmod(file.handle, 0o600);

	var out: std.Io.Writer.Allocating = .init(allocator);
	try out.writer.writeAll("{\"ok\":true,\"path\":");
	try json.encodeText(&out.writer, path);
	try out.writer.print(",\"total\":{d},\"entries\":{d},\"directories\":{d},\"files\":{d},\"scanned\":{d}}}", .{
		scan_state.total(),
		scan_state.stats.entries,
		scan_state.stats.directories,
		scan_state.stats.files,
		stamp,
	});
	return out.written();
}

fn remove(io: Io, allocator: Allocator, pidfd: i32, peer: Peer, request: json.Value) ![]const u8 {
	_ = io;
	const path = json.textAt(request, "path");
	const root = if (json.textAt(request, "root").len > 0) json.textAt(request, "root") else "/";
	try authorize(pidfd, peer.uid, peer.gid, remove_action, path);

	var guard = try guardmod.Guard.init(allocator, std.Io.Threaded.global_single_threaded.io(), &.{});
	defer guard.deinit(allocator);

	try guardmod.removeTree(path, &guard, root);
	return allocator.dupe(u8, "{\"ok\":true}");
}

fn move(io: Io, allocator: Allocator, pidfd: i32, peer: Peer, request: json.Value) ![]const u8 {
	const from = json.textAt(request, "from");
	const to = json.textAt(request, "to");
	if (from.len == 0 or to.len == 0) return error.NoPath;
	try authorize(pidfd, peer.uid, peer.gid, remove_action, from);

	var from_buffer: [4096]u8 = undefined;
	var to_buffer: [4096]u8 = undefined;
	const source = try guardmod.clean(from, &from_buffer);
	const target = try guardmod.clean(to, &to_buffer);

	var guard = try guardmod.Guard.init(allocator, io, &.{});
	defer guard.deinit(allocator);
	if (guard.isRemoveProtected(source) or guard.isRemoveProtected(target)) return error.Protected;
	if (guard.isMount(source, "/")) return error.Protected;

	const source_parent = try guardmod.openRoot(std.fs.path.dirname(source) orelse "/");
	defer _ = linux.close(source_parent);
	const target_parent = try guardmod.openRoot(std.fs.path.dirname(target) orelse "/");
	defer _ = linux.close(target_parent);

	const source_name = try allocator.allocSentinel(u8, std.fs.path.basename(source).len, 0);
	@memcpy(source_name, std.fs.path.basename(source));
	defer allocator.free(source_name);
	const target_name = try allocator.allocSentinel(u8, std.fs.path.basename(target).len, 0);
	@memcpy(target_name, std.fs.path.basename(target));
	defer allocator.free(target_name);

	const result = linux.renameat(source_parent, source_name.ptr, target_parent, target_name.ptr);
	if (linux.errno(result) != .SUCCESS) return error.MoveFailed;
	return "{\"ok\":true}";
}

fn bench(io: Io, allocator: Allocator, pidfd: i32, peer: Peer, request: json.Value) ![]const u8 {
	_ = allocator;
	try authorize(pidfd, peer.uid, peer.gid, bench_action, json.textAt(request, "path"));

	var file = try std.Io.Dir.cwd().openFile(io, "/proc/sys/vm/drop_caches", .{ .mode = .write_only });
	defer file.close(io);
	try file.writeStreamingAll(io, "3\n");

	return "{\"ok\":true}";
}

fn packages(io: Io, allocator: Allocator, pidfd: i32, peer: Peer, request: json.Value) ![]const u8 {
	const flatpak_mode = json.flag(request, "flatpak");
	try authorize(pidfd, peer.uid, peer.gid, packages_action, if (flatpak_mode) "flatpak" else "pacman");

	const list = json.listAt(request, "names");
	if (list.len == 0) return error.Empty;

	var argv: std.ArrayList([]const u8) = .empty;
	if (flatpak_mode) {
		try argv.append(allocator, "flatpak");
		try argv.append(allocator, "uninstall");
		try argv.append(allocator, "--system");
		try argv.append(allocator, "--noninteractive");
		try argv.append(allocator, "--assume-yes");
		for (list) |item| {
			const name = json.text(item);
			if (!safePackage(name)) return error.BadName;
			try argv.append(allocator, name);
		}
	} else {
		try argv.append(allocator, "pacman");
		try argv.append(allocator, "-Rns");
		try argv.append(allocator, "--noconfirm");
		try argv.append(allocator, "--");

		for (list) |item| {
			const name = json.text(item);
			if (!safePackage(name)) return error.BadName;
			try argv.append(allocator, name);
		}
	}

	const result = try exec.run(io, allocator, argv.items);

	var out: std.Io.Writer.Allocating = .init(allocator);
	try out.writer.print("{{\"ok\":{s},\"code\":{d},\"out\":", .{ if (result.code == 0) "true" else "false", result.code });
	try json.encodeText(&out.writer, result.out);
	try out.writer.writeAll(",\"err\":");
	try json.encodeText(&out.writer, result.err);
	try out.writer.writeAll("}");
	return out.written();
}

fn cleanCache(io: Io, allocator: Allocator, pidfd: i32, peer: Peer, request: json.Value) ![]const u8 {
	const tool = json.textAt(request, "tool");
	try authorize(pidfd, peer.uid, peer.gid, packages_action, tool);

	var argv: std.ArrayList([]const u8) = .empty;
	if (std.mem.eql(u8, tool, "paccache")) {
		try argv.append(allocator, "paccache");
		try argv.append(allocator, "-rk0");
	} else if (std.mem.eql(u8, tool, "journal")) {
		try argv.append(allocator, "journalctl");
		try argv.append(allocator, "--vacuum-size=100M");
	} else if (std.mem.eql(u8, tool, "coredump")) {
		try emptyDir(io, allocator, "/var/lib/systemd/coredump");
		return allocator.dupe(u8, "{\"ok\":true}");
	} else {
		return error.UnknownTool;
	}

	const result = try exec.run(io, allocator, argv.items);

	var out: std.Io.Writer.Allocating = .init(allocator);
	try out.writer.print("{{\"ok\":{s},\"code\":{d},\"out\":", .{ if (result.code == 0) "true" else "false", result.code });
	try json.encodeText(&out.writer, result.out);
	try out.writer.writeAll(",\"err\":");
	try json.encodeText(&out.writer, result.err);
	try out.writer.writeAll("}");
	return out.written();
}

fn emptyDir(io: Io, allocator: Allocator, path: []const u8) !void {
	var dir = try std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true });
	defer dir.close(io);

	var it = dir.iterate();
	while (try it.next(io)) |entry| {
		const child = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ path, entry.name });
		try std.Io.Dir.cwd().deleteTree(io, child);
	}
}

fn cleanupScans(io: Io, socket_dir: []const u8) void {
	const allocator = std.heap.smp_allocator;
	var dir = std.Io.Dir.cwd().openDir(io, socket_dir, .{ .iterate = true }) catch return;
	defer dir.close(io);

	var it = dir.iterate();
	while (it.next(io) catch null) |entry| {
		if (!std.mem.startsWith(u8, entry.name, "scan-")) continue;
		if (!std.mem.endsWith(u8, entry.name, ".bin")) continue;

		const path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ socket_dir, entry.name }) catch continue;
		defer allocator.free(path);
		std.Io.Dir.cwd().deleteFile(io, path) catch {};
	}
}

fn chmodPath(path: []const u8, mode: u32) void {
	const z = std.heap.smp_allocator.allocSentinel(u8, path.len, 0) catch return;
	defer std.heap.smp_allocator.free(z);
	@memcpy(z, path);
	_ = linux.chmod(z.ptr, mode);
}

fn watch(io: Io, allocator: Allocator, pidfd: i32, peer: Peer, request: json.Value) ![]const u8 {
	const path = if (json.textAt(request, "path").len > 0) json.textAt(request, "path") else "/";
	try authorize(pidfd, peer.uid, peer.gid, bench_action, path);

	var guard = try guardmod.Guard.init(allocator, io, &.{});
	defer guard.deinit(allocator);
	const mark_path = guard.mountRoot(path);

	const seconds = @max(json.integer(json.field(request, "seconds")), 1);
	var watcher = try fanotify.Watcher.init();
	defer watcher.close();
	watcher.mark(mark_path) catch {
		watcher.markDir(path) catch return error.MarkFailed;
	};

	var buffer: [64 * 1024]u8 align(8) = undefined;
	const deadline = fmt.nowMs(io) + seconds * 1000;
	var events: u64 = 0;
	var overflow: u64 = 0;
	var first: []const u8 = "";
	var last: []const u8 = "";
	var names: std.ArrayList([]const u8) = .empty;

	while (fmt.nowMs(io) < deadline) {
		var batch = try watcher.read(&buffer);
		defer fanotify.freeBatch(batch);

		if (batch.events.len == 0) {
			sleep.ms(2);
			continue;
		}

		while (batch.take()) |event| {
			events += 1;
			if (event.overflow) overflow += 1;
			if (event.name.len > 0) {
				if (first.len == 0) first = event.name;
				last = event.name;
				if (names.items.len < 256 and !hasName(names.items, event.name)) {
					names.append(allocator, allocator.dupe(u8, event.name) catch continue) catch {};
				}
			}
		}
	}

	var out: std.Io.Writer.Allocating = .init(allocator);
	try out.writer.print("{{\"ok\":true,\"path\":{f},\"events\":{d},\"overflow\":{d},\"perSecond\":{d},\"first\":{f},\"last\":{f},\"names\":[", .{
		std.json.fmt(path, .{}),
		events,
		overflow,
		events / seconds,
		std.json.fmt(first, .{}),
		std.json.fmt(last, .{}),
	});
	for (names.items, 0..) |name, index| {
		if (index > 0) try out.writer.writeAll(",");
		try json.encodeText(&out.writer, name);
	}
	try out.writer.writeAll("]}");
	return out.written();
}

fn hasName(names: []const []const u8, name: []const u8) bool {
	for (names) |known| if (std.mem.eql(u8, known, name)) return true;
	return false;
}

fn safePackage(name: []const u8) bool {
	if (name.len == 0 or name[0] == '-') return false;
	for (name) |c| {
		if (std.ascii.isAlphanumeric(c)) continue;
		if (c == '@' or c == '.' or c == '_' or c == '+' or c == '-') continue;
		return false;
	}
	return true;
}

fn authorize(pidfd: i32, uid: u32, gid: u32, action: []const u8, detail_text: []const u8) !void {
	var action_z: [128]u8 = undefined;
	var detail_z: [4096]u8 = undefined;
	if (action.len >= action_z.len or detail_text.len >= detail_z.len) return error.TooLong;

	@memcpy(action_z[0..action.len], action);
	action_z[action.len] = 0;
	@memcpy(detail_z[0..detail_text.len], detail_text);
	detail_z[detail_text.len] = 0;

	var error_buffer: [512]u8 = @splat(0);
	const verdict = yudae_polkit_check(
		pidfd,
		@intCast(uid),
		@intCast(gid),
		@ptrCast(&action_z),
		@ptrCast(&detail_z),
		&error_buffer,
		error_buffer.len,
	);

	if (verdict == 1) return;
	if (verdict == 0) return error.Denied;
	return error.PolkitFailed;
}

fn peerOf(fd: i32) ?Peer {
	var peer: Peer = undefined;
	var length: linux.socklen_t = @sizeOf(Peer);
	const result = linux.getsockopt(fd, linux.SOL.SOCKET, linux.SO.PEERCRED, @ptrCast(&peer), &length);
	if (linux.errno(result) != .SUCCESS) return null;
	return peer;
}

fn reply(io: Io, fd: i32, body: []const u8) void {
	_ = io;
	sock.writeAll(fd, body) catch return;
	sock.writeAll(fd, "\n") catch return;
}

test "package names cannot turn into pacman options" {
	try std.testing.expect(safePackage("linux"));
	try std.testing.expect(safePackage("lib32-glibc"));
	try std.testing.expect(safePackage("python-foo_bar"));
	try std.testing.expect(!safePackage("-Syu"));
	try std.testing.expect(!safePackage("a b"));
}
