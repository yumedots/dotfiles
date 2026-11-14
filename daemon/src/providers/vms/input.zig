const std = @import("std");

pub const Key = struct {
	code: []const u8,
	shift: bool = false,
};

const Hardware = struct {
	name: []const u8,
	qcode: []const u8,
};

const hardware = [_]Hardware{
	.{ .name = "xf86audioraisevolume", .qcode = "volumeup" },
	.{ .name = "xf86volumeup", .qcode = "volumeup" },
	.{ .name = "volumeup", .qcode = "volumeup" },
	.{ .name = "volup", .qcode = "volumeup" },
	.{ .name = "raisevolume", .qcode = "volumeup" },
	.{ .name = "xf86audiolowervolume", .qcode = "volumedown" },
	.{ .name = "xf86volumedown", .qcode = "volumedown" },
	.{ .name = "volumedown", .qcode = "volumedown" },
	.{ .name = "voldown", .qcode = "volumedown" },
	.{ .name = "lowervolume", .qcode = "volumedown" },
	.{ .name = "xf86audiomute", .qcode = "audiomute" },
	.{ .name = "audiomute", .qcode = "audiomute" },
	.{ .name = "mute", .qcode = "audiomute" },
	.{ .name = "togglemute", .qcode = "audiomute" },
	.{ .name = "xf86audionext", .qcode = "audionext" },
	.{ .name = "audionext", .qcode = "audionext" },
	.{ .name = "nextsong", .qcode = "audionext" },
	.{ .name = "nexttrack", .qcode = "audionext" },
	.{ .name = "xf86audioprev", .qcode = "audioprev" },
	.{ .name = "audioprev", .qcode = "audioprev" },
	.{ .name = "previoussong", .qcode = "audioprev" },
	.{ .name = "previoustrack", .qcode = "audioprev" },
	.{ .name = "xf86audioplay", .qcode = "audioplay" },
	.{ .name = "audioplay", .qcode = "audioplay" },
	.{ .name = "xf86audiopause", .qcode = "audioplay" },
	.{ .name = "playpause", .qcode = "audioplay" },
	.{ .name = "xf86audiostop", .qcode = "audiostop" },
	.{ .name = "audiostop", .qcode = "audiostop" },
	.{ .name = "stopcd", .qcode = "audiostop" },
	.{ .name = "xf86mail", .qcode = "mail" },
	.{ .name = "mail", .qcode = "mail" },
	.{ .name = "xf86calculator", .qcode = "calculator" },
	.{ .name = "calculator", .qcode = "calculator" },
	.{ .name = "xf86forward", .qcode = "forward" },
	.{ .name = "forward", .qcode = "forward" },
	.{ .name = "xf86print", .qcode = "print" },
	.{ .name = "print", .qcode = "print" },
	.{ .name = "sysrq", .qcode = "sysrq" },
	.{ .name = "super", .qcode = "meta_l" },
	.{ .name = "superl", .qcode = "meta_l" },
	.{ .name = "metaleft", .qcode = "meta_l" },
	.{ .name = "metaright", .qcode = "meta_r" },
	.{ .name = "compose", .qcode = "compose" },
};

pub fn hardwareOf(name: []const u8) ?[]const u8 {
	for (hardware) |entry| {
		if (sameName(name, entry.name)) return entry.qcode;
	}

	return null;
}

fn sameName(name: []const u8, known: []const u8) bool {
	var index: usize = 0;
	var known_index: usize = 0;

	while (true) {
		while (index < name.len and separator(name[index])) index += 1;
		if (index >= name.len) break;
		if (known_index >= known.len) return false;
		if (std.ascii.toLower(name[index]) != known[known_index]) return false;

		index += 1;
		known_index += 1;
	}

	return known_index == known.len;
}

fn separator(byte: u8) bool {
	return byte == '-' or byte == '_' or byte == '.' or byte == ' ';
}

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

test "hardware names ignore case and separators" {
	try std.testing.expectEqualStrings("volumeup", hardwareOf("XF86AudioRaiseVolume").?);
	try std.testing.expectEqualStrings("volumeup", hardwareOf("volume-up").?);
	try std.testing.expectEqualStrings("volumedown", hardwareOf("volume_down").?);
	try std.testing.expectEqualStrings("audiomute", hardwareOf("Mute").?);
	try std.testing.expectEqualStrings("meta_l", hardwareOf("Super_L").?);
	try std.testing.expect(hardwareOf("a") == null);
	try std.testing.expect(hardwareOf("raisevolumeup") == null);
}
