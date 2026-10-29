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

	pub fn boolean(self: Config, name: []const u8, fallback: bool) bool {
		const value = self.raw(name) orelse return fallback;
		const end = std.mem.indexOfScalar(u8, value, ';') orelse value.len;

		return std.mem.eql(u8, std.mem.trim(u8, value[0..end], " \t"), "true");
	}

	pub fn numbers(self: Config, name: []const u8, allocator: Allocator) ![]i64 {
		const value = self.raw(name) orelse return &.{};
		const open = std.mem.indexOfScalar(u8, value, '[') orelse return &.{};
		const close = std.mem.indexOfScalarPos(u8, value, open, ']') orelse return &.{};

		var out: std.ArrayList(i64) = .empty;
		errdefer out.deinit(allocator);

		var parts = std.mem.tokenizeAny(u8, value[open + 1 .. close], " ,\t");
		while (parts.next()) |part| {
			const parsed = std.fmt.parseInt(i64, part, 10) catch continue;
			try out.append(allocator, parsed);
		}

		return out.toOwnedSlice(allocator);
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

	pub fn codeTable(self: Config, name: []const u8, allocator: Allocator) ![]CodeRow {
		var out: std.ArrayList(CodeRow) = .empty;
		errdefer out.deinit(allocator);

		var inside = false;
		var lines = std.mem.splitScalar(u8, self.text, '\n');

		while (lines.next()) |line| {
			const trimmed = std.mem.trim(u8, line, " \t\r");

			if (!inside) {
				if (!std.mem.startsWith(u8, trimmed, "const ")) continue;

				var it = std.mem.tokenizeAny(u8, trimmed["const ".len..], " =;");
				const key = it.next() orelse continue;
				if (!std.mem.eql(u8, key, name)) continue;

				inside = std.mem.indexOfScalar(u8, trimmed, '{') != null;
				continue;
			}

			if (std.mem.startsWith(u8, trimmed, "}")) break;

			const colon = std.mem.indexOfScalar(u8, trimmed, ':') orelse continue;
			const code = std.fmt.parseInt(i64, std.mem.trim(u8, trimmed[0..colon], " \t"), 10) catch continue;

			var quoted: [2][]const u8 = undefined;
			var count: usize = 0;
			var at: usize = colon + 1;

			while (count < quoted.len) {
				const open = std.mem.indexOfScalarPos(u8, trimmed, at, '"') orelse break;
				const close = std.mem.indexOfScalarPos(u8, trimmed, open + 1, '"') orelse break;

				quoted[count] = trimmed[open + 1 .. close];
				count += 1;
				at = close + 1;
			}

			if (count < quoted.len) continue;

			try out.append(allocator, .{
				.code = code,
				.name = try unescape(allocator, quoted[0]),
				.glyph = try unescape(allocator, quoted[1]),
			});
		}

		return out.toOwnedSlice(allocator);
	}
};

pub const CodeRow = struct {
	code: i64,
	name: []const u8,
	glyph: []const u8,
};

pub fn unescape(allocator: Allocator, text: []const u8) ![]const u8 {
	var out: std.ArrayList(u8) = .empty;
	errdefer out.deinit(allocator);

	var index: usize = 0;

	while (index < text.len) {
		const escaped = text[index] == '\\' and index + 2 < text.len and text[index + 1] == 'u' and text[index + 2] == '{';

		if (!escaped) {
			try out.append(allocator, text[index]);
			index += 1;
			continue;
		}

		const close = std.mem.indexOfScalarPos(u8, text, index + 3, '}') orelse break;
		const point = std.fmt.parseInt(u21, text[index + 3 .. close], 16) catch break;

		var buffer: [4]u8 = undefined;
		const length = std.unicode.utf8Encode(point, &buffer) catch break;

		try out.appendSlice(allocator, buffer[0..length]);
		index = close + 1;
	}

	return out.toOwnedSlice(allocator);
}

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

test "config reads a code table" {
	const text = "const weatherCodes = {\n" ++
		"\t0: { name: \"Clear\", glyph: \"\\u{f0599}\" },\n" ++
		"\t95: { name: \"Thunderstorm\", glyph: \"\\u{f0593}\" }\n" ++
		"};\n" ++
		"const after = 1;\n";

	var config = Config{ .allocator = std.testing.allocator, .text = @constCast(text) };
	_ = &config;

	const rows = try config.codeTable("weatherCodes", std.testing.allocator);
	defer {
		for (rows) |row| {
			std.testing.allocator.free(row.name);
			std.testing.allocator.free(row.glyph);
		}
		std.testing.allocator.free(rows);
	}

	try std.testing.expectEqual(@as(usize, 2), rows.len);
	try std.testing.expectEqual(@as(i64, 0), rows[0].code);
	try std.testing.expectEqualStrings("Clear", rows[0].name);
	try std.testing.expectEqualStrings("\u{f0599}", rows[0].glyph);
	try std.testing.expectEqual(@as(i64, 95), rows[1].code);
	try std.testing.expectEqualStrings("Thunderstorm", rows[1].name);

	try std.testing.expectEqual(@as(usize, 0), (try config.codeTable("missing", std.testing.allocator)).len);
}

