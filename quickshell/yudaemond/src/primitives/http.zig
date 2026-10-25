const std = @import("std");

pub const Io = std.Io;
pub const Allocator = std.mem.Allocator;
pub const Headers = std.http.Client.Request.Headers;

pub const Reply = struct {
	status: std.http.Status,
	body: []u8,

	pub fn deinit(self: Reply, allocator: Allocator) void {
		allocator.free(self.body);
	}

	pub fn ok(self: Reply) bool {
		return self.status == .ok or self.status == .created or self.status == .no_content;
	}
};

pub const Client = struct {
	allocator: Allocator,
	io: Io,
	http: std.http.Client,

	pub fn init(allocator: Allocator, io: Io) Client {
		return .{
			.allocator = allocator,
			.io = io,
			.http = .{ .allocator = allocator, .io = io },
		};
	}

	pub fn get(self: *Client, allocator: Allocator, url: []const u8, auth: ?[]const u8, extra: []const std.http.Header) !Reply {
		var out: std.Io.Writer.Allocating = .init(allocator);
		errdefer out.deinit();

		var headers: Headers = .{
			.user_agent = .{ .override = "yudaemond" },
			.accept_encoding = .{ .override = "identity" },
		};

		if (auth) |value| headers.authorization = .{ .override = value };

		const result = try self.http.fetch(.{
			.location = .{ .url = url },
			.response_writer = &out.writer,
			.headers = headers,
			.extra_headers = extra,
			.keep_alive = false,
		});

		return .{ .status = result.status, .body = try out.toOwnedSlice() };
	}

	pub fn getJson(self: *Client, allocator: Allocator, url: []const u8, auth: ?[]const u8, extra: []const std.http.Header) !std.json.Parsed(std.json.Value) {
		const reply = try self.get(allocator, url, auth, extra);
		defer reply.deinit(allocator);

		return std.json.parseFromSlice(std.json.Value, allocator, reply.body, .{ .allocate = .alloc_always });
	}

	pub fn stream(self: *Client, url: []const u8, auth: ?[]const u8, ctx: *anyopaque, on_line: *const fn (*anyopaque, []const u8) void) !void {
		var headers: Headers = .{
			.user_agent = .{ .override = "yudaemond" },
			.accept_encoding = .{ .override = "identity" },
		};

		if (auth) |value| headers.authorization = .{ .override = value };

		var request = try self.http.request(.GET, try std.Uri.parse(url), .{
			.headers = headers,
			.keep_alive = true,
		});
		defer request.deinit();

		try request.sendBodiless();

		var redirect_buffer: [8192]u8 = undefined;
		var response = try request.receiveHead(&redirect_buffer);

		if (response.head.status != .ok) return error.HttpStatus;

		var transfer: [8192]u8 = undefined;
		const reader = response.reader(&transfer);

		while (try reader.takeDelimiter('\n')) |line| {
			on_line(ctx, line);
		}
	}
};

pub fn basicAuth(allocator: Allocator, user: []const u8, password: []const u8) ![]u8 {
	const pair = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ user, password });
	defer allocator.free(pair);

	const encoder = std.base64.standard.Encoder;
	const out = try allocator.alloc(u8, "Basic ".len + encoder.calcSize(pair.len));
	@memcpy(out[0..6], "Basic ");
	_ = encoder.encode(out[6..], pair);

	return out;
}

pub fn bearer(allocator: Allocator, token: []const u8) ![]u8 {
	return std.fmt.allocPrint(allocator, "Bearer {s}", .{token});
}

pub fn encodeQuery(allocator: Allocator, value: []const u8) ![]u8 {
	var out: std.ArrayList(u8) = .empty;
	errdefer out.deinit(allocator);

	for (value) |byte| {
		const plain = (byte >= 'a' and byte <= 'z') or (byte >= 'A' and byte <= 'Z') or
			(byte >= '0' and byte <= '9') or byte == '-' or byte == '_' or byte == '.' or byte == '~';
		if (plain) {
			try out.append(allocator, byte);
		} else {
			try out.print(allocator, "%{X:0>2}", .{byte});
		}
	}

	return out.toOwnedSlice(allocator);
}

test "basic auth encodes the pair" {
	const allocator = std.testing.allocator;

	const value = try basicAuth(allocator, "opencode", "secret");
	defer allocator.free(value);

	try std.testing.expectEqualStrings("Basic b3BlbmNvZGU6c2VjcmV0", value);
}

test "query encoding escapes slashes and spaces" {
	const allocator = std.testing.allocator;

	const value = try encodeQuery(allocator, "/home/a b");
	defer allocator.free(value);

	try std.testing.expectEqualStrings("%2Fhome%2Fa%20b", value);
}
