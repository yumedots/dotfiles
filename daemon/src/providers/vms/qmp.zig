const std = @import("std");
const sock = @import("../../primitives/sock.zig");
const json = @import("../../primitives/json.zig");

const Allocator = std.mem.Allocator;

pub const Qmp = struct {
    connection: sock.Connection,
    buffer: [256 * 1024]u8 = undefined,

    pub fn init(self: *Qmp, path: []const u8) !void {
        self.connection = try sock.Connection.connect(path, &self.buffer);
        _ = try self.connection.readLine() orelse return error.NoGreeting;
        _ = try self.execute(null, "qmp_capabilities", null);
    }

    pub fn close(self: *Qmp) void {
        self.connection.close();
    }

    pub fn execute(self: *Qmp, allocator: ?Allocator, command: []const u8, arguments: ?[]const u8) ![]const u8 {
        const gpa = allocator orelse std.heap.smp_allocator;

        var out: std.Io.Writer.Allocating = .init(gpa);
        defer out.deinit();
        const writer = &out.writer;

        try writer.writeAll("{\"execute\":");
        try std.json.Stringify.encodeJsonString(command, .{}, writer);

        if (arguments) |body| {
            try writer.writeAll(",\"arguments\":");
            try writer.writeAll(body);
        }

        try writer.writeAll("}");
        try self.connection.writeLine(out.written());

        while (true) {
            const line = try self.connection.readLine() orelse return error.Closed;
            if (std.mem.indexOf(u8, line, "\"return\"")) |_| return line;
            if (std.mem.indexOf(u8, line, "\"error\"")) |_| return error.QmpRejected;
        }
    }

    pub fn status(self: *Qmp, allocator: Allocator) ![]const u8 {
        const line = try self.execute(allocator, "query-status", null);
        var parsed = try json.parse(allocator, line);
        defer parsed.deinit();
        return json.textAt(parsed.value, "return");
    }
};

test "qmp bodies escape the command" {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.json.Stringify.encodeJsonString("query-status", .{}, &writer);
    try std.testing.expectEqualStrings("\"query-status\"", writer.buffered());
}
