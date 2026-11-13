const std = @import("std");
const proc = @import("../../primitives/proc.zig");
const json = @import("../../primitives/json.zig");
const sock = @import("../../primitives/sock.zig");
const exec = @import("../../primitives/exec.zig");
const guardmod = @import("guard.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const Package = struct {
	name: []const u8 = "",
	version: []const u8 = "",
	size: u64 = 0,
	reason: u8 = 1,
	repo: []const u8 = "",
	deps: [][]const u8 = &.{},
	required: bool = false,
};

pub fn render(io: Io, allocator: Allocator) ![]u8 {
	var arena = std.heap.ArenaAllocator.init(allocator);
	defer arena.deinit();
	const inner = arena.allocator();

	const list = try pacman(io, inner);
	var required = std.StringHashMap(void).init(inner);
	defer required.deinit();

	for (list) |pkg| {
		for (pkg.deps) |dep| {
			const name = depName(dep);
			if (name.len > 0) required.put(name, {}) catch {};
		}
	}

	var total: u64 = 0;
	var explicit_count: usize = 0;
	var orphan_count: usize = 0;

	for (list) |*pkg| {
		pkg.required = required.contains(pkg.name);
		const orphan = pkg.reason != 0 and !pkg.required;
		if (orphan) orphan_count += 1;
		if (pkg.reason == 0) explicit_count += 1;
		total += pkg.size;
	}

	var out: std.Io.Writer.Allocating = .init(allocator);
	const w = &out.writer;
	try w.writeAll("{\"ok\":true,\"total\":");
	try w.print("{d},\"explicit\":{d},\"orphans\":{d},\"list\":[", .{ total, explicit_count, orphan_count });

	for (list, 0..) |pkg, index| {
		if (index > 0) try w.writeAll(",");
		const aur = pkg.repo.len == 0 or std.mem.eql(u8, pkg.repo, "local");

		try w.writeAll("{\"name\":");
		try json.encodeText(w, pkg.name);
		try w.writeAll(",\"version\":");
		try json.encodeText(w, pkg.version);
		try w.print(",\"size\":{d},\"repo\":", .{pkg.size});
		try json.encodeText(w, if (aur) "aur" else pkg.repo);
		try w.print(",\"explicit\":{s},\"orphan\":{s},\"aur\":{s}}}", .{
			if (pkg.reason == 0) "true" else "false",
			if (pkg.reason != 0 and !pkg.required) "true" else "false",
			if (aur) "true" else "false",
		});
	}

	try w.writeAll("],\"flatpak\":[");
	const flat = flatpak(io, inner) catch &.{};
	for (flat, 0..) |app, index| {
		if (index > 0) try w.writeAll(",");
		try w.writeAll("{\"name\":");
		try json.encodeText(w, app.name);
		try w.writeAll(",\"version\":");
		try json.encodeText(w, app.version);
		try w.print(",\"size\":{d},\"origin\":", .{app.size});
		try json.encodeText(w, app.origin);
		try w.writeAll(",\"installation\":");
		try json.encodeText(w, app.installation);
		try w.writeAll("}");
	}
	try w.writeAll("]}");

	return out.written();
}

fn pacman(io: Io, allocator: Allocator) ![]Package {
	var out: std.ArrayList(Package) = .empty;
	var dir = try std.Io.Dir.cwd().openDir(io, "/var/lib/pacman/local", .{ .iterate = true });
	defer dir.close(io);

	var it = dir.iterate();
	while (try it.next(io)) |entry| {
		if (entry.kind != .directory) continue;

		const path = try std.fmt.allocPrint(allocator, "/var/lib/pacman/local/{s}/desc", .{entry.name});
		const body = proc.readFile(io, allocator, path) catch continue;
		if (try parse(io, allocator, body)) |pkg| try out.append(allocator, pkg);
	}

	return out.toOwnedSlice(allocator);
}

fn parse(io: Io, allocator: Allocator, body: []const u8) !?Package {
	_ = io;
	var pkg: Package = .{};
	var deps: std.ArrayList([]const u8) = .empty;
	var current: []const u8 = "";
	var value: std.ArrayList(u8) = .empty;

	var lines = std.mem.splitScalar(u8, body, '\n');
	while (lines.next()) |line| {
		if (line.len > 2 and line[0] == '%' and line[line.len - 1] == '%') {
			try apply(allocator, &pkg, current, value.items);
			value.clearRetainingCapacity();
			current = line[1 .. line.len - 1];
			continue;
		}

		if (line.len == 0) {
			try apply(allocator, &pkg, current, value.items);
			value.clearRetainingCapacity();
			current = "";
			continue;
		}

		if (current.len == 0) continue;
		if (std.mem.eql(u8, current, "DEPENDS")) {
			try deps.append(allocator, try allocator.dupe(u8, line));
			continue;
		}

		if (std.mem.eql(u8, current, "NAME") or std.mem.eql(u8, current, "VERSION") or std.mem.eql(u8, current, "INSTALLED_DB") or std.mem.eql(u8, current, "SIZE") or std.mem.eql(u8, current, "REASON")) {
			try value.appendSlice(allocator, line);
		}
	}

	try apply(allocator, &pkg, current, value.items);
	pkg.deps = try deps.toOwnedSlice(allocator);
	if (pkg.name.len == 0) return null;
	return pkg;
}

fn apply(allocator: Allocator, pkg: *Package, key: []const u8, value: []const u8) !void {
	if (std.mem.eql(u8, key, "NAME")) pkg.name = try allocator.dupe(u8, value);
	if (std.mem.eql(u8, key, "VERSION")) pkg.version = try allocator.dupe(u8, value);
	if (std.mem.eql(u8, key, "SIZE")) pkg.size = std.fmt.parseInt(u64, value, 10) catch 0;
	if (std.mem.eql(u8, key, "REASON")) pkg.reason = std.fmt.parseInt(u8, value, 10) catch 1;
	if (std.mem.eql(u8, key, "INSTALLED_DB")) pkg.repo = try allocator.dupe(u8, value);
}

fn depName(dep: []const u8) []const u8 {
	var end = dep.len;
	for (dep, 0..) |c, index| {
		if (c == '>' or c == '<' or c == '=' or c == ':') {
			end = index;
			break;
		}
	}
	return dep[0..end];
}

const Flatpak = struct { name: []const u8, version: []const u8, size: u64, origin: []const u8, installation: []const u8 };

test "a desc keeps size, reason and repo" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const body =
		"%NAME%\nfoo\n\n%VERSION%\n1-1\n\n%INSTALLED_DB%\ncore\n\n%SIZE%\n4096\n\n%REASON%\n0\n\n%DEPENDS%\nbar\nbaz>=2\n";
	const pkg = (try parse(std.testing.io, arena.allocator(), body)).?;

	try std.testing.expectEqualStrings("foo", pkg.name);
	try std.testing.expectEqualStrings("1-1", pkg.version);
	try std.testing.expectEqualStrings("core", pkg.repo);
	try std.testing.expectEqual(@as(u64, 4096), pkg.size);
	try std.testing.expectEqual(@as(u8, 0), pkg.reason);
	try std.testing.expectEqual(@as(usize, 2), pkg.deps.len);
}

fn flatpak(io: Io, allocator: Allocator) ![]Flatpak {
	const result = exec.run(io, allocator, &.{ "flatpak", "list", "--columns=application,version,size,origin,installation" }) catch return &.{};
	if (result.code != 0) return &.{};

	var out: std.ArrayList(Flatpak) = .empty;
	var lines = std.mem.splitScalar(u8, result.out, '\n');
	while (lines.next()) |line| {
		if (line.len == 0) continue;
		var fields = std.mem.splitScalar(u8, line, '\t');

		const name = fields.next() orelse continue;
		const version = fields.next() orelse "";
		const size_text = fields.next() orelse "";
		const origin = fields.next() orelse "";
		const installation = fields.next() orelse "user";

		try out.append(allocator, .{
			.name = try allocator.dupe(u8, name),
			.version = try allocator.dupe(u8, version),
			.size = parseSize(size_text),
			.origin = try allocator.dupe(u8, origin),
			.installation = try allocator.dupe(u8, installation),
		});
	}

	return out.toOwnedSlice(allocator);
}

fn parseSize(text: []const u8) u64 {
	var parts = std.mem.tokenizeAny(u8, text, " \t");
	const number = parts.next() orelse return 0;
	const unit = parts.next() orelse "B";
	const value = std.fmt.parseFloat(f64, number) catch return 0;

	const multiplier: f64 = if (std.mem.eql(u8, unit, "GB"))
		1024.0 * 1024.0 * 1024.0
	else if (std.mem.eql(u8, unit, "MB"))
		1024.0 * 1024.0
	else if (std.mem.eql(u8, unit, "kB") or std.mem.eql(u8, unit, "KB"))
		1024.0
	else
		1.0;

	return @intFromFloat(@max(0, value * multiplier));
}

pub fn uninstall(io: Io, allocator: Allocator, args: json.Value, helper: bool) ![]u8 {
	const names = json.listAt(args, "names");
	if (names.len == 0) return error.Empty;

	var out: std.Io.Writer.Allocating = .init(allocator);
	const w = &out.writer;

	if (!json.flag(args, "confirm")) {
		const installed_pacman = pacman(io, allocator) catch &.{};
		const installed_flatpak = flatpak(io, allocator) catch &.{};

		var space: u64 = 0;
		try w.writeAll("{\"ok\":false,\"error\":\"confirm\",\"items\":[");
		for (names, 0..) |item, index| {
			const name = json.text(item);
			var size: u64 = 0;

			for (installed_pacman) |pkg| {
				if (std.mem.eql(u8, pkg.name, name)) size = pkg.size;
			}
			for (installed_flatpak) |app| {
				if (std.mem.eql(u8, app.name, name)) size = app.size;
			}

			space += size;
			if (index > 0) try w.writeAll(",");
			try w.writeAll("{\"name\":");
			try json.encodeText(w, name);
			try w.print(",\"size\":{d}}}", .{size});
		}
		try w.print("],\"space\":{d}}}", .{space});
		return out.written();
	}

	var pacman_names: std.ArrayList([]const u8) = .empty;
	var user_flatpak: std.ArrayList([]const u8) = .empty;
	var system_flatpak: std.ArrayList([]const u8) = .empty;
	const installed_flatpak = flatpak(io, allocator) catch &.{};

	for (names) |item| {
		const name = json.text(item);
		var found = false;

		for (installed_flatpak) |app| {
			if (!std.mem.eql(u8, app.name, name)) continue;
			found = true;
			if (std.mem.eql(u8, app.installation, "system")) {
				try system_flatpak.append(allocator, name);
			} else {
				try user_flatpak.append(allocator, name);
			}
		}

		if (!found) try pacman_names.append(allocator, name);
	}

	var results: std.ArrayList(u8) = .empty;
	if (user_flatpak.items.len > 0) {
		var argv: std.ArrayList([]const u8) = .empty;
		try argv.append(allocator, "flatpak");
		try argv.append(allocator, "uninstall");
		try argv.append(allocator, "--user");
		try argv.append(allocator, "--noninteractive");
		try argv.append(allocator, "--assume-yes");
		for (user_flatpak.items) |name| try argv.append(allocator, name);
		const result = exec.run(io, allocator, argv.items) catch null;
		if (result) |value| {
			defer value.deinit(allocator);
			try results.appendSlice(allocator, value.out);
			if (value.code != 0) try results.appendSlice(allocator, value.err);
		}
	}

	if (system_flatpak.items.len > 0) {
		if (!helper) return error.HelperUnavailable;
		const text = try helperPackages(io, allocator, system_flatpak.items, true);
		try results.appendSlice(allocator, text);
	}

	if (pacman_names.items.len > 0) {
		if (!helper) return error.HelperUnavailable;
		const text = try helperPackages(io, allocator, pacman_names.items, false);
		try results.appendSlice(allocator, text);
	}

	try w.writeAll("{\"ok\":true,\"out\":");
	try json.encodeText(w, results.items);
	try w.writeAll("}");
	return out.written();
}

pub fn clean(io: Io, allocator: Allocator, args: json.Value, helper: bool) ![]u8 {
	const list = try pacman(io, allocator);
	var required = std.StringHashMap(void).init(allocator);
	defer required.deinit();

	for (list) |pkg| {
		for (pkg.deps) |dep| {
			const name = depName(dep);
			if (name.len > 0) required.put(name, {}) catch {};
		}
	}

	var orphans: std.ArrayList([]const u8) = .empty;
	var space: u64 = 0;
	for (list) |pkg| {
		if (pkg.reason == 0 or required.contains(pkg.name)) continue;
		try orphans.append(allocator, pkg.name);
		space += pkg.size;
	}

	var out: std.Io.Writer.Allocating = .init(allocator);
	const w = &out.writer;

	if (!json.flag(args, "confirm")) {
		try w.writeAll("{\"ok\":false,\"error\":\"confirm\",\"items\":[");
		for (orphans.items, 0..) |name, index| {
			if (index > 0) try w.writeAll(",");
			var size: u64 = 0;
			for (list) |pkg| {
				if (std.mem.eql(u8, pkg.name, name)) size = pkg.size;
			}
			try w.writeAll("{\"name\":");
			try json.encodeText(w, name);
			try w.print(",\"size\":{d}}}", .{size});
		}
		try w.print("],\"space\":{d}}}", .{space});
		return out.written();
	}

	if (orphans.items.len == 0) return allocator.dupe(u8, "{\"ok\":true,\"out\":\"no orphan packages\"}");

	var names = std.json.Array.init(allocator);
	for (orphans.items) |name| try names.append(.{ .string = name });

	var object: std.json.ObjectMap = .empty;
	try object.put(allocator, "names", .{ .array = names });
	try object.put(allocator, "confirm", .{ .bool = true });
	return uninstall(io, allocator, .{ .object = object }, helper);
}

fn helperPackages(io: Io, allocator: Allocator, names: []const []const u8, flatpak_mode: bool) ![]const u8 {
	_ = io;
	var request: std.Io.Writer.Allocating = .init(allocator);
	try request.writer.writeAll("{\"action\":\"packages\",");
	if (flatpak_mode) try request.writer.writeAll("\"flatpak\":true,");
	try request.writer.writeAll("\"names\":[");
	for (names, 0..) |name, index| {
		if (index > 0) try request.writer.writeAll(",");
		try json.encodeText(&request.writer, name);
	}
	try request.writer.writeAll("]}");

	var buffer: [1024 * 1024]u8 = undefined;
	var connection = sock.Connection.connect(helperPath(), &buffer) catch return error.HelperUnavailable;
	defer connection.close();
	try connection.writeLine(request.written());
	const line = try connection.readLine() orelse return error.NoReply;
	const parsed = try json.parse(allocator, line);
	if (!json.flag(parsed.value, "ok")) return error.UninstallFailed;
	return allocator.dupe(u8, json.textAt(parsed.value, "out"));
}

fn helperPath() []const u8 {
	return guardmod.fsdSocket();
}
