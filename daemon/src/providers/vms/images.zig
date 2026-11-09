const std = @import("std");
const proc = @import("../../primitives/proc.zig");
const exec = @import("../../primitives/exec.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;

pub fn overlay(io: Io, allocator: Allocator, name: []const u8) ![]u8 {
	return overlayFrom(io, allocator, name, "");
}

pub fn overlayFrom(io: Io, allocator: Allocator, name: []const u8, tag: []const u8) ![]u8 {
	const repo = proc.repo(io, allocator);
	const script = try std.fs.path.join(allocator, &.{ repo, "vm", "images" });

	var argv: std.ArrayListUnmanaged([]const u8) = .empty;
	defer argv.deinit(allocator);
	try argv.appendSlice(allocator, &.{ "bash", script, "overlay", name });
	if (tag.len > 0) try argv.append(allocator, tag);

	const result = try exec.runLimit(io, allocator, argv.items, null, 1024 * 1024);
	defer result.deinit(allocator);

	if (result.code != 0) return error.ImageFailed;

	const trimmed = std.mem.trim(u8, result.out, " \t\r\n");
	const line = if (std.mem.lastIndexOfScalar(u8, trimmed, '\n')) |at| trimmed[at + 1 ..] else trimmed;

	if (line.len == 0) return error.ImageFailed;
	return allocator.dupe(u8, line);
}

pub fn ensure(io: Io, allocator: Allocator) !void {
	const repo = proc.repo(io, allocator);
	const script = try std.fs.path.join(allocator, &.{ repo, "vm", "images" });

	const result = try exec.runLimit(io, allocator, &.{ "bash", script, "ensure" }, null, 1024 * 1024);
	defer result.deinit(allocator);

	if (result.code != 0) return error.ImageFailed;
}
