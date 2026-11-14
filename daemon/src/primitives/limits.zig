const std = @import("std");

pub const Limit = struct {
	title: []const u8,
	percent: f64,
	resetsAt: []const u8,
};

pub const Plan = struct {
	title: []const u8 = "",
	limits: []const Limit = &.{},
	failure: []const u8 = "",
};

pub fn copy(allocator: std.mem.Allocator, title: []const u8, failure: []const u8, limits: anytype) !Plan {
	var out: std.ArrayListUnmanaged(Limit) = .empty;

	for (limits) |entry| {
		try out.append(allocator, .{
			.title = try allocator.dupe(u8, entry.title),
			.percent = entry.percent,
			.resetsAt = try allocator.dupe(u8, entry.resets_at),
		});
	}

	return .{
		.title = try allocator.dupe(u8, title),
		.limits = out.items,
		.failure = try allocator.dupe(u8, failure),
	};
}

test "a plan is copied out of a provider's own strings" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const Item = struct { title: []const u8, percent: f64, resets_at: []const u8 };
	const items = [_]Item{
		.{ .title = "Session", .percent = 12.5, .resets_at = "soon" },
	};

	const plan = try copy(arena.allocator(), "OpenCode", "", &items);

	try std.testing.expectEqualStrings("OpenCode", plan.title);
	try std.testing.expectEqual(@as(usize, 1), plan.limits.len);
	try std.testing.expectEqual(@as(f64, 12.5), plan.limits[0].percent);
	try std.testing.expectEqualStrings("soon", plan.limits[0].resetsAt);
}
