const std = @import("std");

pub const Key = struct {
	code: []const u8,
	shift: bool = false,
};

pub fn keyOf(char: u8) ?Key {
	if (char >= 'a' and char <= 'z') return .{ .code = letter(char) };
	if (char >= 'A' and char <= 'Z') return .{ .code = letter(char + 32), .shift = true };
	if (char >= '0' and char <= '9') return .{ .code = digit(char) };

	return switch (char) {
		' ' => .{ .code = "spc" },
		'\n', '\r' => .{ .code = "ret" },
		'\t' => .{ .code = "tab" },
		'-' => .{ .code = "minus" },
		'=' => .{ .code = "equal" },
		'[' => .{ .code = "bracket_left" },
		']' => .{ .code = "bracket_right" },
		'\\' => .{ .code = "backslash" },
		';' => .{ .code = "semicolon" },
		'\'' => .{ .code = "apostrophe" },
		'`' => .{ .code = "grave_accent" },
		',' => .{ .code = "comma" },
		'.' => .{ .code = "dot" },
		'/' => .{ .code = "slash" },
		'!' => .{ .code = "1", .shift = true },
		'@' => .{ .code = "2", .shift = true },
		'#' => .{ .code = "3", .shift = true },
		'$' => .{ .code = "4", .shift = true },
		'%' => .{ .code = "5", .shift = true },
		'^' => .{ .code = "6", .shift = true },
		'&' => .{ .code = "7", .shift = true },
		'*' => .{ .code = "8", .shift = true },
		'(' => .{ .code = "9", .shift = true },
		')' => .{ .code = "0", .shift = true },
		'_' => .{ .code = "minus", .shift = true },
		'+' => .{ .code = "equal", .shift = true },
		'{' => .{ .code = "bracket_left", .shift = true },
		'}' => .{ .code = "bracket_right", .shift = true },
		'|' => .{ .code = "backslash", .shift = true },
		':' => .{ .code = "semicolon", .shift = true },
		'"' => .{ .code = "apostrophe", .shift = true },
		'~' => .{ .code = "grave_accent", .shift = true },
		'<' => .{ .code = "comma", .shift = true },
		'>' => .{ .code = "dot", .shift = true },
		'?' => .{ .code = "slash", .shift = true },
		else => null,
	};
}

fn letter(char: u8) []const u8 {
	return switch (char) {
		'a' => "a",
		'b' => "b",
		'c' => "c",
		'd' => "d",
		'e' => "e",
		'f' => "f",
		'g' => "g",
		'h' => "h",
		'i' => "i",
		'j' => "j",
		'k' => "k",
		'l' => "l",
		'm' => "m",
		'n' => "n",
		'o' => "o",
		'p' => "p",
		'q' => "q",
		'r' => "r",
		's' => "s",
		't' => "t",
		'u' => "u",
		'v' => "v",
		'w' => "w",
		'x' => "x",
		'y' => "y",
		'z' => "z",
		else => "",
	};
}

fn digit(char: u8) []const u8 {
	return switch (char) {
		'0' => "0",
		'1' => "1",
		'2' => "2",
		'3' => "3",
		'4' => "4",
		'5' => "5",
		'6' => "6",
		'7' => "7",
		'8' => "8",
		'9' => "9",
		else => "",
	};
}

test "shifted punctuation carries the shift" {
	try std.testing.expectEqualStrings("1", keyOf('!').?.code);
	try std.testing.expect(keyOf('!').?.shift);
	try std.testing.expectEqualStrings("a", keyOf('A').?.code);
	try std.testing.expect(keyOf('A').?.shift);
}
