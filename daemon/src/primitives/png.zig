const std = @import("std");

const Allocator = std.mem.Allocator;

const signature = [_]u8{ 0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a };
const block_max = 65535;

pub fn encodeRgba(allocator: Allocator, width: usize, height: usize, stride: usize, channels: usize, data: []const u8) ![]u8 {
	if (width == 0 or height == 0 or channels < 3 or channels > 4) return error.BadImage;
	if (stride < width * channels or data.len < stride * (height - 1) + width * channels) return error.BadImage;

	const raw = try allocator.alloc(u8, height * (1 + width * 4));
	defer allocator.free(raw);

	var at: usize = 0;
	for (0..height) |y| {
		raw[at] = 0;
		at += 1;

		for (0..width) |x| {
			const pixel = data[y * stride + x * channels ..];

			raw[at] = pixel[0];
			raw[at + 1] = pixel[1];
			raw[at + 2] = pixel[2];
			raw[at + 3] = if (channels == 4) pixel[3] else 255;
			at += 4;
		}
	}

	var out: std.ArrayList(u8) = .empty;
	errdefer out.deinit(allocator);

	try out.appendSlice(allocator, &signature);

	var header: [13]u8 = undefined;
	std.mem.writeInt(u32, header[0..4], @intCast(width), .big);
	std.mem.writeInt(u32, header[4..8], @intCast(height), .big);
	header[8] = 8;
	header[9] = 6;
	header[10] = 0;
	header[11] = 0;
	header[12] = 0;
	try chunk(allocator, &out, "IHDR", &header);

	var zlib: std.ArrayList(u8) = .empty;
	defer zlib.deinit(allocator);

	try zlib.appendSlice(allocator, &.{ 0x78, 0x01 });

	var offset: usize = 0;
	while (offset < raw.len or offset == 0) {
		const size = @min(block_max, raw.len - offset);
		const last: u8 = if (offset + size >= raw.len) 1 else 0;

		try zlib.append(allocator, last);

		var lengths: [4]u8 = undefined;
		std.mem.writeInt(u16, lengths[0..2], @intCast(size), .little);
		std.mem.writeInt(u16, lengths[2..4], @intCast(~@as(u16, @intCast(size))), .little);
		try zlib.appendSlice(allocator, &lengths);
		try zlib.appendSlice(allocator, raw[offset .. offset + size]);

		offset += size;
		if (last == 1) break;
	}

	var adler: [4]u8 = undefined;
	std.mem.writeInt(u32, &adler, std.hash.Adler32.hash(raw), .big);
	try zlib.appendSlice(allocator, &adler);

	try chunk(allocator, &out, "IDAT", zlib.items);
	try chunk(allocator, &out, "IEND", &.{});

	return out.toOwnedSlice(allocator);
}

fn chunk(allocator: Allocator, out: *std.ArrayList(u8), kind: *const [4]u8, body: []const u8) !void {
	var length: [4]u8 = undefined;
	std.mem.writeInt(u32, &length, @intCast(body.len), .big);
	try out.appendSlice(allocator, &length);

	var crc = std.hash.Crc32.init();
	crc.update(kind);
	crc.update(body);

	try out.appendSlice(allocator, kind);
	try out.appendSlice(allocator, body);

	var sum: [4]u8 = undefined;
	std.mem.writeInt(u32, &sum, crc.final(), .big);
	try out.appendSlice(allocator, &sum);
}

test "a png has its signature, a header and a closing chunk" {
	const pixels = [_]u8{ 255, 0, 0, 0, 255, 0, 0, 0, 255, 9, 9, 9 };
	const out = try encodeRgba(std.testing.allocator, 2, 2, 6, 3, &pixels);
	defer std.testing.allocator.free(out);

	try std.testing.expectEqualSlices(u8, &signature, out[0..8]);
	try std.testing.expectEqualStrings("IHDR", out[12..16]);
	try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, out[16..20], .big));
	try std.testing.expectEqualStrings("IEND", out[out.len - 8 .. out.len - 4]);
}
