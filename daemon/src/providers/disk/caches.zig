const std = @import("std");
const proc = @import("../../primitives/proc.zig");
const json = @import("../../primitives/json.zig");
const sock = @import("../../primitives/sock.zig");
const exec = @import("../../primitives/exec.zig");
const guardmod = @import("guard.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

const Entry = struct {
	id: []const u8,
	label: []const u8,
	path: []const u8,
	tool: []const u8,
	root: bool = false,
};

const fixed = [_]Entry{
	.{ .id = "pacman", .label = "pacman package cache", .path = "/var/cache/pacman/pkg", .tool = "paccache", .root = true },
	.{ .id = "journal", .label = "system journal", .path = "/var/log/journal", .tool = "journalctl", .root = true },
	.{ .id = "coredump", .label = "core dumps", .path = "/var/lib/systemd/coredump", .tool = "coredump", .root = true },
	.{ .id = "paru", .label = "paru clones", .path = "{home}/.cache/paru/clone", .tool = "paru" },
	.{ .id = "npm", .label = "npm cache", .path = "{home}/.npm", .tool = "npm" },
	.{ .id = "bun", .label = "bun cache", .path = "{home}/.bun/install/cache", .tool = "bun" },
	.{ .id = "cargo", .label = "cargo registry", .path = "{home}/.cargo/registry", .tool = "" },
	.{ .id = "go", .label = "go module cache", .path = "{home}/go/pkg/mod", .tool = "go" },
	.{ .id = "rustup", .label = "rustup toolchains", .path = "{home}/.rustup", .tool = "" },
	.{ .id = "zig", .label = "zig cache", .path = "{home}/.cache/zig", .tool = "" },
	.{ .id = "mesa", .label = "mesa shader cache", .path = "{home}/.cache/mesa_shader_cache", .tool = "" },
	.{ .id = "thumbnails", .label = "thumbnails", .path = "{home}/.cache/thumbnails", .tool = "" },
	.{ .id = "pip", .label = "pip cache", .path = "{home}/.cache/pip", .tool = "" },
	.{ .id = "uv", .label = "uv cache", .path = "{home}/.cache/uv", .tool = "" },
	.{ .id = "trash", .label = "trash", .path = "{home}/.local/share/Trash", .tool = "" },
	.{ .id = "vm-base", .label = "VM base images", .path = "{home}/.cache/dotfiles/vm-base", .tool = "" },
	.{ .id = "rootfs", .label = "rootfs builds", .path = "{home}/rootfs-build", .tool = "" },
};

pub fn render(io: Io, allocator: Allocator) ![]u8 {
	var arena = std.heap.ArenaAllocator.init(allocator);
	defer arena.deinit();
	const inner = arena.allocator();
	const home = proc.home(io, inner);

	var entries: std.ArrayList(Entry) = .empty;
	defer entries.deinit(inner);

	for (fixed) |entry| {
		try entries.append(inner, .{
			.id = try inner.dupe(u8, entry.id),
			.label = try inner.dupe(u8, entry.label),
			.path = try expand(inner, entry.path, home),
			.tool = try inner.dupe(u8, entry.tool),
			.root = entry.root,
		});
	}

	const yudae_dir = try std.fmt.allocPrint(inner, "{s}/.cache", .{home});
	if (std.Io.Dir.cwd().openDir(io, yudae_dir, .{ .iterate = true })) |dir| {
		defer dir.close(io);
		var it = dir.iterate();
		while (try it.next(io)) |child| {
			if (child.kind != .directory) continue;
			if (!std.mem.startsWith(u8, child.name, "yudae")) continue;

			try entries.append(inner, .{
				.id = try std.fmt.allocPrint(inner, "yudae:{s}", .{child.name}),
				.label = try std.fmt.allocPrint(inner, "{s}", .{child.name}),
				.path = try std.fmt.allocPrint(inner, "{s}/{s}", .{ yudae_dir, child.name }),
				.tool = "",
			});
		}
	} else |_| {}

	var total: u64 = 0;
	var out: std.Io.Writer.Allocating = .init(allocator);
	const w = &out.writer;
	try w.writeAll("{\"ok\":true,\"list\":[");

	for (entries.items, 0..) |entry, index| {
		const size = dirSize(io, inner, entry.path, 0);
		total += size;
		if (index > 0) try w.writeAll(",");
		try w.writeAll("{\"id\":");
		try json.encodeText(w, entry.id);
		try w.writeAll(",\"label\":");
		try json.encodeText(w, entry.label);
		try w.writeAll(",\"path\":");
		try json.encodeText(w, entry.path);
		try w.writeAll(",\"tool\":");
		try json.encodeText(w, entry.tool);
		try w.print(",\"size\":{d},\"root\":{s},\"exists\":{s}}}", .{
			size,
			if (entry.root) "true" else "false",
			if (proc.exists(io, entry.path)) "true" else "false",
		});
	}

	try w.print("],\"total\":{d}}}", .{total});
	return out.written();
}

pub fn clean(io: Io, allocator: Allocator, args: json.Value, helper: bool) ![]u8 {
	const wanted = json.textAt(args, "id");

	var arena = std.heap.ArenaAllocator.init(allocator);
	defer arena.deinit();
	const inner = arena.allocator();
	const home = proc.home(io, inner);

	var entries: std.ArrayList(Entry) = .empty;

	for (fixed) |entry| {
		try entries.append(inner, .{
			.id = entry.id,
			.label = entry.label,
			.path = try expand(inner, entry.path, home),
			.tool = entry.tool,
			.root = entry.root,
		});
	}

	const cache_root = try std.fmt.allocPrint(inner, "{s}/.cache", .{home});
	if (std.Io.Dir.cwd().openDir(io, cache_root, .{ .iterate = true })) |dir| {
		defer dir.close(io);
		var it = dir.iterate();
		while (try it.next(io)) |child| {
			if (child.kind != .directory or !std.mem.startsWith(u8, child.name, "yudae")) continue;
			try entries.append(inner, .{
				.id = try std.fmt.allocPrint(inner, "yudae:{s}", .{child.name}),
				.label = child.name,
				.path = try std.fmt.allocPrint(inner, "{s}/{s}", .{ cache_root, child.name }),
				.tool = "",
			});
		}
	} else |_| {}

	var matched: std.ArrayList(Entry) = .empty;
	for (entries.items) |entry| {
		if (wanted.len > 0 and !std.mem.eql(u8, wanted, "all") and !std.mem.eql(u8, wanted, entry.id)) continue;
		try matched.append(inner, entry);
	}

	if (matched.items.len == 0) return error.NoCache;

	var out: std.Io.Writer.Allocating = .init(allocator);
	const w = &out.writer;

	if (!json.flag(args, "confirm")) {
		var space: u64 = 0;
		try w.writeAll("{\"ok\":false,\"error\":\"confirm\",\"items\":[");
		for (matched.items, 0..) |entry, index| {
			const size = dirSize(io, inner, entry.path, 0);
			space += size;
			if (index > 0) try w.writeAll(",");
			try w.writeAll("{\"id\":");
			try json.encodeText(w, entry.id);
			try w.writeAll(",\"label\":");
			try json.encodeText(w, entry.label);
			try w.print(",\"size\":{d}}}", .{size});
		}
		try w.print("],\"space\":{d}}}", .{space});
		return out.written();
	}

	var output: std.ArrayList(u8) = .empty;
	for (matched.items) |entry| {
		const before = dirSize(io, inner, entry.path, 0);
		if (entry.root and (std.mem.eql(u8, entry.tool, "paccache") or std.mem.eql(u8, entry.tool, "journalctl") or std.mem.eql(u8, entry.tool, "coredump"))) {
			if (!helper) return error.HelperUnavailable;
			const tool = if (std.mem.eql(u8, entry.tool, "journalctl")) "journal" else entry.tool;
			try helperCache(io, inner, tool);
		} else if (entry.tool.len > 0) {
			const argv = toolArgv(inner, entry.tool, entry.path) catch {
				try removePath(io, inner, entry.path);
				continue;
			};
			const result = exec.run(io, inner, argv) catch null;
			if (result) |value| try output.appendSlice(inner, value.out);
		} else {
			try removePath(io, inner, entry.path);
		}

		const after = dirSize(io, inner, entry.path, 0);
		const freed = if (before > after) before - after else 0;
		try output.appendSlice(inner, try std.fmt.allocPrint(inner, "{s}: freed {d} bytes\n", .{ entry.label, freed }));
	}

	try w.writeAll("{\"ok\":true,\"out\":");
	try json.encodeText(w, output.items);
	try w.writeAll("}");
	return out.written();
}

fn expand(allocator: Allocator, template: []const u8, home: []const u8) ![]const u8 {
	if (std.mem.startsWith(u8, template, "{home}")) {
		return std.fmt.allocPrint(allocator, "{s}{s}", .{ home, template["{home}".len..] });
	}
	return allocator.dupe(u8, template);
}

fn dirSize(io: Io, allocator: Allocator, path: []const u8, depth: usize) u64 {
	if (depth > 64) return 0;

	const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return 0;
	if (stat.kind != .directory) return stat.size;

	var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return 0;
	defer dir.close(io);

	var total: u64 = 0;
	var it = dir.iterate();
	while (it.next(io) catch null) |entry| {
		if (entry.kind == .sym_link) continue;
		const child = std.fmt.allocPrint(allocator, "{s}/{s}", .{ path, entry.name }) catch continue;
		defer allocator.free(child);
		total += dirSize(io, allocator, child, depth + 1);
	}

	return total;
}

fn toolArgv(allocator: Allocator, tool: []const u8, path: []const u8) ![]const []const u8 {
	_ = path;
	if (std.mem.eql(u8, tool, "npm")) return &.{ "npm", "cache", "clean", "--force" };
	if (std.mem.eql(u8, tool, "bun")) return &.{ "bun", "pm", "cache", "rm" };
	if (std.mem.eql(u8, tool, "go")) return &.{ "go", "clean", "-modcache" };
	_ = allocator;
	return error.NoTool;
}

fn removePath(io: Io, allocator: Allocator, path: []const u8) !void {
	var guard = try guardmod.Guard.init(allocator, io, &.{});
	defer guard.deinit(allocator);
	guardmod.removeTree(path, &guard, "/") catch return;
}

fn helperCache(io: Io, allocator: Allocator, tool: []const u8) !void {
	var request: std.Io.Writer.Allocating = .init(allocator);
	try request.writer.writeAll("{\"action\":\"cache\",\"tool\":");
	try json.encodeText(&request.writer, tool);
	try request.writer.writeAll("}");

	var buffer: [1024 * 1024]u8 = undefined;
	var connection = sock.Connection.connect(helperPath(), &buffer) catch return error.HelperUnavailable;
	defer connection.close();
	try connection.writeLine(request.written());
	const line = try connection.readLine() orelse return error.NoReply;
	const parsed = try json.parse(allocator, line);
	if (!json.flag(parsed.value, "ok")) return error.CleanFailed;
	_ = io;
}

fn helperPath() []const u8 {
	return guardmod.fsdSocket();
}
