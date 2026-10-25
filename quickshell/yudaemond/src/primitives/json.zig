const std = @import("std");

pub const Value = std.json.Value;
pub const Allocator = std.mem.Allocator;

pub fn parse(allocator: Allocator, body: []const u8) !std.json.Parsed(Value) {
	return std.json.parseFromSlice(Value, allocator, body, .{ .allocate = .alloc_always });
}

pub fn field(value: Value, key: []const u8) ?Value {
	return switch (value) {
		.object => |map| map.get(key),
		else => null,
	};
}

pub fn deep(value: Value, keys: []const []const u8) ?Value {
	var current = value;

	for (keys) |key| {
		current = field(current, key) orelse return null;
	}

	return current;
}

pub fn text(value: ?Value) []const u8 {
	const v = value orelse return "";
	return switch (v) {
		.string => |s| s,
		.number_string => |s| s,
		else => "",
	};
}

pub fn textAt(value: Value, key: []const u8) []const u8 {
	return text(field(value, key));
}

pub fn textDeep(value: Value, keys: []const []const u8) []const u8 {
	return text(deep(value, keys));
}

pub fn number(value: ?Value) f64 {
	const v = value orelse return 0;
	return switch (v) {
		.integer => |n| @floatFromInt(n),
		.float => |n| n,
		.number_string => |s| std.fmt.parseFloat(f64, s) catch 0,
		else => 0,
	};
}

pub fn numberAt(value: Value, key: []const u8) f64 {
	return number(field(value, key));
}

pub fn integer(value: ?Value) i64 {
	const v = value orelse return 0;
	return switch (v) {
		.integer => |n| n,
		.float => |n| @intFromFloat(n),
		.number_string => |s| std.fmt.parseInt(i64, s, 10) catch 0,
		else => 0,
	};
}

pub fn flag(value: Value, key: []const u8) bool {
	return switch (field(value, key) orelse return false) {
		.bool => |b| b,
		else => false,
	};
}

pub fn list(value: ?Value) []const Value {
	const v = value orelse return &.{};
	return switch (v) {
		.array => |items| items.items,
		else => &.{},
	};
}

pub fn listAt(value: Value, key: []const u8) []const Value {
	return list(field(value, key));
}

pub fn write(writer: *std.Io.Writer, value: anytype) !void {
	try writer.print("{f}", .{std.json.fmt(value, .{})});
}

test "json reads nested values" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const parsed = try parse(arena.allocator(), "{\"data\":{\"id\":\"a\",\"n\":2,\"list\":[{\"x\":1}]}}");
	const root = parsed.value;

	try std.testing.expectEqualStrings("a", textDeep(root, &.{ "data", "id" }));
	try std.testing.expectEqual(@as(f64, 2), number(deep(root, &.{ "data", "n" })));
	try std.testing.expectEqual(@as(usize, 1), list(deep(root, &.{ "data", "list" })).len);
	try std.testing.expectEqual(@as(usize, 0), text(field(root, "absent")).len);
}

test "json rejects garbage" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	try std.testing.expectError(error.SyntaxError, parse(arena.allocator(), "not json"));
}
