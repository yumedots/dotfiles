const std = @import("std");

const Allocator = std.mem.Allocator;

pub const Entry = struct {
	value: []u8,
	text: []u8,
};

pub fn evaluate(arena: Allocator, query: []const u8) ?Entry {
	const trimmed = std.mem.trim(u8, query, " \t\r\n");

	if (!hasDigit(trimmed)) return null;

	const expression = strip(arena, trimmed) catch return null;
	const result = calculate(expression) orelse return null;
	const value = format(arena, result) catch return null;

	if (std.mem.eql(u8, value, trimmed)) return null;

	const text = std.fmt.allocPrint(arena, "{s} = {s}", .{ trimmed, value }) catch return null;

	return .{ .value = value, .text = text };
}

fn hasDigit(text: []const u8) bool {
	for (text) |character| {
		if (std.ascii.isDigit(character)) return true;
	}

	return false;
}

fn strip(arena: Allocator, text: []const u8) ![]const u8 {
	var out: std.ArrayList(u8) = .empty;
	errdefer out.deinit(arena);

	for (text) |character| {
		if (std.ascii.isWhitespace(character)) continue;
		try out.append(arena, character);
	}

	return out.toOwnedSlice(arena);
}

fn calculate(text: []const u8) ?f64 {
	var parser: Parser = .{ .text = text };
	const result = parser.expression() orelse return null;

	if (parser.at != text.len) return null;
	if (!std.math.isFinite(result)) return null;

	return result;
}

const Parser = struct {
	text: []const u8,
	at: usize = 0,

	fn eat(self: *Parser, character: u8) bool {
		if (self.at < self.text.len and self.text[self.at] == character) {
			self.at += 1;
			return true;
		}

		return false;
	}

	fn expression(self: *Parser) ?f64 {
		var value = self.term() orelse return null;

		while (true) {
			if (self.eat('+')) {
				const right = self.term() orelse return null;
				value += right;
			} else if (self.eat('-')) {
				const right = self.term() orelse return null;
				value -= right;
			} else {
				return value;
			}
		}
	}

	fn term(self: *Parser) ?f64 {
		var value = self.power() orelse return null;

		while (true) {
			if (self.eat('*')) {
				const right = self.power() orelse return null;
				value *= right;
			} else if (self.eat('/')) {
				const right = self.power() orelse return null;
				if (right == 0) return null;
				value /= right;
			} else if (self.eat('%')) {
				const right = self.power() orelse return null;
				if (right == 0) return null;
				value = @rem(value, right);
			} else {
				return value;
			}
		}
	}

	fn power(self: *Parser) ?f64 {
		const base = self.unary() orelse return null;

		if (!self.eat('^')) return base;

		const exponent = self.power() orelse return null;

		return std.math.pow(f64, base, exponent);
	}

	fn unary(self: *Parser) ?f64 {
		if (self.eat('-')) {
			const value = self.unary() orelse return null;
			return -value;
		}

		if (self.eat('+')) return self.unary();

		return self.atom();
	}

	fn atom(self: *Parser) ?f64 {
		if (self.eat('(')) {
			const value = self.expression() orelse return null;
			return if (self.eat(')')) value else null;
		}

		if (self.at < self.text.len and std.ascii.isAlphabetic(self.text[self.at])) {
			const start = self.at;

			while (self.at < self.text.len and std.ascii.isAlphabetic(self.text[self.at])) self.at += 1;

			const word = self.text[start..self.at];

			if (self.eat('(')) {
				const argument = self.expression() orelse return null;
				if (!self.eat(')')) return null;

				return apply(word, argument);
			}

			if (std.mem.eql(u8, word, "pi")) return std.math.pi;
			if (std.mem.eql(u8, word, "e")) return std.math.e;

			return null;
		}

		return self.number();
	}

	fn number(self: *Parser) ?f64 {
		const start = self.at;
		var index = start;

		while (index < self.text.len and std.ascii.isDigit(self.text[index])) index += 1;

		var end = index;

		if (index < self.text.len and self.text[index] == '.') {
			var after = index + 1;

			while (after < self.text.len and std.ascii.isDigit(self.text[after])) after += 1;
			if (after > index + 1) end = after;
		}

		if (end == start) return null;

		self.at = end;

		return std.fmt.parseFloat(f64, self.text[start..end]) catch null;
	}
};

fn apply(word: []const u8, argument: f64) ?f64 {
	if (std.mem.eql(u8, word, "sqrt")) return std.math.sqrt(argument);
	if (std.mem.eql(u8, word, "abs")) return @abs(argument);
	if (std.mem.eql(u8, word, "round")) return roundHalfUp(argument);
	if (std.mem.eql(u8, word, "floor")) return @floor(argument);
	if (std.mem.eql(u8, word, "ceil")) return @ceil(argument);

	return null;
}

fn roundHalfUp(value: f64) f64 {
	return if (value >= 0) @floor(value + 0.5) else -@floor(-value + 0.5);
}

fn format(arena: Allocator, value: f64) ![]u8 {
	if (!std.math.isFinite(value)) return error.NotFinite;

	const rounded = roundHalfUp(value * 1_000_000.0) / 1_000_000.0;

	return std.fmt.allocPrint(arena, "{d}", .{if (rounded == 0) @as(f64, 0) else rounded});
}

fn expectValue(query: []const u8, value: []const u8, text: []const u8) !void {
	var backing = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer backing.deinit();

	const entry = evaluate(backing.allocator(), query) orelse return error.ExpectedEntry;

	try std.testing.expectEqualStrings(value, entry.value);
	try std.testing.expectEqualStrings(text, entry.text);
}

fn expectRejected(query: []const u8) !void {
	var backing = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer backing.deinit();

	try std.testing.expect(evaluate(backing.allocator(), query) == null);
}

test "calc follows arithmetic precedence" {
	try expectValue("2+3*4", "14", "2+3*4 = 14");
	try expectValue("10-4/2", "8", "10-4/2 = 8");
	try expectValue("7%4", "3", "7%4 = 3");
}

test "calc honours parentheses" {
	try expectValue("(2+3)*4", "20", "(2+3)*4 = 20");
	try expectValue("2*(3+(4-1))", "12", "2*(3+(4-1)) = 12");
}

test "calc power is right associative" {
	try expectValue("2^3^2", "512", "2^3^2 = 512");
	try expectValue("(2^3)^2", "64", "(2^3)^2 = 64");
}

test "calc handles unary signs" {
	try expectValue("-5+10", "5", "-5+10 = 5");
	try expectValue("--5", "5", "--5 = 5");
	try expectValue("3*-2", "-6", "3*-2 = -6");
}

test "calc applies every function" {
	try expectValue("sqrt(16)", "4", "sqrt(16) = 4");
	try expectValue("abs(-3)", "3", "abs(-3) = 3");
	try expectValue("round(2.5)", "3", "round(2.5) = 3");
	try expectValue("floor(2.9)", "2", "floor(2.9) = 2");
	try expectValue("ceil(2.1)", "3", "ceil(2.1) = 3");
}

test "calc knows pi and e" {
	try expectValue("pi*1", "3.141593", "pi*1 = 3.141593");
	try expectValue("e*1", "2.718282", "e*1 = 2.718282");
	try expectValue("round(pi*2)", "6", "round(pi*2) = 6");
}

test "calc ignores whitespace" {
	try expectValue(" 1 + 2 * 3 ", "7", "1 + 2 * 3 = 7");
	try expectValue("sqrt( 9 )", "3", "sqrt( 9 ) = 3");
}

test "calc renders a launcher line" {
	try expectValue("2+2", "4", "2+2 = 4");
	try expectValue(" 2 + 2 ", "4", "2 + 2 = 4");
	try expectValue("2 + 2", "4", "2 + 2 = 4");
	try expectValue("1/3", "0.333333", "1/3 = 0.333333");
	try expectValue("1.5*2", "3", "1.5*2 = 3");
}

test "calc rejects what is not arithmetic" {
	try expectRejected("firefox");
	try expectRejected("2+");
	try expectRejected("1/0");
	try expectRejected("2 + 2 =");
	try expectRejected("");
	try expectRejected("   ");
	try expectRejected("4");
	try expectRejected("(2+3");
	try expectRejected("2^");
	try expectRejected("9^9999");
	try expectRejected("sqrt(-1)");
}
