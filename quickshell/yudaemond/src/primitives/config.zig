const std = @import("std");
const proc = @import("proc.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Config = struct {
	allocator: Allocator,
	text: []u8,

	pub fn load(io: Io, allocator: Allocator) !Config {
		const path = try std.fmt.allocPrint(allocator, "{s}/.config/quickshell/config.js", .{proc.home(io, allocator)});
		defer allocator.free(path);

		return .{ .allocator = allocator, .text = try proc.readFile(io, allocator, path) };
	}

	pub fn deinit(self: Config) void {
		self.allocator.free(self.text);
	}

	fn raw(self: Config, name: []const u8) ?[]const u8 {
		var lines = std.mem.splitScalar(u8, self.text, '\n');

		while (lines.next()) |line| {
			const trimmed = std.mem.trim(u8, line, " \t");

			if (!std.mem.startsWith(u8, trimmed, "const ")) continue;

			var it = std.mem.tokenizeAny(u8, trimmed["const ".len..], " =;");

			const key = it.next() orelse continue;
			if (!std.mem.eql(u8, key, name)) continue;

			return it.rest();
		}

		return null;
	}

	pub fn number(self: Config, name: []const u8, fallback: f64) f64 {
		const value = self.raw(name) orelse return fallback;
		const end = std.mem.indexOfScalar(u8, value, ';') orelse value.len;

		return std.fmt.parseFloat(f64, std.mem.trim(u8, value[0..end], " \t")) catch fallback;
	}

	pub fn integer(self: Config, name: []const u8, fallback: i64) i64 {
		return @intFromFloat(self.number(name, @floatFromInt(fallback)));
	}

	pub fn string(self: Config, name: []const u8, allocator: Allocator) ?[]u8 {
		const value = self.raw(name) orelse return null;
		const start = std.mem.indexOfScalar(u8, value, '"') orelse return null;
		const end = std.mem.indexOfScalarPos(u8, value, start + 1, '"') orelse return null;

		return allocator.dupe(u8, value[start + 1 .. end]) catch null;
	}

	pub fn strings(self: Config, name: []const u8, allocator: Allocator) ![][]u8 {
		const value = self.raw(name) orelse return &.{};
		const open = std.mem.indexOfScalar(u8, value, '[') orelse return &.{};
		const close = std.mem.indexOfScalarPos(u8, value, open, ']') orelse return &.{};

		var out: std.ArrayList([]u8) = .empty;
		errdefer out.deinit(allocator);

		var index = open + 1;
		while (index < close) {
			const quote = std.mem.indexOfScalarPos(u8, value[0..close], index, '"') orelse break;
			const end = std.mem.indexOfScalarPos(u8, value[0..close], quote + 1, '"') orelse break;

			try out.append(allocator, try allocator.dupe(u8, value[quote + 1 .. end]));
			index = end + 1;
		}

		return out.toOwnedSlice(allocator);
	}
};

test "config reads numbers, strings and lists" {
	const text = "const a = 12;\nconst b = \"celsius\";\nconst c = [\"one\", \"two\"];\nconst d = weatherTempUnit === \"celsius\" ? \"kmh\" : \"mph\";";

	var config = Config{ .allocator = std.testing.allocator, .text = @constCast(text) };
	_ = &config;

	try std.testing.expectEqual(@as(f64, 12), config.number("a", 0));
	try std.testing.expectEqual(@as(f64, 7), config.number("missing", 7));

	const unit = config.string("b", std.testing.allocator).?;
	defer std.testing.allocator.free(unit);
	try std.testing.expectEqualStrings("celsius", unit);

	const list = try config.strings("c", std.testing.allocator);
	defer {
		for (list) |item| std.testing.allocator.free(item);
		std.testing.allocator.free(list);
	}

	try std.testing.expectEqual(@as(usize, 2), list.len);
	try std.testing.expectEqualStrings("two", list[1]);
}
