const std = @import("std");
const proc = @import("../../primitives/proc.zig");

const Io = std.Io;
const Allocator = std.mem.Allocator;

pub const Budget = struct {
	mem_mb: u32,
	cores: u32,
};

pub fn detect(io: Io, allocator: Allocator) Budget {
	const body = proc.readFile(io, allocator, "/proc/meminfo") catch "";
	defer allocator.free(body);

	var total_mb: u32 = 0;

	if (std.mem.indexOf(u8, body, "MemTotal:")) |at| {
		var index = at + "MemTotal:".len;

		while (index < body.len and (body[index] == ' ' or body[index] == '\t')) index += 1;

		var end = index;
		while (end < body.len and std.ascii.isDigit(body[end])) end += 1;

		const kb = std.fmt.parseInt(u64, body[index..end], 10) catch 0;
		total_mb = @intCast(kb / 1024);
	}

	const cpus = std.Thread.getCpuCount() catch 1;

	return .{
		.mem_mb = @max(total_mb / 2, 1024),
		.cores = @max(@as(u32, @intCast(cpus)) / 4, 1),
	};
}
