const std = @import("std");

pub const Tier = enum {
	hot,
	warm,
	parked,
	off,

	pub fn text(self: Tier) []const u8 {
		return switch (self) {
			.hot => "hot",
			.warm => "warm",
			.parked => "parked",
			.off => "off",
		};
	}
};
