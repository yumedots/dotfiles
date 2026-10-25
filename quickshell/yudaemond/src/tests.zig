const std = @import("std");

test {
	_ = @import("primitives/json.zig");
	_ = @import("primitives/fmt.zig");
	_ = @import("primitives/http.zig");
	_ = @import("primitives/proc.zig");
	_ = @import("primitives/watch.zig");
	_ = @import("primitives/sock.zig");
	_ = @import("ipc.zig");
	_ = @import("providers/opencode.zig");
	_ = @import("providers/codex.zig");
	_ = @import("providers/cursor.zig");
	_ = @import("providers/daemon.zig");
	_ = @import("providers/github.zig");
	_ = @import("providers/weather.zig");
	_ = @import("providers/system.zig");
	_ = @import("providers/apps.zig");
	_ = @import("providers/screen.zig");
	_ = @import("providers/settings.zig");
	_ = @import("providers/network.zig");
	_ = @import("primitives/hypr.zig");
	_ = @import("primitives/config.zig");
	_ = @import("cli.zig");
	_ = @import("bench.zig");
	_ = @import("parity.zig");
	_ = @import("mcp.zig");
	_ = @import("primitives/exec.zig");
}
