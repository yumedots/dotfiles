const std = @import("std");
const linux = std.os.linux;

pub fn ms(amount: u64) void {
	var request = linux.timespec{
		.sec = @intCast(amount / 1000),
		.nsec = @intCast((amount % 1000) * std.time.ns_per_ms),
	};

	_ = linux.nanosleep(&request, null);
}

pub fn forever() noreturn {
	while (true) _ = linux.pause();
}
