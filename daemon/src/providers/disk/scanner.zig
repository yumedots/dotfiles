const std = @import("std");
const linux = std.os.linux;
const guardmod = @import("guard.zig");

pub const Allocator = std.mem.Allocator;
pub const Io = std.Io;
pub const none: u32 = std.math.maxInt(u32);
pub const fold_below: u64 = 1 << 20;

pub const Kind = enum(u8) {
	directory = 0,
	file = 1,
	other = 2,
};

pub const Node = extern struct {
	parent: u32 = none,
	first_child: u32 = none,
	next_sibling: u32 = none,
	name_off: u32 = 0,
	size: u64 = 0,
	mtime: u32 = 0,
	name_len: u16 = 0,
	kind: Kind = .file,
	flags: u8 = 0,
};

comptime {
	if (@sizeOf(Node) != 32) @compileError("disk node must stay 32 bytes");
}

pub const Stats = struct {
	entries: u64 = 0,
	directories: u64 = 0,
	files: u64 = 0,
	syscalls: u64 = 0,
	hardlinks: u64 = 0,
	folded: u64 = 0,
	started_ns: i128 = 0,
	ended_ns: i128 = 0,

	pub fn elapsedNs(self: Stats) i128 {
		return self.ended_ns - self.started_ns;
	}

	pub fn entriesPerSecond(self: Stats) f64 {
		const ns = self.elapsedNs();
		if (ns <= 0) return 0;
		return @as(f64, @floatFromInt(self.entries)) * 1_000_000_000.0 / @as(f64, @floatFromInt(ns));
	}
};

pub const Scan = struct {
	allocator: Allocator,
	nodes: std.ArrayListUnmanaged(Node) = .empty,
	names: std.ArrayListUnmanaged(u8) = .empty,
	root: []u8 = &.{},
	root_dev: u64 = 0,
	guard: *const guardmod.Guard,
	fold: u64 = fold_below,
	full_disk: bool = false,
	stats: Stats = .{},
	path: std.ArrayListUnmanaged(u8) = .empty,
	links: std.AutoHashMapUnmanaged(u128, void) = .empty,
	last_child: std.ArrayListUnmanaged(u32) = .empty,
	shared: std.Io.Mutex = .init,

	pub fn init(allocator: Allocator, guard: *const guardmod.Guard, fold: u64) !Scan {
		return .{ .allocator = allocator, .guard = guard, .fold = fold };
	}

	pub fn deinit(self: *Scan) void {
		self.nodes.deinit(self.allocator);
		self.names.deinit(self.allocator);
		self.path.deinit(self.allocator);
		self.links.deinit(self.allocator);
		self.last_child.deinit(self.allocator);
		if (self.root.len > 0) self.allocator.free(self.root);
	}

	pub fn total(self: *const Scan) u64 {
		if (self.nodes.items.len == 0) return 0;
		return self.nodes.items[0].size;
	}

	pub fn run(self: *Scan, root: []const u8) !void {
		if (self.root.len > 0) self.allocator.free(self.root);
		self.root = try self.allocator.dupe(u8, root);
		self.stats.started_ns = nowNs();

		const fd = try guardmod.openRoot(root);
		defer _ = linux.close(fd);

		const st = try statFd(fd);
		self.root_dev = devOf(st);
		try self.path.appendSlice(self.allocator, root);

		const root_index = try self.addNode(none, root, st, .directory, blocksOf(st));
		self.stats.directories += 1;
		self.stats.entries += 1;

		try self.scanDir(fd, root_index, st);
		self.rollup(root_index);

		self.stats.ended_ns = nowNs();
	}

	const btrfs_ioctl_magic = 0x94;
	const SearchKey = extern struct {
		tree_id: u64 = 0,
		min_objectid: u64 = 0,
		max_objectid: u64 = 0,
		min_offset: u64 = 0,
		max_offset: u64 = 0,
		min_transid: u64 = 0,
		max_transid: u64 = 0,
		min_type: u32 = 0,
		max_type: u32 = 0,
		nr_items: u32 = 0,
		unused: u32 = 0,
		unused1: u64 = 0,
		unused2: u64 = 0,
		unused3: u64 = 0,
		unused4: u64 = 0,
	};
	const SearchArgs = extern struct {
		key: SearchKey = .{},
		buf_size: u64 = 0,
	};
	const SearchHeader = extern struct {
		transid: u64,
		objectid: u64,
		offset: u64,
		kind: u32,
		len: u32,
	};
	const Inode = struct {
		size: u64,
		mode: u32,
		nlink: u32,
	};
	const Ref = struct {
		parent: u64,
		name: []const u8,
	};

	fn runBtrfsImpl(self: *Scan, root: []const u8) !void {
		if (self.root.len > 0) self.allocator.free(self.root);
		self.root = try self.allocator.dupe(u8, root);
		self.stats.started_ns = nowNs();

		const fd = try guardmod.openRoot(root);
		defer _ = linux.close(fd);
		const root_stat = try statFd(fd);
		if (root_stat.ino != 256) return error.NotSubvolumeRoot;

		var inodes = std.AutoHashMapUnmanaged(u64, Inode).empty;
		defer inodes.deinit(self.allocator);
		var refs = std.AutoHashMapUnmanaged(u64, Ref).empty;
		defer {
			var values = refs.valueIterator();
			while (values.next()) |ref| self.allocator.free(ref.name);
			refs.deinit(self.allocator);
		}
		var children = std.AutoHashMapUnmanaged(u64, std.ArrayListUnmanaged(u64)).empty;
		defer {
			var values = children.valueIterator();
			while (values.next()) |list| list.deinit(self.allocator);
			children.deinit(self.allocator);
		}

		const request = linux.IOCTL.IOWR(btrfs_ioctl_magic, 17, SearchArgs);
		var key: SearchKey = .{
			.tree_id = 0,
			.min_objectid = 256,
			.max_objectid = std.math.maxInt(u64),
			.min_offset = 0,
			.max_offset = std.math.maxInt(u64),
			.min_transid = 0,
			.max_transid = std.math.maxInt(u64),
			.min_type = 1,
			.max_type = 255,
			.nr_items = 4096,
		};
		const buf_len: usize = 1024 * 1024;
		const storage = try self.allocator.alignedAlloc(u8, .@"8", @sizeOf(SearchArgs) + buf_len);
		defer self.allocator.free(storage);
		const data_start = @sizeOf(SearchArgs);

		var rounds: usize = 0;
		while (rounds < 1_000_000) : (rounds += 1) {
			key.nr_items = 4096;
			const args_ptr: *SearchArgs = @ptrCast(@alignCast(storage.ptr));
			args_ptr.key = key;
			args_ptr.buf_size = buf_len;

			const result = linux.ioctl(fd, request, @intFromPtr(storage.ptr));
			if (linux.errno(result) != .SUCCESS) return error.BtrfsSearchFailed;
			key = args_ptr.key;
			if (key.nr_items == 0) break;
			if (key.nr_items > 4096) return error.BtrfsSearchFailed;

			var offset: usize = 0;
			var last: ?SearchHeader = null;
			var index: usize = 0;
			while (index < key.nr_items) : (index += 1) {
				if (offset + @sizeOf(SearchHeader) > buf_len) return error.BtrfsSearchFailed;
				const header: *align(1) const SearchHeader = @ptrCast(&storage[data_start + offset]);
				const record_end = offset + @sizeOf(SearchHeader) + header.len;
				if (record_end > buf_len) return error.BtrfsSearchFailed;

				const payload = storage[data_start + offset + @sizeOf(SearchHeader) .. data_start + record_end];
				if (header.kind == 1 and payload.len >= 56) {
					const size = readLe64(payload, 16);
					const nbytes = readLe64(payload, 24);
					const nlink = readLe32(payload, 40);
					const mode = readLe32(payload, 52);
					try inodes.put(self.allocator, header.objectid, .{ .size = if (nbytes > 0) nbytes else size, .mode = mode, .nlink = nlink });
				} else if (header.kind == 12 and payload.len >= 10) {
					const name_len = readLe16(payload, 8);
					if (payload.len >= 10 + name_len) {
						const name = try self.allocator.dupe(u8, payload[10 .. 10 + name_len]);
						try refs.put(self.allocator, header.objectid, .{ .parent = header.offset, .name = name });
					}
				} else if (header.kind == 13 and payload.len >= 18) {
					const parent = readLe64(payload, 0);
					const name_len = readLe16(payload, 16);
					if (payload.len >= 18 + name_len) {
						const name = try self.allocator.dupe(u8, payload[18 .. 18 + name_len]);
						try refs.put(self.allocator, header.objectid, .{ .parent = parent, .name = name });
					}
				}

				last = header.*;
				offset = record_end;
			}

			const tail = last orelse break;
			const previous = key;
			key.min_objectid = tail.objectid;
			key.min_type = tail.kind;
			if (tail.offset == std.math.maxInt(u64)) {
				key.min_offset = 0;
				key.min_type = tail.kind + 1;
			} else {
				key.min_offset = tail.offset + 1;
			}

			if (key.min_objectid == previous.min_objectid and key.min_type == previous.min_type and key.min_offset == previous.min_offset) {
				return error.BtrfsSearchStalled;
			}
		}

		var ref_iter = refs.iterator();
		while (ref_iter.next()) |entry| {
			const child_ino = entry.key_ptr.*;
			if (child_ino == 256) continue;
			const parent_ino = entry.value_ptr.parent;
			if (parent_ino == child_ino) continue;
			const list = try children.getOrPut(self.allocator, parent_ino);
			if (!list.found_existing) list.value_ptr.* = .empty;
			try list.value_ptr.append(self.allocator, child_ino);
		}

		self.root_dev = devOf(root_stat);
		const root_inode = inodes.get(256) orelse Inode{ .size = 0, .mode = 0o040755, .nlink = 1 };
		const root_index = try self.addNode(none, root, fakeStat(root_stat.ino, root_inode, root_stat.mtime.sec), .directory, root_inode.size);
		self.stats.directories += 1;
		self.stats.entries += 1;

		var path = std.ArrayListUnmanaged(u8).empty;
		defer path.deinit(self.allocator);
		try path.appendSlice(self.allocator, root);
		try self.visitBtrfs(&inodes, &refs, &children, 256, root_index, &path);

		self.rollup(root_index);
		self.stats.ended_ns = nowNs();
	}

	fn visitBtrfs(
		self: *Scan,
		inodes: *std.AutoHashMapUnmanaged(u64, Inode),
		refs: *std.AutoHashMapUnmanaged(u64, Ref),
		children: *std.AutoHashMapUnmanaged(u64, std.ArrayListUnmanaged(u64)),
		parent_ino: u64,
		parent_index: u32,
		path: *std.ArrayListUnmanaged(u8),
	) !void {
		const list = children.get(parent_ino) orelse return;

		for (list.items) |ino| {
			const inode = inodes.get(ino) orelse continue;
			const ref = refs.get(ino) orelse continue;
			if (ref.name.len == 0) continue;

			const mark = path.items.len;
			if (path.items.len == 0 or path.items[path.items.len - 1] != '/') try path.append(self.allocator, '/');
			try path.appendSlice(self.allocator, ref.name);
			defer path.shrinkRetainingCapacity(mark);

			if (self.skipPath(path.items)) continue;

			const kind: Kind = if (std.posix.S.ISDIR(inode.mode)) .directory else if (std.posix.S.ISREG(inode.mode)) .file else .other;
			const index = try self.addNode(parent_index, ref.name, fakeStat(ino, inode, 0), kind, inode.size);
			if (kind == .directory) {
				self.stats.directories += 1;
				self.stats.entries += 1;
				try self.visitBtrfs(inodes, refs, children, ino, index, path);
			} else {
				self.stats.files += 1;
				self.stats.entries += 1;
			}
		}
	}

	fn fakeStat(ino: u64, inode: Inode, mtime: i64) linux.Statx {
		var st: linux.Statx = std.mem.zeroes(linux.Statx);
		st.mask = .{ .TYPE = true, .MODE = true, .NLINK = true, .INO = true, .SIZE = true };
		st.nlink = inode.nlink;
		st.mode = @intCast(inode.mode);
		st.ino = ino;
		st.size = inode.size;
		st.mtime = .{ .sec = mtime, .nsec = 0, .__pad1 = 0 };
		return st;
	}

	fn readLe64(bytes: []const u8, offset: usize) u64 {
		return std.mem.readInt(u64, bytes[offset..][0..8], .little);
	}

	fn readLe32(bytes: []const u8, offset: usize) u32 {
		return std.mem.readInt(u32, bytes[offset..][0..4], .little);
	}

	fn readLe16(bytes: []const u8, offset: usize) u16 {
		return std.mem.readInt(u16, bytes[offset..][0..2], .little);
	}

	pub fn runBtrfs(self: *Scan, root: []const u8) !void {
		return self.runBtrfsImpl(root);
	}

	pub fn runThreaded(self: *Scan, root: []const u8, threads: usize) !void {
		if (self.root.len > 0) self.allocator.free(self.root);
		self.root = try self.allocator.dupe(u8, root);
		self.stats.started_ns = nowNs();

		const fd = try guardmod.openRoot(root);
		const st = try statFd(fd);
		_ = linux.close(fd);

		self.root_dev = devOf(st);
		const root_index = try self.addNode(none, root, st, .directory, blocksOf(st));
		self.stats.directories += 1;
		self.stats.entries += 1;

		var queue: Queue = .{};
		queue.push(self.allocator, .{ .parent = root_index, .path = try self.allocator.dupe(u8, root) });

		var workers: [64]std.Thread = undefined;
		const count = @min(@max(threads, 1), workers.len);

		for (workers[0..count]) |*worker| {
			worker.* = try std.Thread.spawn(.{}, workerLoop, .{ self, &queue });
		}

		for (workers[0..count]) |worker| worker.join();

		if (queue.failure) |err| {
			queue.freePending(self.allocator);
			self.stats.ended_ns = nowNs();
			return err;
		}

		self.rollup(root_index);
		self.stats.ended_ns = nowNs();
		queue.jobs.deinit(self.allocator);
	}

	pub fn runUringThreaded(self: *Scan, root: []const u8, threads: usize) !void {
		if (self.root.len > 0) self.allocator.free(self.root);
		self.root = try self.allocator.dupe(u8, root);
		self.stats.started_ns = nowNs();

		const fd = try guardmod.openRoot(root);
		const st = try statFd(fd);
		_ = linux.close(fd);

		self.root_dev = devOf(st);
		const root_index = try self.addNode(none, root, st, .directory, blocksOf(st));
		self.stats.directories += 1;
		self.stats.entries += 1;

		var queue: Queue = .{};
		queue.push(self.allocator, .{ .parent = root_index, .path = try self.allocator.dupe(u8, root) });

		var workers: [64]std.Thread = undefined;
		const count = @min(@max(threads, 1), workers.len);

		for (workers[0..count]) |*worker| {
			worker.* = try std.Thread.spawn(.{}, uringWorker, .{ self, &queue });
		}
		for (workers[0..count]) |worker| worker.join();

		if (queue.failure) |err| {
			queue.freePending(self.allocator);
			self.stats.ended_ns = nowNs();
			return err;
		}

		self.rollup(root_index);
		self.stats.ended_ns = nowNs();
		queue.jobs.deinit(self.allocator);
	}

	fn uringWorker(self: *Scan, queue: *Queue) void {
		var ring = linux.IoUring.init(256, 0) catch {
			queue.mutex.lockUncancelable(mutexIo());
			if (queue.failure == null) queue.failure = error.RingInit;
			queue.mutex.unlock(mutexIo());
			return;
		};
		defer ring.deinit();

		while (true) {
			queue.mutex.lockUncancelable(mutexIo());
			if (queue.failure != null) {
				queue.mutex.unlock(mutexIo());
				return;
			}
			if (queue.jobs.items.len == 0) {
				if (queue.active == 0) {
					queue.mutex.unlock(mutexIo());
					return;
				}
				queue.mutex.unlock(mutexIo());
				std.Thread.yield() catch {};
				continue;
			}

			const job = queue.jobs.pop().?;
			queue.active += 1;
			queue.mutex.unlock(mutexIo());

			self.threadDirUring(job, queue, &ring) catch |err| {
				queue.mutex.lockUncancelable(mutexIo());
				if (queue.failure == null) queue.failure = err;
				queue.mutex.unlock(mutexIo());
			};

			self.allocator.free(job.path);

			queue.mutex.lockUncancelable(mutexIo());
			queue.active -= 1;
			queue.mutex.unlock(mutexIo());
		}
	}

	const uring_batch = 256;

	fn threadDirUring(self: *Scan, job: Job, queue: *Queue, ring: *linux.IoUring) !void {
		const fd = try guardmod.openRoot(job.path);
		defer _ = linux.close(fd);

		var buffer: [128 * 1024]u8 = undefined;
		while (true) {
			const count = linux.getdents64(fd, &buffer, buffer.len);
			self.bumpSyscall();
			if (linux.errno(count) != .SUCCESS) return error.ReadFailed;
			if (count == 0) break;

			var names: [uring_batch][:0]const u8 = undefined;
			var stats: [uring_batch]linux.Statx = undefined;
			var paths: [uring_batch][]u8 = undefined;
			var batch: usize = 0;

			var offset: usize = 0;
			while (offset < count) {
				const entry: *align(1) linux.dirent64 = @ptrCast(&buffer[offset]);
				if (entry.reclen == 0) break;
				offset += entry.reclen;

				const name = std.mem.span(@as([*:0]const u8, @ptrCast(&entry.name)));
				if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
				if (name.len == 0 or name.len > std.math.maxInt(u16)) continue;

				const child_path = if (std.mem.eql(u8, job.path, "/"))
					try std.fmt.allocPrint(self.allocator, "/{s}", .{name})
				else
					try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ job.path, name });

				if (self.skipPath(child_path)) {
					self.allocator.free(child_path);
					continue;
				}

				names[batch] = name;
				paths[batch] = child_path;
				_ = ring.statx(batch, fd, name, linux.AT.SYMLINK_NOFOLLOW, statMask(), &stats[batch]) catch return error.SubmitFailed;
				batch += 1;

				if (batch == uring_batch) {
					try self.flushUring(job.parent, queue, ring, names[0..batch], &stats, paths[0..batch]);
					batch = 0;
				}
			}

			if (batch > 0) try self.flushUring(job.parent, queue, ring, names[0..batch], &stats, paths[0..batch]);
		}
	}

	fn flushUring(
		self: *Scan,
		parent: u32,
		queue: *Queue,
		ring: *linux.IoUring,
		names: []const [:0]const u8,
		stats: *[uring_batch]linux.Statx,
		paths: []const []u8,
	) !void {
		_ = names;
		_ = try ring.submit_and_wait(@intCast(paths.len));
		self.bumpSyscall();

		var cqes: [uring_batch]linux.io_uring_cqe = undefined;
		var got: usize = 0;
		while (got < paths.len) {
			const n = try ring.copy_cqes(&cqes, @intCast(paths.len - got));
			if (n == 0) continue;
			got += n;
		}

		for (cqes[0..got]) |cqe| {
			const index: usize = @intCast(cqe.user_data);
			const child_path = paths[index];
			defer self.allocator.free(child_path);

			if (cqe.err() != .SUCCESS) return error.StatFailed;
			const st = stats[index];

			if (!self.full_disk and devOf(st) != self.root_dev) continue;
			if (st.nlink > 1 and !std.posix.S.ISDIR(st.mode)) {
				const key = linkKey(st);
				self.shared.lockUncancelable(mutexIo());
				const seen = self.links.contains(key);
				if (!seen) self.links.put(self.allocator, key, {}) catch {};
				self.shared.unlock(mutexIo());
				if (seen) {
					self.bumpHardlink();
					continue;
				}
			}

			const name = std.fs.path.basename(child_path);
			if (std.posix.S.ISDIR(st.mode)) {
				const index_node = try self.addNode(parent, name, st, .directory, blocksOf(st));
				self.bumpDir();
				queue.push(self.allocator, .{ .parent = index_node, .path = try self.allocator.dupe(u8, child_path) });
				continue;
			}

			const size = blocksOf(st);
			self.bumpFile();
			if (size < self.fold) {
				self.addFolded(parent, size);
				self.bumpFolded();
				continue;
			}

			const kind: Kind = if (std.posix.S.ISREG(st.mode)) .file else .other;
			_ = try self.addNode(parent, name, st, kind, size);
		}
	}

	fn workerLoop(self: *Scan, queue: *Queue) void {
		while (true) {
			queue.mutex.lockUncancelable(mutexIo());

			if (queue.failure != null) {
				queue.mutex.unlock(mutexIo());
				return;
			}

			if (queue.jobs.items.len == 0) {
				if (queue.active == 0) {
					queue.mutex.unlock(mutexIo());
					return;
				}
				queue.mutex.unlock(mutexIo());
				std.Thread.yield() catch {};
				continue;
			}

			const job = queue.jobs.pop().?;
			queue.active += 1;
			queue.mutex.unlock(mutexIo());

			self.threadDir(job, queue) catch |err| {
				queue.mutex.lockUncancelable(mutexIo());
				if (queue.failure == null) queue.failure = err;
				queue.mutex.unlock(mutexIo());
			};

			self.allocator.free(job.path);

			queue.mutex.lockUncancelable(mutexIo());
			queue.active -= 1;
			queue.mutex.unlock(mutexIo());
		}
	}

	fn threadDir(self: *Scan, job: Job, queue: *Queue) !void {
		const fd = try guardmod.openRoot(job.path);
		defer _ = linux.close(fd);

		var buffer: [128 * 1024]u8 = undefined;
		while (true) {
			const count = linux.getdents64(fd, &buffer, buffer.len);
			self.bumpSyscall();
			if (linux.errno(count) != .SUCCESS) return error.ReadFailed;
			if (count == 0) break;

			var offset: usize = 0;
			while (offset < count) {
				const entry: *align(1) linux.dirent64 = @ptrCast(&buffer[offset]);
				if (entry.reclen == 0) break;
				offset += entry.reclen;

				const name = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&entry.name)), 0);
				if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
				if (name.len == 0 or name.len > std.math.maxInt(u16)) continue;

				const child_path = if (std.mem.eql(u8, job.path, "/"))
					try std.fmt.allocPrint(self.allocator, "/{s}", .{name})
				else
					try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ job.path, name });
				defer self.allocator.free(child_path);

				if (self.skipPath(child_path)) continue;

				var st: linux.Statx = undefined;
				const result = linux.statx(fd, @ptrCast(&entry.name), linux.AT.SYMLINK_NOFOLLOW, statMask(), &st);
				self.bumpSyscall();
				if (linux.errno(result) != .SUCCESS) return error.StatFailed;
				if (!self.full_disk and devOf(st) != self.root_dev) continue;

				if (st.nlink > 1 and !std.posix.S.ISDIR(st.mode)) {
					const key = linkKey(st);
					self.shared.lockUncancelable(mutexIo());
					const seen = self.links.contains(key);
					if (!seen) self.links.put(self.allocator, key, {}) catch {};
					self.shared.unlock(mutexIo());
					if (seen) {
						self.bumpHardlink();
						continue;
					}
				}

				if (std.posix.S.ISDIR(st.mode)) {
					const index = try self.addNode(job.parent, name, st, .directory, blocksOf(st));
					self.bumpDir();
					queue.push(self.allocator, .{ .parent = index, .path = try self.allocator.dupe(u8, child_path) });
					continue;
				}

				const size = blocksOf(st);
				self.bumpFile();
				if (size < self.fold) {
					self.addFolded(job.parent, size);
					self.bumpFolded();
					continue;
				}

				const kind: Kind = if (std.posix.S.ISREG(st.mode)) .file else .other;
				_ = try self.addNode(job.parent, name, st, kind, size);
			}
		}
	}

	fn bumpSyscall(self: *Scan) void {
		self.shared.lockUncancelable(mutexIo());
		self.stats.syscalls += 1;
		self.shared.unlock(mutexIo());
	}

	fn bumpDir(self: *Scan) void {
		self.shared.lockUncancelable(mutexIo());
		self.stats.directories += 1;
		self.stats.entries += 1;
		self.shared.unlock(mutexIo());
	}

	fn bumpFile(self: *Scan) void {
		self.shared.lockUncancelable(mutexIo());
		self.stats.files += 1;
		self.stats.entries += 1;
		self.shared.unlock(mutexIo());
	}

	fn bumpHardlink(self: *Scan) void {
		self.shared.lockUncancelable(mutexIo());
		self.stats.hardlinks += 1;
		self.shared.unlock(mutexIo());
	}

	fn bumpFolded(self: *Scan) void {
		self.shared.lockUncancelable(mutexIo());
		self.stats.folded += 1;
		self.shared.unlock(mutexIo());
	}

	fn scanDir(self: *Scan, fd: i32, parent: u32, parent_stat: linux.Statx) !void {
		var buffer: [128 * 1024]u8 = undefined;

		while (true) {
			const count = linux.getdents64(fd, &buffer, buffer.len);
			self.stats.syscalls += 1;

			if (linux.errno(count) != .SUCCESS) return error.ReadFailed;
			if (count == 0) break;

			var offset: usize = 0;
			while (offset < count) {
				const entry: *align(1) linux.dirent64 = @ptrCast(&buffer[offset]);
				if (entry.reclen == 0) break;
				offset += entry.reclen;

				const name = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&entry.name)), 0);
				if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
				if (name.len == 0 or name.len > std.math.maxInt(u16)) continue;

				const mark = self.path.items.len;
				if (self.path.items.len == 0 or self.path.items[self.path.items.len - 1] != '/') {
					try self.path.append(self.allocator, '/');
				}
				try self.path.appendSlice(self.allocator, name);
				defer self.path.shrinkRetainingCapacity(mark);

				if (self.skipPath(self.path.items)) continue;

				var st: linux.Statx = undefined;
				const result = linux.statx(fd, @ptrCast(&entry.name), linux.AT.SYMLINK_NOFOLLOW, statMask(), &st);
				self.stats.syscalls += 1;
				if (linux.errno(result) != .SUCCESS) return error.StatFailed;

				if (!self.full_disk and devOf(st) != self.root_dev) continue;
				if (st.nlink > 1 and !std.posix.S.ISDIR(st.mode)) {
					const key = linkKey(st);
					if (self.links.contains(key)) {
						self.stats.hardlinks += 1;
						continue;
					}
					try self.links.put(self.allocator, key, {});
				}

				if (std.posix.S.ISDIR(st.mode)) {
					const child_fd = guardmod.openChild(fd, name, true) catch return error.OpenFailed;
					defer _ = linux.close(child_fd);

					const index = try self.addNode(parent, name, st, .directory, blocksOf(st));
					self.stats.directories += 1;
					self.stats.entries += 1;

					try self.scanDir(child_fd, index, st);
					continue;
				}

				const size = blocksOf(st);
				self.stats.files += 1;
				self.stats.entries += 1;

				if (size < self.fold) {
					self.nodes.items[parent].size += size;
					self.stats.folded += 1;
					continue;
				}

				const kind: Kind = if (std.posix.S.ISREG(st.mode)) .file else .other;
				_ = try self.addNode(parent, name, st, kind, size);
			}
		}

		_ = parent_stat;
	}

	fn addNode(self: *Scan, parent: u32, name: []const u8, st: linux.Statx, kind: Kind, size: u64) !u32 {
		self.shared.lockUncancelable(mutexIo());
		defer self.shared.unlock(mutexIo());

		const index: u32 = @intCast(self.nodes.items.len);
		const name_off: u32 = @intCast(self.names.items.len);
		try self.names.appendSlice(self.allocator, name);

		try self.nodes.append(self.allocator, .{
			.parent = parent,
			.name_off = name_off,
			.name_len = @intCast(name.len),
			.mtime = @intCast(st.mtime.sec),
			.kind = kind,
			.size = size,
		});
		try self.last_child.append(self.allocator, index);

		if (parent != none) {
			const p = &self.nodes.items[parent];
			if (p.first_child == none) {
				p.first_child = index;
			} else {
				self.nodes.items[self.last_child.items[parent]].next_sibling = index;
			}
			self.last_child.items[parent] = index;
		}

		return index;
	}

	fn addFolded(self: *Scan, parent: u32, size: u64) void {
		self.shared.lockUncancelable(mutexIo());
		defer self.shared.unlock(mutexIo());
		self.nodes.items[parent].size += size;
	}

	fn rollup(self: *Scan, index: u32) void {
		var child = self.nodes.items[index].first_child;
		while (child != none) : (child = self.nodes.items[child].next_sibling) {
			self.rollup(child);
			self.nodes.items[index].size += self.nodes.items[child].size;
		}
	}

	fn skipPath(self: *const Scan, path: []const u8) bool {
		if (self.full_disk) {
			if (std.mem.indexOf(u8, path, "/.snapshots") != null) return true;
			return guardmod.hasPrefix(path, "/proc") or guardmod.hasPrefix(path, "/sys") or
				guardmod.hasPrefix(path, "/dev") or guardmod.hasPrefix(path, "/run");
		}
		return self.guard.isProtected(path, self.root) or self.guard.isMount(path, self.root);
	}

	pub fn nameOf(self: *const Scan, index: u32) []const u8 {
		const node = self.nodes.items[index];
		return self.names.items[node.name_off .. node.name_off + node.name_len];
	}

	pub fn childCount(self: *const Scan, index: u32) u32 {
		var count: u32 = 0;
		var child = self.nodes.items[index].first_child;
		while (child != none) : (child = self.nodes.items[child].next_sibling) count += 1;
		return count;
	}

	pub fn find(self: *const Scan, path: []const u8) ?u32 {
		if (std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, self.root)) return 0;

		var index: u32 = 0;
		var rest = path;
		if (std.mem.startsWith(u8, rest, self.root)) rest = rest[self.root.len..];

		var parts = std.mem.tokenizeScalar(u8, rest, '/');
		while (parts.next()) |part| {
			var child = self.nodes.items[index].first_child;
			while (child != none) : (child = self.nodes.items[child].next_sibling) {
				if (std.mem.eql(u8, self.nameOf(child), part)) break;
			}
			if (child == none) return null;
			index = child;
		}

		return index;
	}
};

fn mutexIo() std.Io {
	return std.Io.Threaded.global_single_threaded.io();
}

fn nowNs() i128 {
	var ts: linux.timespec = undefined;
	if (linux.errno(linux.clock_gettime(.MONOTONIC, &ts)) != .SUCCESS) return 0;
	return @as(i128, ts.sec) * std.time.ns_per_s + ts.nsec;
}

const Job = struct {
	parent: u32,
	path: []u8,
};

const Queue = struct {
	mutex: std.Io.Mutex = .init,
	jobs: std.ArrayListUnmanaged(Job) = .empty,
	active: usize = 0,
	failure: ?anyerror = null,

	fn push(self: *Queue, allocator: Allocator, job: Job) void {
		self.mutex.lockUncancelable(mutexIo());
		defer self.mutex.unlock(mutexIo());
		self.jobs.append(allocator, job) catch {
			allocator.free(job.path);
		};
	}

	fn freePending(self: *Queue, allocator: Allocator) void {
		for (self.jobs.items) |job| allocator.free(job.path);
		self.jobs.deinit(allocator);
	}
};

fn statMask() linux.STATX {
	return .{ .TYPE = true, .MODE = true, .NLINK = true, .INO = true, .SIZE = true, .BLOCKS = true, .MTIME = true };
}

fn statFd(fd: i32) !linux.Statx {
	var st: linux.Statx = undefined;
	const result = linux.statx(fd, "", linux.AT.EMPTY_PATH, statMask(), &st);
	if (linux.errno(result) != .SUCCESS) return error.StatFailed;
	return st;
}

fn blocksOf(st: linux.Statx) u64 {
	return st.blocks * 512;
}

fn devOf(st: linux.Statx) u64 {
	return (@as(u64, st.dev_major) << 32) | st.dev_minor;
}

fn linkKey(st: linux.Statx) u128 {
	return (@as(u128, devOf(st)) << 64) | st.ino;
}

fn writeTestFile(io: Io, allocator: Allocator, base: []const u8, relative: []const u8, body: []const u8) void {
	const path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ base, relative }) catch return;
	defer allocator.free(path);

	if (std.fs.path.dirname(path)) |dir| std.Io.Dir.cwd().createDirPath(io, dir) catch {};

	var file = std.Io.Dir.cwd().createFile(io, path, .{ .truncate = true }) catch return;
	file.writeStreamingAll(io, body) catch {};
	file.close(io);
}

fn usedOf(allocator: Allocator, path: []const u8) u64 {
	var st: linux.Statx = undefined;
	const z = allocator.allocSentinel(u8, path.len, 0) catch return 0;
	@memcpy(z, path);
	defer allocator.free(z);

	const result = linux.statx(linux.AT.FDCWD, z.ptr, linux.AT.SYMLINK_NOFOLLOW, statMask(), &st);
	if (linux.errno(result) != .SUCCESS) return 0;
	return blocksOf(st);
}

fn expectedUsed(io: Io, allocator: Allocator, path: []const u8, skip: []const u8) u64 {
	var st: linux.Statx = undefined;
	const z = allocator.allocSentinel(u8, path.len, 0) catch return 0;
	@memcpy(z, path);
	defer allocator.free(z);

	const result = linux.statx(linux.AT.FDCWD, z.ptr, linux.AT.SYMLINK_NOFOLLOW, statMask(), &st);
	if (linux.errno(result) != .SUCCESS) return 0;

	var total = blocksOf(st);
	if (!std.posix.S.ISDIR(st.mode)) return total;

	var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return total;
	defer dir.close(io);
	var it = dir.iterate();

	while (it.next(io) catch null) |entry| {
		if (std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")) continue;

		const child = std.fmt.allocPrint(allocator, "{s}/{s}", .{ path, entry.name }) catch continue;
		defer allocator.free(child);
		if (std.mem.eql(u8, child, skip)) continue;

		total += expectedUsed(io, allocator, child, skip);
	}

	return total;
}

test "scanner keeps exact totals, hardlinks once and skips protected paths" {
	const io = std.testing.io;
	var tmp = std.testing.tmpDir(.{});
	defer tmp.cleanup();

	const base = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}", .{tmp.sub_path});
	defer std.testing.allocator.free(base);

	writeTestFile(io, std.testing.allocator, base, "tree/a.txt", "hello\n");
	writeTestFile(io, std.testing.allocator, base, "tree/b.txt", "world\n");
	writeTestFile(io, std.testing.allocator, base, "tree/deep/one.txt", "one\n");
	writeTestFile(io, std.testing.allocator, base, "tree/secret/hidden.txt", "hidden\n");

	const root = try std.fmt.allocPrint(std.testing.allocator, "{s}/tree", .{base});
	defer std.testing.allocator.free(root);
	const secret = try std.fmt.allocPrint(std.testing.allocator, "{s}/secret", .{root});
	defer std.testing.allocator.free(secret);
	const hard = try std.fmt.allocPrint(std.testing.allocator, "{s}/a.txt", .{root});
	defer std.testing.allocator.free(hard);
	const second = try std.fmt.allocPrint(std.testing.allocator, "{s}/deep/same", .{root});
	defer std.testing.allocator.free(second);

	try std.Io.Dir.cwd().hardLink(hard, std.Io.Dir.cwd(), second, io, .{});

	const loop = try std.fmt.allocPrint(std.testing.allocator, "{s}/deep/loop", .{root});
	defer std.testing.allocator.free(loop);
	try std.Io.Dir.cwd().symLink(io, root, loop, .{});

	var extra = [_][]const u8{secret};
	var guard = try guardmod.Guard.init(std.testing.allocator, io, &extra);
	defer guard.deinit(std.testing.allocator);

	var scan = try Scan.init(std.testing.allocator, &guard, fold_below);
	defer scan.deinit();
	try scan.run(root);

	try std.testing.expect(scan.find(secret) == null);
	try std.testing.expect(scan.find("/nope") == null);
	try std.testing.expectEqual(@as(u64, 1), scan.stats.hardlinks);

	const expected = expectedUsed(io, std.testing.allocator, root, secret) - usedOf(std.testing.allocator, second);
	try std.testing.expectEqual(expected, scan.total());

	var threaded = try Scan.init(std.testing.allocator, &guard, fold_below);
	defer threaded.deinit();
	try threaded.runThreaded(root, 4);

	try std.testing.expectEqual(scan.total(), threaded.total());
	try std.testing.expectEqual(scan.stats.entries, threaded.stats.entries);
	try std.testing.expectEqual(scan.stats.hardlinks, threaded.stats.hardlinks);
	try std.testing.expect(threaded.find(secret) == null);

	var uring = try Scan.init(std.testing.allocator, &guard, fold_below);
	defer uring.deinit();
	uring.runUringThreaded(root, 4) catch return error.SkipZigTest;

	try std.testing.expectEqual(scan.total(), uring.total());
	try std.testing.expectEqual(scan.stats.entries, uring.stats.entries);
	try std.testing.expectEqual(scan.stats.hardlinks, uring.stats.hardlinks);
	try std.testing.expect(uring.find(secret) == null);

	var btrfs = try Scan.init(std.testing.allocator, &guard, fold_below);
	defer btrfs.deinit();
	btrfs.runBtrfs(root) catch |err| switch (err) {
		error.BtrfsSearchFailed, error.NotSubvolumeRoot => return,
		else => return err,
	};

	try std.testing.expectEqual(scan.total(), btrfs.total());
	try std.testing.expect(btrfs.find(secret) == null);
}
