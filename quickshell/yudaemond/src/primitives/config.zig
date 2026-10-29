const std = @import("std");
const proc = @import("proc.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const Value = union(enum) {
	string: []const u8,
	integer: i64,
	float: f64,
	boolean: bool,
	array: []const Value,
	table: *Table,
};

pub const Entry = struct {
	key: []const u8,
	value: Value,
};

pub const Table = struct {
	entries: std.ArrayListUnmanaged(Entry) = .empty,
};

pub const CodeRow = struct {
	code: i64,
	name: []const u8,
	glyph: []const u8,
};

pub const Config = struct {
	arena: *std.heap.ArenaAllocator,
	root: *Table,

	pub fn load(io: Io, allocator: Allocator) !Config {
		const home = proc.home(io, allocator);
		const path = try std.fmt.allocPrint(allocator, "{s}/.config/quickshell/config.toml", .{home});
		defer allocator.free(path);

		return loadPath(io, allocator, path);
	}

	pub fn loadPath(io: Io, allocator: Allocator, path: []const u8) !Config {
		const body = proc.readFile(io, allocator, path) catch "";
		defer if (body.len > 0) allocator.free(body);

		return parse(allocator, body);
	}

	pub fn parse(allocator: Allocator, text: []const u8) !Config {
		const arena = try allocator.create(std.heap.ArenaAllocator);
		errdefer allocator.destroy(arena);

		arena.* = std.heap.ArenaAllocator.init(allocator);
		errdefer arena.deinit();

		const owned = try arena.allocator().dupe(u8, text);
		var parser = Parser{ .text = owned, .arena = arena.allocator() };
		const root = try parser.document();

		return .{ .arena = arena, .root = root };
	}

	pub fn deinit(self: Config) void {
		const arena = self.arena;
		const child = arena.child_allocator;
		arena.deinit();
		child.destroy(arena);
	}

	fn find(table: *Table, name: []const u8) ?Value {
		for (table.entries.items) |entry| {
			switch (entry.value) {
				.table => |inner| {
					if (find(inner, name)) |value| return value;
				},
				else => {
					if (std.mem.eql(u8, entry.key, name)) return entry.value;
				},
			}
		}

		return null;
	}

	pub fn number(self: Config, name: []const u8, fallback: f64) f64 {
		return switch (find(self.root, name) orelse return fallback) {
			.integer => |value| @floatFromInt(value),
			.float => |value| value,
			.string => |text| std.fmt.parseFloat(f64, text) catch fallback,
			else => fallback,
		};
	}

	pub fn integer(self: Config, name: []const u8, fallback: i64) i64 {
		return switch (find(self.root, name) orelse return fallback) {
			.integer => |value| value,
			.float => |value| @intFromFloat(value),
			.boolean => |value| @intFromBool(value),
			else => fallback,
		};
	}

	pub fn boolean(self: Config, name: []const u8, fallback: bool) bool {
		return switch (find(self.root, name) orelse return fallback) {
			.boolean => |value| value,
			.integer => |value| value != 0,
			else => fallback,
		};
	}

	pub fn string(self: Config, name: []const u8, allocator: Allocator) ?[]u8 {
		return switch (find(self.root, name) orelse return null) {
			.string => |value| allocator.dupe(u8, value) catch null,
			else => null,
		};
	}

	pub fn color(self: Config, name: []const u8) ?[]const u8 {
		return switch (find(self.root, name) orelse return null) {
			.string => |value| value,
			else => null,
		};
	}

	pub fn numbers(self: Config, name: []const u8, allocator: Allocator) ![]i64 {
		const items = switch (find(self.root, name) orelse return &.{}) {
			.array => |items| items,
			else => return &.{},
		};

		var out: std.ArrayList(i64) = .empty;
		errdefer out.deinit(allocator);

		for (items) |item| {
			const value: i64 = switch (item) {
				.integer => |n| n,
				.float => |n| @intFromFloat(n),
				else => continue,
			};

			try out.append(allocator, value);
		}

		return out.toOwnedSlice(allocator);
	}

	pub fn strings(self: Config, name: []const u8, allocator: Allocator) ![][]u8 {
		const items = switch (find(self.root, name) orelse return &.{}) {
			.array => |items| items,
			else => return &.{},
		};

		var out: std.ArrayList([]u8) = .empty;
		errdefer out.deinit(allocator);

		for (items) |item| {
			const text = switch (item) {
				.string => |value| value,
				else => continue,
			};

			try out.append(allocator, try allocator.dupe(u8, text));
		}

		return out.toOwnedSlice(allocator);
	}

	pub fn tableString(self: Config, name: []const u8, index: usize, key: []const u8, allocator: Allocator) ?[]u8 {
		const items = switch (find(self.root, name) orelse return null) {
			.array => |items| items,
			else => return null,
		};

		if (index >= items.len) return null;

		const table = switch (items[index]) {
			.table => |table| table,
			else => return null,
		};

		return switch (find(table, key) orelse return null) {
			.string => |value| allocator.dupe(u8, value) catch null,
			else => null,
		};
	}

	pub fn codeTable(self: Config, name: []const u8, allocator: Allocator) ![]CodeRow {
		const items = switch (find(self.root, name) orelse return &.{}) {
			.array => |items| items,
			else => return &.{},
		};

		var out: std.ArrayList(CodeRow) = .empty;
		errdefer out.deinit(allocator);

		for (items) |item| {
			const table = switch (item) {
				.table => |table| table,
				else => continue,
			};

			const code: i64 = switch (find(table, "code") orelse continue) {
				.integer => |value| value,
				else => continue,
			};
			const label = switch (find(table, "name") orelse continue) {
				.string => |value| value,
				else => continue,
			};
			const glyph = switch (find(table, "glyph") orelse continue) {
				.string => |value| value,
				else => continue,
			};

			try out.append(allocator, .{
				.code = code,
				.name = try allocator.dupe(u8, label),
				.glyph = try allocator.dupe(u8, glyph),
			});
		}

		return out.toOwnedSlice(allocator);
	}

	pub fn render(self: Config, writer: *std.Io.Writer) !void {
		try writer.writeAll("{");

		var first = true;
		try flatten(writer, self.root, &first);

		try writer.writeAll("}");
	}
};

fn flatten(writer: *std.Io.Writer, table: *Table, first: *bool) !void {
	for (table.entries.items) |entry| {
		if (entry.value == .table) {
			try flatten(writer, entry.value.table, first);
			continue;
		}

		if (!first.*) try writer.writeAll(",");
		first.* = false;

		try writeKey(writer, entry.key);
		try writer.writeAll(":");
		try writeValue(writer, entry.value);
	}
}

fn writeKey(writer: *std.Io.Writer, key: []const u8) !void {
	try writer.writeAll("\"");
	for (key) |byte| {
		switch (byte) {
			'"', '\\' => {
				try writer.writeAll("\\");
				try writer.writeByte(byte);
			},
			else => try writer.writeByte(byte),
		}
	}
	try writer.writeAll("\"");
}

fn writeValue(writer: *std.Io.Writer, value: Value) !void {
	switch (value) {
		.string => |text| try writeKey(writer, text),
		.integer => |number_value| try writer.print("{d}", .{number_value}),
		.float => |number_value| try writer.print("{d}", .{number_value}),
		.boolean => |flag| try writer.writeAll(if (flag) "true" else "false"),
		.array => |items| {
			try writer.writeAll("[");
			for (items, 0..) |item, index| {
				if (index > 0) try writer.writeAll(",");
				try writeValue(writer, item);
			}
			try writer.writeAll("]");
		},
		.table => |inner| {
			try writer.writeAll("{");

			var first = true;
			for (inner.entries.items) |entry| {
				if (!first) try writer.writeAll(",");
				first = false;

				try writeKey(writer, entry.key);
				try writer.writeAll(":");
				try writeValue(writer, entry.value);
			}

			try writer.writeAll("}");
		},
	}
}

const Error = error{ InvalidToml, OutOfMemory };

const Parser = struct {
	text: []const u8,
	pos: usize = 0,
	arena: Allocator,

	fn skip(self: *Parser) void {
		while (self.pos < self.text.len) {
			switch (self.text[self.pos]) {
				' ', '\t', '\r', '\n' => self.pos += 1,
				'#' => {
					while (self.pos < self.text.len and self.text[self.pos] != '\n') self.pos += 1;
				},
				else => return,
			}
		}
	}

	fn skipInline(self: *Parser) void {
		while (self.pos < self.text.len and (self.text[self.pos] == ' ' or self.text[self.pos] == '\t')) self.pos += 1;
	}

	fn document(self: *Parser) Error!*Table {
		const root = try self.arena.create(Table);
		root.* = .{};

		var current = root;

		while (true) {
			self.skip();
			if (self.pos >= self.text.len) break;

			if (self.text[self.pos] == '[') {
				self.pos += 1;
				if (self.pos < self.text.len and self.text[self.pos] == '[') return error.InvalidToml;

				current = try self.section(root);

				self.skipInline();
				if (self.pos >= self.text.len or self.text[self.pos] != ']') return error.InvalidToml;
				self.pos += 1;
				continue;
			}

			const name = try self.key();
			self.skipInline();

			if (self.pos >= self.text.len or self.text[self.pos] != '=') return error.InvalidToml;
			self.pos += 1;

			const parsed = try self.value();

			for (current.entries.items) |*entry| {
				if (!std.mem.eql(u8, entry.key, name)) continue;
				entry.value = parsed;
				break;
			} else {
				try current.entries.append(self.arena, .{ .key = name, .value = parsed });
			}
		}

		return root;
	}

	fn section(self: *Parser, root: *Table) Error!*Table {
		var current = root;

		while (true) {
			self.skipInline();
			const name = try self.key();
			current = try self.child(current, name);

			self.skipInline();
			if (self.pos < self.text.len and self.text[self.pos] == '.') {
				self.pos += 1;
				continue;
			}

			return current;
		}
	}

	fn child(self: *Parser, parent: *Table, name: []const u8) Error!*Table {
		for (parent.entries.items) |*entry| {
			if (!std.mem.eql(u8, entry.key, name)) continue;

			return switch (entry.value) {
				.table => |inner| inner,
				else => error.InvalidToml,
			};
		}

		const inner = try self.arena.create(Table);
		inner.* = .{};
		try parent.entries.append(self.arena, .{ .key = name, .value = .{ .table = inner } });

		return inner;
	}

	fn key(self: *Parser) Error![]const u8 {
		if (self.pos < self.text.len and (self.text[self.pos] == '"' or self.text[self.pos] == '\'')) {
			return self.string();
		}

		const start = self.pos;

		while (self.pos < self.text.len) {
			const byte = self.text[self.pos];
			if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '-') break;
			self.pos += 1;
		}

		if (self.pos == start) return error.InvalidToml;

		return self.text[start..self.pos];
	}

	fn value(self: *Parser) Error!Value {
		self.skipInline();
		if (self.pos >= self.text.len) return error.InvalidToml;

		return switch (self.text[self.pos]) {
			'"', '\'' => .{ .string = try self.string() },
			'[' => self.array(),
			'{' => self.table(),
			else => self.scalar(),
		};
	}

	fn array(self: *Parser) Error!Value {
		self.pos += 1;

		var items: std.ArrayListUnmanaged(Value) = .empty;

		while (true) {
			self.skip();
			if (self.pos >= self.text.len) return error.InvalidToml;

			if (self.text[self.pos] == ']') {
				self.pos += 1;
				break;
			}

			try items.append(self.arena, try self.value());

			self.skip();
			if (self.pos < self.text.len and self.text[self.pos] == ',') {
				self.pos += 1;
				continue;
			}
		}

		return .{ .array = items.items };
	}

	fn table(self: *Parser) Error!Value {
		self.pos += 1;

		const inner = try self.arena.create(Table);
		inner.* = .{};

		while (true) {
			self.skip();
			if (self.pos >= self.text.len) return error.InvalidToml;

			if (self.text[self.pos] == '}') {
				self.pos += 1;
				break;
			}

			const name = try self.key();
			self.skipInline();

			if (self.pos >= self.text.len or self.text[self.pos] != '=') return error.InvalidToml;
			self.pos += 1;

			try inner.entries.append(self.arena, .{ .key = name, .value = try self.value() });

			self.skip();
			if (self.pos < self.text.len and self.text[self.pos] == ',') {
				self.pos += 1;
				continue;
			}
		}

		return .{ .table = inner };
	}

	fn scalar(self: *Parser) Error!Value {
		const start = self.pos;

		while (self.pos < self.text.len) {
			const byte = self.text[self.pos];
			if (!std.ascii.isAlphanumeric(byte) and byte != '.' and byte != '+' and byte != '-') break;
			self.pos += 1;
		}

		const text = self.text[start..self.pos];
		if (text.len == 0) return error.InvalidToml;

		if (std.mem.eql(u8, text, "true")) return .{ .boolean = true };
		if (std.mem.eql(u8, text, "false")) return .{ .boolean = false };

		if (std.mem.indexOfAny(u8, text, ".eE") != null) {
			return .{ .float = std.fmt.parseFloat(f64, text) catch return error.InvalidToml };
		}

		return .{ .integer = std.fmt.parseInt(i64, text, 10) catch return error.InvalidToml };
	}

	fn string(self: *Parser) Error![]const u8 {
		const quote = self.text[self.pos];
		self.pos += 1;

		var out: std.ArrayListUnmanaged(u8) = .empty;

		while (true) {
			if (self.pos >= self.text.len) return error.InvalidToml;

			const byte = self.text[self.pos];

			if (byte == quote) {
				self.pos += 1;
				break;
			}

			if (byte == '\n') return error.InvalidToml;

			if (byte != '\\' or quote == '\'') {
				try out.append(self.arena, byte);
				self.pos += 1;
				continue;
			}

			self.pos += 1;
			if (self.pos >= self.text.len) return error.InvalidToml;

			const escape = self.text[self.pos];
			self.pos += 1;

			switch (escape) {
				'"' => try out.append(self.arena, '"'),
				'\\' => try out.append(self.arena, '\\'),
				'n' => try out.append(self.arena, '\n'),
				't' => try out.append(self.arena, '\t'),
				'r' => try out.append(self.arena, '\r'),
				'b' => try out.append(self.arena, 0x08),
				'f' => try out.append(self.arena, 0x0c),
				'u' => try self.hex(&out, 4),
				'U' => try self.hex(&out, 8),
				else => return error.InvalidToml,
			}
		}

		return out.items;
	}

	fn hex(self: *Parser, out: *std.ArrayListUnmanaged(u8), digits: usize) Error!void {
		if (self.pos + digits > self.text.len) return error.InvalidToml;

		const point = std.fmt.parseInt(u21, self.text[self.pos .. self.pos + digits], 16) catch return error.InvalidToml;
		self.pos += digits;

		var buffer: [4]u8 = undefined;
		const length = std.unicode.utf8Encode(point, &buffer) catch return error.InvalidToml;

		try out.appendSlice(self.arena, buffer[0..length]);
	}
};

test "sections, comments and every scalar type" {
	const text =
		"# a comment\n" ++
		"[colors]\n" ++
		"surface = \"#101010\"  # trailing comment\n" ++
		"alpha = 1\n" ++
		"scale = 1.5\n" ++
		"mono = true\n" ++
		"name = 'literal # not a comment'\n" ++
		"\n" ++
		"[bar]\n" ++
		"cells = 15\n" ++
		"quiet = false\n";

	const cfg = try Config.parse(std.testing.allocator, text);
	defer cfg.deinit();

	try std.testing.expectEqualStrings("#101010", cfg.color("surface").?);
	try std.testing.expectEqual(@as(f64, 1), cfg.number("alpha", 0));
	try std.testing.expectEqual(@as(f64, 1.5), cfg.number("scale", 0));
	try std.testing.expect(cfg.boolean("mono", false));
	try std.testing.expect(!cfg.boolean("quiet", true));
	try std.testing.expectEqualStrings("literal # not a comment", cfg.color("name").?);
	try std.testing.expectEqual(@as(i64, 15), cfg.integer("cells", 0));
	try std.testing.expectEqual(@as(f64, 7), cfg.number("missing", 7));
	try std.testing.expectEqual(@as(i64, -1), cfg.integer("missing", -1));
	try std.testing.expect(!cfg.boolean("missing", false));
	try std.testing.expect(cfg.boolean("missing", true));
	try std.testing.expectEqual(@as(?[]const u8, null), cfg.color("missing"));

	const name = cfg.string("missing", std.testing.allocator);
	try std.testing.expectEqual(@as(?[]u8, null), name);
}

test "escapes decode glyphs and quotes" {
	const text =
		"[icons]\n" ++
		"close = \"\\uF00D\"\n" ++
		"wide = \"\\U000F0599\"\n" ++
		"quoted = \"say \\\"hi\\\"\"\n" ++
		"slashed = \"a\\\\b\"\n";

	const cfg = try Config.parse(std.testing.allocator, text);
	defer cfg.deinit();

	try std.testing.expectEqualStrings("\u{f00d}", cfg.color("close").?);
	try std.testing.expectEqualStrings("\u{f0599}", cfg.color("wide").?);
	try std.testing.expectEqualStrings("say \"hi\"", cfg.color("quoted").?);
	try std.testing.expectEqualStrings("a\\b", cfg.color("slashed").?);
}

test "arrays hold strings, numbers and tables" {
	const text =
		"[network]\n" ++
		"icons = [\"a\", \"b\",]\n" ++
		"fonts = [\n\t10,\n\t11,\n]\n" ++
		"actions = [\n\t{ name = \"Suspend\", glyph = \"\\uF04B2\" },\n\t{ name = \"Reboot\", glyph = \"\\uEAD2\" },\n]\n" ++
		"codes = [\n\t{ code = 0, name = \"Clear\", glyph = \"\\U000F0599\" },\n]\n";

	const cfg = try Config.parse(std.testing.allocator, text);
	defer cfg.deinit();

	const icons = try cfg.strings("icons", std.testing.allocator);
	defer {
		for (icons) |item| std.testing.allocator.free(item);
		std.testing.allocator.free(icons);
	}

	try std.testing.expectEqual(@as(usize, 2), icons.len);
	try std.testing.expectEqualStrings("b", icons[1]);

	const fonts = try cfg.numbers("fonts", std.testing.allocator);
	defer std.testing.allocator.free(fonts);

	try std.testing.expectEqual(@as(usize, 2), fonts.len);
	try std.testing.expectEqual(@as(i64, 11), fonts[1]);

	const rows = try cfg.codeTable("codes", std.testing.allocator);
	defer {
		for (rows) |row| {
			std.testing.allocator.free(row.name);
			std.testing.allocator.free(row.glyph);
		}
		std.testing.allocator.free(rows);
	}

	try std.testing.expectEqual(@as(usize, 1), rows.len);
	try std.testing.expectEqual(@as(i64, 0), rows[0].code);
	try std.testing.expectEqualStrings("Clear", rows[0].name);
	try std.testing.expectEqualStrings("\u{f0599}", rows[0].glyph);

	try std.testing.expectEqual(@as(usize, 0), (try cfg.strings("missing", std.testing.allocator)).len);
	try std.testing.expectEqual(@as(usize, 0), (try cfg.numbers("missing", std.testing.allocator)).len);
	try std.testing.expectEqual(@as(usize, 0), (try cfg.codeTable("missing", std.testing.allocator)).len);
}

test "unknown keys are kept out of the way and a missing file leaves every default" {
	const text =
		"[colors]\n" ++
		"surface = \"#101010\"\n" ++
		"[tuning]\n" ++
		"unknownKnob = 9\n";

	const cfg = try Config.parse(std.testing.allocator, text);
	defer cfg.deinit();

	try std.testing.expectEqualStrings("#101010", cfg.color("surface").?);
	try std.testing.expectEqual(@as(f64, 9), cfg.number("unknownKnob", 0));

	const empty = try Config.parse(std.testing.allocator, "");
	defer empty.deinit();

	try std.testing.expectEqual(@as(?[]const u8, null), empty.color("surface"));
	try std.testing.expectEqual(@as(i64, 15), empty.integer("barCells", 15));
	try std.testing.expectEqual(@as(f64, 320), empty.number("workspaceMorphMs", 320));
	try std.testing.expect(empty.boolean("mono", true));

	try std.testing.expectError(error.InvalidToml, Config.parse(std.testing.allocator, "broken = "));
}

test "the snapshot renders every key once" {
	const text =
		"[colors]\n" ++
		"surface = \"#101010\"\n" ++
		"alpha = 1\n" ++
		"scale = 1.5\n" ++
		"mono = true\n" ++
		"[tray]\n" ++
		"icons = [\"a\", \"b\"]\n" ++
		"actions = [{ name = \"Suspend\" }]\n";

	const cfg = try Config.parse(std.testing.allocator, text);
	defer cfg.deinit();

	var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
	defer out.deinit();

	try cfg.render(&out.writer);

	const body = out.written();

	try std.testing.expect(std.mem.startsWith(u8, body, "{"));
	try std.testing.expect(std.mem.endsWith(u8, body, "}"));

	const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, body, .{});
	defer parsed.deinit();

	const object = parsed.value.object;

	try std.testing.expectEqualStrings("#101010", object.get("surface").?.string);
	try std.testing.expectEqual(@as(i64, 1), object.get("alpha").?.integer);
	try std.testing.expectEqual(@as(f64, 1.5), object.get("scale").?.float);
	try std.testing.expect(object.get("mono").?.bool);
	try std.testing.expectEqual(@as(usize, 2), object.get("icons").?.array.items.len);
	try std.testing.expectEqualStrings("Suspend", object.get("actions").?.array.items[0].object.get("name").?.string);
	try std.testing.expectEqual(@as(usize, 6), object.count());
}
