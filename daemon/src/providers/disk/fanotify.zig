const std = @import("std");
const linux = std.os.linux;

pub const Event = struct {
	mask: u64,
	pid: i32,
	name: []const u8,
	overflow: bool,
};

pub const Watcher = struct {
	fd: i32,

	pub fn init() !Watcher {
		const flags: linux.fanotify.InitFlags = .{
			.CLOEXEC = true,
			.NONBLOCK = true,
			.CLASS = .NOTIF,
			.REPORT_FID = true,
			.REPORT_DIR_FID = true,
			.REPORT_NAME = true,
			.UNLIMITED_QUEUE = true,
		};
		const event_flags: u32 = @bitCast(std.posix.O{ .ACCMODE = .RDONLY });
		const result = linux.fanotify_init(flags, event_flags);
		if (linux.errno(result) != .SUCCESS) return error.FanotifyUnavailable;
		return .{ .fd = @intCast(result) };
	}

	pub fn close(self: *Watcher) void {
		_ = linux.close(self.fd);
	}

	pub fn mark(self: *Watcher, path: []const u8) !void {
		const z = try std.heap.smp_allocator.allocSentinel(u8, path.len, 0);
		defer std.heap.smp_allocator.free(z);
		@memcpy(z, path);

		const flags: linux.fanotify.MarkFlags = .{ .ADD = true, .FILESYSTEM = true };
		const mask: linux.fanotify.MarkMask = .{
			.CREATE = true,
			.DELETE = true,
			.MOVED_FROM = true,
			.MOVED_TO = true,
			.MODIFY = true,
			.CLOSE_WRITE = true,
			.ONDIR = true,
		};

		var result = linux.fanotify_mark(self.fd, flags, mask, linux.AT.FDCWD, z.ptr);
		if (linux.errno(result) != .SUCCESS) {
			const mount_flags: linux.fanotify.MarkFlags = .{ .ADD = true, .MOUNT = true };
			result = linux.fanotify_mark(self.fd, mount_flags, mask, linux.AT.FDCWD, z.ptr);
		}
		if (linux.errno(result) != .SUCCESS) return error.MarkFailed;
	}

	pub fn markDir(self: *Watcher, path: []const u8) !void {
		const z = try std.heap.smp_allocator.allocSentinel(u8, path.len, 0);
		defer std.heap.smp_allocator.free(z);
		@memcpy(z, path);

		const flags: linux.fanotify.MarkFlags = .{ .ADD = true };
		const mask: linux.fanotify.MarkMask = .{
			.CREATE = true,
			.DELETE = true,
			.MOVED_FROM = true,
			.MOVED_TO = true,
			.MODIFY = true,
			.CLOSE_WRITE = true,
			.EVENT_ON_CHILD = true,
			.ONDIR = true,
		};

		const result = linux.fanotify_mark(self.fd, flags, mask, linux.AT.FDCWD, z.ptr);
		if (linux.errno(result) != .SUCCESS) return error.MarkFailed;
	}

	pub const Batch = struct {
		events: []const Event,
		next: usize = 0,

		pub fn take(self: *Batch) ?Event {
			if (self.next >= self.events.len) return null;
			const event = self.events[self.next];
			self.next += 1;
			return event;
		}
	};

	pub fn read(self: *Watcher, buffer: []align(8) u8) !Batch {
		const count = linux.read(self.fd, buffer.ptr, buffer.len);
		const err = linux.errno(count);
		if (err == .AGAIN) return .{ .events = &.{} };
		if (err != .SUCCESS) return error.ReadFailed;
		if (count == 0) return .{ .events = &.{} };

		var events: std.ArrayList(Event) = .empty;
		errdefer events.deinit(std.heap.smp_allocator);

		var offset: usize = 0;
		while (offset + @sizeOf(linux.fanotify.event_metadata) <= count) {
			const metadata: *align(1) linux.fanotify.event_metadata = @ptrCast(&buffer[offset]);
			if (metadata.event_len < @sizeOf(linux.fanotify.event_metadata)) break;

			const end = @min(count, offset + metadata.event_len);
			const mask: u64 = @bitCast(metadata.mask);
			const overflow = metadata.mask.Q_OVERFLOW;

			try events.append(std.heap.smp_allocator, .{
				.mask = mask,
				.pid = metadata.pid,
				.name = infoName(buffer[offset..end], metadata.metadata_len),
				.overflow = overflow,
			});

			if (metadata.fd >= 0) _ = linux.close(metadata.fd);
			offset += metadata.event_len;
		}

		return .{ .events = try events.toOwnedSlice(std.heap.smp_allocator) };
	}
};

pub fn freeBatch(batch: Watcher.Batch) void {
	if (batch.events.len > 0) std.heap.smp_allocator.free(batch.events);
}

fn infoName(record: []const u8, start: u16) []const u8 {
	const begin: usize = start;
	const end: usize = record.len;
	const fid_base = @sizeOf(linux.fanotify.event_info_header) + @sizeOf(linux.kernel_fsid_t);
	const handle_base = fid_base + @sizeOf(linux.file_handle);

	var offset = begin;
	while (offset + @sizeOf(linux.fanotify.event_info_header) <= end) {
		const header: *align(1) const linux.fanotify.event_info_header = @ptrCast(&record[offset]);
		if (header.len < @sizeOf(linux.fanotify.event_info_header)) break;
		const record_end = @min(end, offset + header.len);

		if (header.info_type == .DFID_NAME and offset + handle_base <= record_end) {
			const handle: *align(1) const linux.file_handle = @ptrCast(&record[offset + fid_base]);
			const name_start = offset + handle_base + handle.handle_bytes;
			if (name_start < record_end) return std.mem.sliceTo(record[name_start..record_end], 0);
		}

		offset += header.len;
	}

	return "";
}

pub fn describe(mask: u64) []const u8 {
	const bits: linux.fanotify.MarkMask = @bitCast(mask);
	if (bits.CREATE) return "create";
	if (bits.DELETE) return "delete";
	if (bits.MOVED_FROM or bits.MOVED_TO) return "move";
	if (bits.CLOSE_WRITE or bits.MODIFY) return "write";
	if (bits.Q_OVERFLOW) return "overflow";
	return "event";
}

test "a fanotify mask describes the change" {
	const create: linux.fanotify.MarkMask = .{ .CREATE = true };
	try std.testing.expectEqualStrings("create", describe(@bitCast(create)));

	const write: linux.fanotify.MarkMask = .{ .MODIFY = true };
	try std.testing.expectEqualStrings("write", describe(@bitCast(write)));
}
