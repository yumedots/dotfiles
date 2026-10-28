const std = @import("std");
const hubmod = @import("../hub.zig");
const exec = @import("../primitives/exec.zig");
const json = @import("../primitives/json.zig");
const fmt = @import("../primitives/fmt.zig");
const proc = @import("../primitives/proc.zig");
const sleep = @import("../primitives/sleep.zig");
const watch = @import("../primitives/watch.zig");
const hypr = @import("../primitives/hypr.zig");
const wallpaper = @import("wallpaper.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const state_file = ".config/quickshell/cache/bar-ink.json";
const verdict_file = ".config/quickshell/yudaemond/cache/wallpaper-ink.json";
const daemon_bin = "/usr/bin/awww-daemon";
const ink_prefix = "awww-ink-";
const black_ink = "#000000";
const white_ink = "#ffffff";
const ink_black = "black";
const ink_white = "white";
const measure_gap_ms = 2000;
const fade_ms = 400;
/// the frame that starts a fade is committed on the next pass and shown on the refresh after
/// that, so the fade is on screen a little after the first ink write
const first_frame_ms = 50;
const confirm_ms = fade_ms + 150;
const mid_lead_ms = fade_ms / 2 - 40;
const mid_wait_ms = 80;
const mid_poll_ms = 10;
const ink_wait_ms = 700;
const ink_poll_ms = 20;
const max_band = 255;

/// The wallpaper is half switched halfway through its fade: the old image is as present as the
/// new one and the bar band has stopped being the old colour. That is the moment the ink flips,
/// not when the cache knows the answer. A daemon that writes on every frame marks the fade's
/// first frame; the frame is on screen a moment later, so the halfway point is half a fade after
/// that.
const Moment = struct {
	at: i64,
	written: bool = false,

	fn after(started: i64) Moment {
		return .{ .at = started + fade_ms / 2 };
	}

	fn wait(self: Moment, now: i64) u64 {
		if (now >= self.at) return 0;

		return @intCast(self.at - now);
	}
};

/// When the bar should take the new ink. A write that lands after `awww img` returned is the
/// verdict of the frame that made the wallpaper half present, so it is already the moment. A
/// write before that is a per-frame daemon's first frame, which is the start of the fade, so
/// the moment is half a fade after that frame reaches the screen. With no write at all the fade
/// is assumed to have started when the command did.
fn moment(written: ?Stamp, started: i64) Moment {
	const at = if (written) |stamp| @divTrunc(stamp.mtime, 1_000_000) else 0;

	if (written != null and at > started) return .{ .at = at, .written = true };
	if (written != null) return .{ .at = at + first_frame_ms + fade_ms / 2, .written = false };

	return .{ .at = started + fade_ms / 2, .written = false };
}


/// A verdict written at the midpoint wins only when it agrees with the colour the switch
/// expects: a wallpaper daemon that still writes per frame leaves a blend there, not a verdict.
fn pickMidpoint(expected: []const u8, written: []const u8) []const u8 {
	if (written.len == 0) return expected;
	if (expected.len == 0) return written;
	if (std.mem.eql(u8, written, expected)) return written;

	return expected;
}

const State = struct {
	bare: bool,
	band: i64,
};

const Stamp = struct {
	mtime: i64,
	size: i64,
};

const Size = struct {
	width: i64,
	height: i64,
};

const Target = struct {
	name: []const u8,
	width: i64,
	height: i64,
};

const Verdict = struct {
	mtime: i64,
	size: i64,
	band: i64,
	width: i64,
	height: i64,
	ink: []u8,
};

pub const Ink = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	mutex: std.Io.Mutex = .init,
	save_mutex: std.Io.Mutex = .init,
	show_mutex: std.Io.Mutex = .init,
	bare: bool = false,
	band: i64 = 0,
	inks: std.StringHashMapUnmanaged([]u8) = .empty,
	verdicts: std.StringHashMapUnmanaged(Verdict) = .empty,
	attempted: std.StringHashMapUnmanaged(Stamp) = .empty,
	out_size: ?Size = null,
	wallpaper: ?*wallpaper.Wallpaper = null,
	generation: std.atomic.Value(u64) = .init(0),
	scans: std.atomic.Value(u64) = .init(0),
	working: std.atomic.Value(bool) = .init(false),

	pub fn create(allocator: Allocator, io: Io, hub: *Hub) !*Ink {
		const self = try allocator.create(Ink);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
		};

		return self;
	}

	pub fn provider(self: *Ink) hubmod.Provider {
		return .{ .key = "ink", .ctx = self, .render = renderThunk };
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Ink = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	pub fn attach(self: *Ink, source: *wallpaper.Wallpaper) void {
		self.wallpaper = source;
	}

	pub fn start(self: *Ink) !void {
		self.openCache();
		self.load();
		_ = self.refresh(null);

		const keeper = try std.Thread.spawn(.{}, keepDaemon, .{self});
		keeper.detach();

		const watcher = try std.Thread.spawn(.{}, watchLoop, .{self});
		watcher.detach();

		if (self.bare) self.reapply();

		self.schedule();
	}

	pub fn set(self: *Ink, band: i64, bare: ?bool) void {
		self.mutex.lockUncancelable(self.io);
		const changed = band > 0 and self.band != band;
		if (band > 0) self.band = band;
		if (bare) |flag| self.bare = flag;
		self.mutex.unlock(self.io);

		self.persist();
		self.hub.publish();

		if (changed) {
			self.reapply();
			self.schedule();
		}
	}

	pub fn apply(self: *Ink, path: []const u8, band: i64) void {
		if (path.len == 0) return;

		self.mutex.lockUncancelable(self.io);
		const changed = band > 0 and self.band != band;
		if (band > 0) self.band = band;
		self.mutex.unlock(self.io);

		if (changed) self.persist();

		self.sync(path);
	}

	fn reapply(self: *Ink) void {
		const source = self.wallpaper orelse return;

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const path = source.activePath(arena.allocator()) orelse return;
		self.sync(path);
	}

	fn sync(self: *Ink, path: []const u8) void {
		const expected = self.switchColour(path);
		const copy = self.allocator.dupe(u8, path) catch return;
		const generation = self.generation.fetchAdd(1, .monotonic) + 1;

		const thread = std.Thread.spawn(.{}, show, .{ self, copy, expected, generation }) catch {
			self.allocator.free(copy);
			return;
		};

		thread.detach();
	}

	fn show(self: *Ink, path: []u8, expected: []const u8, generation: u64) void {
		defer self.allocator.free(path);

		// one wallpaper transition at a time: overlapping `awww img` runs finish out of order
		// and leave whichever drew last on screen
		self.show_mutex.lockUncancelable(self.io);
		defer self.show_mutex.unlock(self.io);

		if (self.generation.load(.monotonic) != generation) return;

		self.mutex.lockUncancelable(self.io);
		const band = self.band;
		self.mutex.unlock(self.io);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();

		var argv: std.ArrayListUnmanaged([]const u8) = .empty;

		argv.appendSlice(allocator, &.{ "awww", "img", "--transition-type", "fade", "--transition-duration", "0.4", "--transition-fps", "60" }) catch return;

		if (band > 0) {
			const rows = std.fmt.allocPrint(allocator, "{d}", .{band}) catch return;
			argv.appendSlice(allocator, &.{ "--ink-band", rows }) catch return;
		}

		argv.append(allocator, path) catch return;

		const stamp = self.stampOf(path);
		const ink = self.inkStamp(allocator);
		const started = fmt.nowMs(self.io);
		const result = exec.run(self.io, self.allocator, argv.items) catch return;
		defer result.deinit(self.allocator);
		std.debug.print("DBG t={d} img code={d} ms={d}\n", .{ fmt.nowMs(self.io), result.code, fmt.nowMs(self.io) - started });

		if (result.code != 0) {
			if (expected.len > 0) self.paint(expected);

			return;
		}

		self.settle(path, stamp, ink, expected, generation, fmt.nowMs(self.io));
	}

	/// Off the apply thread: flip the ink when the wallpaper is half switched, then confirm the
	/// cache once the fade is over.
	fn settle(self: *Ink, path: []const u8, stamp: ?Stamp, ink: ?Stamp, expected: []const u8, generation: u64, started: i64) void {
		const copy = self.allocator.dupe(u8, path) catch return;

		const thread = std.Thread.spawn(.{}, settleThunk, .{ self, copy, stamp, ink, expected, generation, started }) catch {
			self.allocator.free(copy);
			return;
		};

		thread.detach();
	}

	fn settleThunk(self: *Ink, path: []u8, stamp: ?Stamp, ink: ?Stamp, expected: []const u8, generation: u64, started: i64) void {
		defer self.allocator.free(path);

		const written = self.firstInk(ink, generation, started);

		if (self.generation.load(.monotonic) != generation) return;

		const flip = moment(written, started);
		var colour: []const u8 = "";

		if (flip.written) {
			const painted = self.writtenColour(generation) orelse "";

			colour = pickMidpoint(expected, painted);

			if (painted.len > 0 and !std.mem.eql(u8, painted, colour)) {
				std.debug.print("yudaemond: ink midpoint wrote {s} but the switch expects {s}; keeping the measured colour\n", .{ painted, colour });
			}
		} else if (flip.at > fmt.nowMs(self.io)) {
			sleep.ms(@intCast(flip.at - fmt.nowMs(self.io)));
			colour = expected;
		}

		if (self.generation.load(.monotonic) != generation) return;

		if (colour.len > 0) self.paint(colour);

		std.debug.print("yudaemond: ink switch colour={s} from={s} at=+{d}ms\n", .{
			colour,
			if (flip.written) "awww" else "schedule",
			flip.at - started,
		});

		sleep.ms(@intCast(@max(0, flip.at + fade_ms / 2 + confirm_ms - fade_ms - fmt.nowMs(self.io))));

		if (self.generation.load(.monotonic) != generation) return;

		self.awaitInk(ink, generation);

		if (self.generation.load(.monotonic) != generation) return;

		_ = self.refresh(generation);

		self.confirm(path, stamp);
	}

	/// The first write the wallpaper daemon makes after the apply. A daemon that draws its ink on
	/// every frame writes it on the transition's first frame, before `awww img` even returns.
	fn firstInk(self: *Ink, ink: ?Stamp, generation: u64, started: i64) ?Stamp {
		const before = ink orelse return null;

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const path = self.inkPath(arena.allocator()) orelse return null;
		const deadline = started + fade_ms + confirm_ms;

		while (true) {
			if (self.stampOf(path)) |stamp| {
				if (stamp.mtime != before.mtime or stamp.size != before.size) return stamp;
			}

			if (self.generation.load(.monotonic) != generation) return null;
			if (fmt.nowMs(self.io) >= deadline) return null;

			sleep.ms(5);
		}
	}

	fn writtenColour(self: *Ink, generation: u64) ?[]const u8 {
		_ = generation;

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();
		const path = self.inkPath(allocator) orelse return null;

		return self.inkColour(path, allocator);
	}

	fn inkColour(self: *Ink, path: []const u8, allocator: Allocator) ?[]const u8 {
		const raw = proc.readFile(self.io, allocator, path) catch return null;

		return colourOf(raw);
	}

	/// Waits for the transition to write its verdict. A wallpaper daemon that writes per frame
	/// has already done so by the time the fade is over, so only the missing write waits.
	fn awaitInk(self: *Ink, before: ?Stamp, generation: u64) void {
		const wanted = before orelse return;

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const path = self.inkPath(arena.allocator()) orelse return;

		var waited: usize = 0;

		while (waited < ink_wait_ms) : (waited += ink_poll_ms) {
			const now = self.stampOf(path) orelse return;

			if (now.mtime != wanted.mtime or now.size != wanted.size) return;
			if (self.generation.load(.monotonic) != generation) return;

			sleep.ms(ink_poll_ms);
		}
	}

	fn inkPath(self: *Ink, allocator: Allocator) ?[]u8 {
		const name = focused(self.io, allocator);
		if (name.len == 0) return null;

		return std.fmt.allocPrint(allocator, "{s}/{s}{s}", .{ proc.runtimeDir(self.io, allocator), ink_prefix, name }) catch null;
	}

	fn inkStamp(self: *Ink, allocator: Allocator) ?Stamp {
		const path = self.inkPath(allocator) orelse return null;

		return self.stampOf(path);
	}

	/// The colour the switch will land on, known before the fade starts: the cached verdict when
	/// it still holds, otherwise one measurement of the file. It is kept off screen until the
	/// midpoint, so the bar turns with the wall and not before it.
	fn switchColour(self: *Ink, path: []const u8) []const u8 {
		const stamp = self.stampOf(path) orelse return "";

		var colour: []const u8 = "";

		self.mutex.lockUncancelable(self.io);
		if (self.verdicts.get(path)) |verdict| {
			if (fresh(verdict, stamp, self.band, self.out_size)) colour = paintOf(verdict.ink);
		}
		self.mutex.unlock(self.io);

		if (colour.len > 0) return colour;

		return self.measureColour(path, stamp);
	}

	fn measureColour(self: *Ink, path: []const u8, stamp: Stamp) []const u8 {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();
		const band = self.bandNow();
		if (band <= 0) return "";

		const target = self.outputSize(allocator) orelse return "";
		const ink = self.measureInk(path, target, band) orelse return "";

		if (self.store(path, stamp, band, target, ink)) self.saveVerdicts();

		return paintOf(ink);
	}

	fn paint(self: *Ink, colour: []const u8) void {
		var changed = false;

		self.mutex.lockUncancelable(self.io);
		var it = self.inks.iterator();
		while (it.next()) |entry| {
			if (std.mem.eql(u8, entry.value_ptr.*, colour)) continue;

			const copy = self.allocator.dupe(u8, colour) catch continue;
			self.allocator.free(entry.value_ptr.*);
			entry.value_ptr.* = copy;
			changed = true;
		}
		self.mutex.unlock(self.io);

		if (!changed) return;

		self.persist();
		self.hub.publish();
	}

	fn confirm(self: *Ink, path: []const u8, stamp: ?Stamp) void {
		const wanted = stamp orelse return;

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const target = self.outputSize(arena.allocator()) orelse return;

		var ink: []const u8 = "";
		var cached: []const u8 = "";

		self.mutex.lockUncancelable(self.io);
		if (self.inks.get(target.name)) |colour| ink = inkOf(colour) orelse "";
		if (self.verdicts.get(path)) |verdict| {
			const size: Size = .{ .width = target.width, .height = target.height };
			if (fresh(verdict, wanted, self.band, size)) cached = verdict.ink;
		}
		const band = self.band;
		self.mutex.unlock(self.io);

		if (ink.len == 0 or band <= 0) return;

		// a verdict measured on the same file, band and canvas that the fade contradicts is a
		// cache bug, not something to paper over: the bar has to take the measured one
		if (cached.len > 0 and !std.mem.eql(u8, cached, ink)) {
			std.debug.print("yudaemond: ink cache was wrong path={s} cached={s} measured={s} band={d} canvas={d}x{d}\n", .{ path, cached, ink, band, target.width, target.height });
		}

		if (!self.store(path, wanted, band, target, ink)) return;

		self.saveVerdicts();
	}

	fn outputSize(self: *Ink, allocator: Allocator) ?Target {
		var attempt: usize = 0;

		while (attempt < 2) : (attempt += 1) {
			if (self.querySize(allocator)) |target| return target;

			sleep.ms(400);
		}

		return null;
	}

	fn querySize(self: *Ink, allocator: Allocator) ?Target {
		const result = exec.run(self.io, self.allocator, &.{ "awww", "query" }) catch return null;
		defer result.deinit(self.allocator);

		if (result.code != 0) return null;

		const target = targetOf(allocator, result.out, focused(self.io, allocator)) orelse return null;

		// awww frames the wallpaper on the canvas the query reports for that output, so the
		// cached verdict only holds while the output still has that size
		self.mutex.lockUncancelable(self.io);
		self.out_size = .{ .width = target.width, .height = target.height };
		self.mutex.unlock(self.io);

		return target;
	}

	fn measure(self: *Ink, path: []const u8, target: Target, band: i64) void {
		const stamp = self.stampOf(path) orelse return;

		self.remember(path, stamp);

		const ink = self.measureInk(path, target, band) orelse return;

		if (self.store(path, stamp, band, target, ink)) self.saveVerdicts();

		sleep.ms(measure_gap_ms);
	}

	fn measureInk(self: *Ink, path: []const u8, target: Target, band: i64) ?[]const u8 {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();

		const rows = std.fmt.allocPrint(allocator, "{d}", .{@min(band, max_band)}) catch return null;
		const width = std.fmt.allocPrint(allocator, "{d}", .{target.width}) catch return null;
		const height = std.fmt.allocPrint(allocator, "{d}", .{target.height}) catch return null;

		const result = exec.run(self.io, self.allocator, &.{ "awww", "ink", "--width", width, "--height", height, "--band", rows, path }) catch return null;
		defer result.deinit(self.allocator);

		if (result.code != 0) return null;

		return measuredOf(result.out);
	}

	fn plan(self: *Ink, allocator: Allocator, band: i64, target: ?Target) [][]const u8 {
		var out: std.ArrayListUnmanaged([]const u8) = .empty;

		const source = self.wallpaper orelse return out.items;
		const paths = source.paths(allocator) catch return out.items;

		for (paths) |path| {
			const stamp = self.stampOf(path) orelse continue;
			if (self.settled(path, stamp, band, target)) continue;
			if (self.tried(path, stamp)) continue;

			out.append(allocator, path) catch continue;
		}

		self.dropGone(allocator);

		return out.items;
	}

	fn settled(self: *Ink, path: []const u8, stamp: Stamp, band: i64, target: ?Target) bool {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		const verdict = self.verdicts.get(path) orelse return false;

		const size: ?Size = if (target) |want| .{ .width = want.width, .height = want.height } else null;

		return fresh(verdict, stamp, band, size);
	}

	fn tried(self: *Ink, path: []const u8, stamp: Stamp) bool {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		const seen = self.attempted.get(path) orelse return false;

		return seen.mtime == stamp.mtime and seen.size == stamp.size;
	}

	fn remember(self: *Ink, path: []const u8, stamp: Stamp) void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		const key = self.allocator.dupe(u8, path) catch return;

		const entry = self.attempted.getOrPut(self.allocator, key) catch {
			self.allocator.free(key);
			return;
		};

		if (entry.found_existing) self.allocator.free(key);

		entry.value_ptr.* = stamp;
	}

	fn store(self: *Ink, path: []const u8, stamp: Stamp, band: i64, target: Target, ink: []const u8) bool {
		const next: Verdict = .{
			.mtime = stamp.mtime,
			.size = stamp.size,
			.band = band,
			.width = target.width,
			.height = target.height,
			.ink = self.allocator.dupe(u8, ink) catch return false,
		};

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		if (self.verdicts.getPtr(path)) |slot| {
			if (sameVerdict(slot.*, next)) {
				self.allocator.free(next.ink);
				return false;
			}

			self.allocator.free(slot.ink);
			slot.* = next;
			return true;
		}

		const key = self.allocator.dupe(u8, path) catch {
			self.allocator.free(next.ink);
			return false;
		};

		self.verdicts.put(self.allocator, key, next) catch {
			self.allocator.free(key);
			self.allocator.free(next.ink);
			return false;
		};

		return true;
	}

	fn drop(self: *Ink, path: []const u8) void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		if (self.verdicts.fetchRemove(path)) |entry| {
			self.allocator.free(entry.key);
			self.allocator.free(entry.value.ink);
		}

		if (self.attempted.fetchRemove(path)) |entry| self.allocator.free(entry.key);
	}

	/// Drops the cache entries of wallpapers that are gone, so a deleted file does not keep a
	/// verdict the next wallpaper of the same name would inherit.
	fn dropGone(self: *Ink, allocator: Allocator) void {
		var gone: std.ArrayListUnmanaged([]const u8) = .empty;

		self.mutex.lockUncancelable(self.io);
		var it = self.verdicts.keyIterator();
		while (it.next()) |key| {
			if (proc.exists(self.io, key.*)) continue;
			gone.append(allocator, allocator.dupe(u8, key.*) catch continue) catch continue;
		}
		self.mutex.unlock(self.io);

		if (gone.items.len == 0) return;

		std.debug.print("DBG ink drop gone={d}\n", .{gone.items.len});

		for (gone.items) |path| self.drop(path);

		self.saveVerdicts();
	}

	fn stampOf(self: *Ink, path: []const u8) ?Stamp {
		const stat = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch return null;

		return .{ .mtime = @intCast(stat.mtime.nanoseconds), .size = @intCast(stat.size) };
	}

	pub fn rescanned(ctx: *anyopaque) void {
		const self: *Ink = @ptrCast(@alignCast(ctx));

		self.schedule();
	}

	/// A pass that is already running picks the scan up on its next round; one that is just
	/// finishing restarts, so a scan landing between the last round and the exit is not lost.
	fn schedule(self: *Ink) void {
		_ = self.scans.fetchAdd(1, .monotonic);

		self.ensureWorker();
	}

	fn ensureWorker(self: *Ink) void {
		if (self.working.swap(true, .acquire)) return;

		const thread = std.Thread.spawn(.{}, workLoop, .{self}) catch {
			self.working.store(false, .release);
			return;
		};

		thread.detach();
	}

	fn workLoop(self: *Ink) void {
		var seen = self.scans.load(.monotonic);

		while (true) {
			if (!self.round()) continue;
			if (self.scans.load(.monotonic) == seen) break;

			seen = self.scans.load(.monotonic);
		}

		self.working.store(false, .release);

		if (self.scans.load(.monotonic) != seen) self.ensureWorker();
	}

	/// Measures one wallpaper per pass, at a gentle rate, so the daemon stays cheap while the
	/// cache fills. Returns true when there is nothing left to measure.
	fn round(self: *Ink) bool {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();
		const target = self.outputSize(allocator);

		const band = self.bandNow();
		const jobs = self.plan(allocator, band, target);

		if (jobs.len == 0) return true;
		if (target == null or band <= 0) return true;

		for (jobs) |path| self.measure(path, target.?, band);

		return false;
	}

	fn bandNow(self: *Ink) i64 {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		return self.band;
	}

	fn saveVerdicts(self: *Ink) void {
		self.save_mutex.lockUncancelable(self.io);
		defer self.save_mutex.unlock(self.io);

		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();
		const path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ proc.home(self.io, self.allocator), verdict_file }) catch return;

		const body = self.verdictBody(allocator) orelse return;
		proc.writeFileAtomic(self.io, self.allocator, path, body) catch return;
	}

	fn verdictBody(self: *Ink, allocator: Allocator) ?[]const u8 {
		var buffer: Writer.Allocating = .init(allocator);

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		buffer.writer.writeAll("{\"files\":{") catch return null;

		var first = true;
		var it = self.verdicts.iterator();

		while (it.next()) |entry| {
			if (!first) buffer.writer.writeAll(",") catch return null;
			first = false;

			json.write(&buffer.writer, entry.key_ptr.*) catch return null;
			buffer.writer.writeAll(":") catch return null;
			writeVerdict(&buffer.writer, entry.value_ptr.*) catch return null;
		}

		buffer.writer.writeAll("}}") catch return null;

		return buffer.toOwnedSlice() catch null;
	}

	fn refresh(self: *Ink, generation: ?u64) bool {
		if (generation) |wanted| {
			if (self.generation.load(.monotonic) != wanted) return false;
		}

		if (!self.readInks()) return false;

		self.persist();
		self.hub.publish();

		return true;
	}

	/// Rebuilds the per-output ink map from the `awww-ink-<output>` files the wallpaper daemon
	/// writes when it measures a frame. Each file holds `black` or `white`; the bar paints the
	/// pure colour, exactly like the QML singleton did before the port.
	fn readInks(self: *Ink) bool {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();
		const dir_path = proc.runtimeDir(self.io, allocator);

		var dir = std.Io.Dir.cwd().openDir(self.io, dir_path, .{ .iterate = true }) catch return false;
		defer dir.close(self.io);

		var next: std.StringHashMapUnmanaged([]u8) = .empty;

		var it = dir.iterate();
		while (it.next(self.io) catch null) |item| {
			if (item.kind != .file) continue;
			if (!std.mem.startsWith(u8, item.name, ink_prefix)) continue;

			const path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, item.name }) catch continue;
			const raw = proc.readFile(self.io, allocator, path) catch continue;
			const colour = colourOf(raw) orelse continue;

			const key = self.allocator.dupe(u8, item.name[ink_prefix.len..]) catch continue;
			const value = self.allocator.dupe(u8, colour) catch {
				self.allocator.free(key);
				continue;
			};

			next.put(self.allocator, key, value) catch {
				self.allocator.free(key);
				self.allocator.free(value);
			};
		}

		if (outputs(self.io, allocator)) |live| _ = prune(self.allocator, &next, live);

		self.mutex.lockUncancelable(self.io);

		const same = sameInks(&self.inks, &next);

		if (!same) {
			var old = self.inks.iterator();
			while (old.next()) |entry| {
				self.allocator.free(entry.key_ptr.*);
				self.allocator.free(entry.value_ptr.*);
			}
			self.inks.deinit(self.allocator);
			self.inks = next;
		}

		self.mutex.unlock(self.io);

		if (same) {
			var stale = next.iterator();
			while (stale.next()) |entry| {
				self.allocator.free(entry.key_ptr.*);
				self.allocator.free(entry.value_ptr.*);
			}
			next.deinit(self.allocator);
		}

		return !same;
	}

	fn watchLoop(self: *Ink) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();
		const dir_path = proc.runtimeDir(self.io, allocator);
		const dir = allocator.allocSentinel(u8, dir_path.len, 0) catch return;
		@memcpy(dir, dir_path);

		var watcher = watch.Watcher.init() catch return;
		defer watcher.close();

		watcher.add(dir) catch return;

		var debounce: watch.Debounce = .{};

		while (true) {
			const name = watcher.next() catch {
				sleep.ms(1000);
				continue;
			};

			if (!std.mem.startsWith(u8, name, ink_prefix)) continue;

			// awww writes once per drawn frame through the fade; only the write that is left
			// after the burst is the verdict, so wait until the writes stop
			debounce.note(fmt.nowMs(self.io));
			self.awaitQuiet(&watcher, &debounce);
			_ = self.refresh(null);
		}
	}

	fn awaitQuiet(self: *Ink, watcher: *watch.Watcher, debounce: *watch.Debounce) void {
		while (true) {
			const now = fmt.nowMs(self.io);

			if (debounce.due(now)) return;

			sleep.ms(40);

			if (!watcher.pending()) continue;

			_ = watcher.next() catch return;
			debounce.note(fmt.nowMs(self.io));
		}
	}

	fn persist(self: *Ink) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();
		const path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ proc.home(self.io, self.allocator), state_file }) catch return;

		const body = self.stateBody(allocator) orelse return;
		proc.writeFileAtomic(self.io, self.allocator, path, body) catch return;
	}

	fn stateBody(self: *Ink, allocator: Allocator) ?[]const u8 {
		var buffer: Writer.Allocating = .init(allocator);

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		buffer.writer.print("{{\"bare\":{s},\"band\":{d},", .{
			if (self.bare) "true" else "false",
			self.band,
		}) catch return null;

		self.writeInks(&buffer.writer, allocator) catch return null;
		buffer.writer.writeAll("}") catch return null;

		return buffer.toOwnedSlice() catch null;
	}

	fn writeInks(self: *Ink, writer: *Writer, allocator: Allocator) !void {
		var keys: std.ArrayListUnmanaged([]const u8) = .empty;
		defer keys.deinit(allocator);

		var it = self.inks.iterator();
		while (it.next()) |entry| keys.append(allocator, entry.key_ptr.*) catch {};

		std.mem.sort([]const u8, keys.items, {}, lessThan);

		try writer.writeAll("\"inks\":{");

		for (keys.items, 0..) |key, index| {
			const value = self.inks.get(key) orelse continue;

			if (index > 0) try writer.writeAll(",");

			try json.write(writer, key);
			try writer.writeAll(":");
			try json.write(writer, value);
		}

		try writer.writeAll("},\"verdicts\":{");

		for (keys.items, 0..) |key, index| {
			const value = self.inks.get(key) orelse continue;

			if (index > 0) try writer.writeAll(",");

			try json.write(writer, key);
			try writer.writeAll(":");
			try json.write(writer, if (std.mem.eql(u8, value, black_ink)) "black" else "white");
		}

		try writer.writeAll("}");
	}

	fn load(self: *Ink) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();
		const path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ proc.home(self.io, self.allocator), state_file }) catch return;

		const raw = proc.readFile(self.io, allocator, path) catch return;
		const parsed = json.parse(allocator, raw) catch return;
		const state = stateOf(parsed.value);

		self.mutex.lockUncancelable(self.io);
		self.bare = state.bare;
		self.band = state.band;

		if (json.field(parsed.value, "inks")) |inks| {
			if (inks == .object) {
				var it = inks.object.iterator();
				while (it.next()) |entry| {
					const key = self.allocator.dupe(u8, entry.key_ptr.*) catch continue;
					const value = self.allocator.dupe(u8, json.text(entry.value_ptr.*)) catch {
						self.allocator.free(key);
						continue;
					};
					self.inks.put(self.allocator, key, value) catch {
						self.allocator.free(key);
						self.allocator.free(value);
					};
				}
			}
		}

		self.mutex.unlock(self.io);

		self.pruneOutputs();
		self.loadVerdicts();
	}

	/// An output that is gone from Hyprland is gone for good, but its ink file outlives the
	/// session that wrote it, so the cache only keeps the outputs Hyprland reports right now.
	fn pruneOutputs(self: *Ink) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const live = outputs(self.io, arena.allocator()) orelse return;

		self.mutex.lockUncancelable(self.io);
		const dropped = prune(self.allocator, &self.inks, live);
		self.mutex.unlock(self.io);

		if (dropped == 0) return;

		self.persist();
	}

	fn openCache(self: *Ink) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const dir = std.fmt.allocPrint(arena.allocator(), "{s}/.config/quickshell/yudaemond/cache", .{proc.home(self.io, self.allocator)}) catch return;

		std.Io.Dir.cwd().createDirPath(self.io, dir) catch {};
	}

	fn loadVerdicts(self: *Ink) void {
		var arena = std.heap.ArenaAllocator.init(self.allocator);
		defer arena.deinit();

		const allocator = arena.allocator();
		const path = std.fmt.allocPrint(allocator, "{s}/{s}", .{ proc.home(self.io, self.allocator), verdict_file }) catch return;

		const raw = proc.readFile(self.io, allocator, path) catch return;
		const parsed = json.parse(allocator, raw) catch return;

		const files = json.field(parsed.value, "files") orelse return;
		if (files != .object) return;

		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		var it = files.object.iterator();
		while (it.next()) |entry| {
			const verdict = verdictOf(allocator, entry.value_ptr.*) orelse continue;

			const key = self.allocator.dupe(u8, entry.key_ptr.*) catch continue;
			const ink = self.allocator.dupe(u8, verdict.ink) catch {
				self.allocator.free(key);
				continue;
			};

			self.verdicts.put(self.allocator, key, .{
				.mtime = verdict.mtime,
				.size = verdict.size,
				.band = verdict.band,
				.width = verdict.width,
				.height = verdict.height,
				.ink = ink,
			}) catch {
				self.allocator.free(key);
				self.allocator.free(ink);
			};
		}
	}

	fn keepDaemon(self: *Ink) void {
		while (true) {
			if (self.daemonAlive()) {
				sleep.ms(5000);
				continue;
			}

			self.runDaemon();
			sleep.ms(1000);
		}
	}

	fn daemonAlive(self: *Ink) bool {
		const display = proc.env(self.io, self.allocator, "WAYLAND_DISPLAY") orelse return true;

		const path = std.fmt.allocPrint(self.allocator, "{s}/{s}-awww-daemon.sock", .{ proc.runtimeDir(self.io, self.allocator), display }) catch return true;
		defer self.allocator.free(path);

		return proc.exists(self.io, path);
	}

	fn runDaemon(self: *Ink) void {
		var child = std.process.spawn(self.io, .{
			.argv = &.{daemon_bin},
			.stdin = .ignore,
			.stdout = .ignore,
			.stderr = .ignore,
		}) catch {
			sleep.ms(5000);
			return;
		};

		_ = child.wait(self.io) catch {};
	}

	fn render(self: *Ink, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		try writer.print("{{\"bare\":{s},\"band\":{d},", .{
			if (self.bare) "true" else "false",
			self.band,
		});

		try self.writeInks(writer, self.allocator);
		try writer.writeAll("}");
	}
};

fn stateOf(root: json.Value) State {
	return .{
		.bare = json.flag(root, "bare"),
		.band = json.integer(json.field(root, "band")),
	};
}

/// The runtime file awww writes holds `black` or `white`; the bar paints that colour purely,
/// with no tint of its own.
fn colourOf(raw: []const u8) ?[]const u8 {
	const text_ = std.mem.trim(u8, raw, " \t\r\n");

	if (std.mem.eql(u8, text_, "black")) return black_ink;
	if (std.mem.eql(u8, text_, "white")) return white_ink;

	return null;
}

/// A verdict only holds for the same file and the same measurement: the band is global, so a
/// band change invalidates every entry, and a mode change invalidates the ones measured at the
/// old output size. Passing no target skips the size when the caller cannot know it yet.
fn fresh(verdict: Verdict, stamp: Stamp, band: i64, size: ?Size) bool {
	if (verdict.mtime != stamp.mtime) return false;
	if (verdict.size != stamp.size) return false;
	if (verdict.band != band) return false;

	if (size) |want| {
		if (verdict.width != want.width or verdict.height != want.height) return false;
	}

	return true;
}

fn sameVerdict(a: Verdict, b: Verdict) bool {
	return a.mtime == b.mtime and a.size == b.size and a.band == b.band and
		a.width == b.width and a.height == b.height and std.mem.eql(u8, a.ink, b.ink);
}

fn paintOf(ink: []const u8) []const u8 {
	return if (std.mem.eql(u8, ink, ink_black)) black_ink else white_ink;
}

fn inkOf(colour: []const u8) ?[]const u8 {
	if (std.mem.eql(u8, colour, black_ink)) return ink_black;
	if (std.mem.eql(u8, colour, white_ink)) return ink_white;

	return null;
}

/// `awww ink` prints the verdict and the band's mean luminance; only the verdict is kept.
fn measuredOf(raw: []const u8) ?[]const u8 {
	var words = std.mem.tokenizeAny(u8, raw, " \t\r\n");

	const first = words.next() orelse return null;

	if (std.mem.eql(u8, first, ink_black)) return ink_black;
	if (std.mem.eql(u8, first, ink_white)) return ink_white;

	return null;
}

/// `awww query` prints one line per output: `: DP-2: 1920x1080, scale: 1.3333334, ...`. The
/// size is the canvas awww draws on, which is what `awww ink` has to be told to match it, and
/// the line that counts is the output the wallpaper is shown on, not whichever line comes first.
fn targetOf(allocator: Allocator, raw: []const u8, wanted: []const u8) ?Target {
	var fallback: ?Target = null;

	var lines = std.mem.splitScalar(u8, raw, '\n');

	while (lines.next()) |line| {
		const opened = std.mem.indexOf(u8, line, ": ") orelse continue;
		const rest = line[opened + 2 ..];
		const stop = std.mem.indexOfScalar(u8, rest, ',') orelse rest.len;
		const head = rest[0..stop];

		const split = std.mem.lastIndexOf(u8, head, ": ") orelse continue;
		const name = std.mem.trim(u8, head[0..split], " \t");
		const dim = head[split + 2 ..];

		const x = std.mem.indexOfScalar(u8, dim, 'x') orelse continue;
		const width = std.fmt.parseInt(i64, dim[0..x], 10) catch continue;
		const height = std.fmt.parseInt(i64, dim[x + 1 ..], 10) catch continue;

		if (name.len == 0 or width <= 0 or height <= 0) continue;

		const target: Target = .{
			.name = allocator.dupe(u8, name) catch return null,
			.width = width,
			.height = height,
		};

		if (wanted.len > 0 and std.mem.eql(u8, name, wanted)) return target;
		if (fallback == null) fallback = target;
	}

	return fallback;
}

fn focused(io: Io, allocator: Allocator) []const u8 {
	const raw = hypr.request(io, allocator, "j/monitors") catch return "";
	const parsed = json.parse(allocator, raw) catch return "";

	for (json.list(parsed.value)) |monitor| {
		if (!json.flag(monitor, "focused")) continue;

		return json.textAt(monitor, "name");
	}

	return "";
}

/// The outputs Hyprland is driving now. Null when the answer is unknown, because a failed query
/// must not be read as "every output is gone" and wipe the cache.
fn outputs(io: Io, allocator: Allocator) ?[][]const u8 {
	const raw = hypr.request(io, allocator, "j/monitors") catch return null;

	return monitorNames(allocator, raw);
}

fn monitorNames(allocator: Allocator, raw: []const u8) ?[][]const u8 {
	const parsed = json.parse(allocator, raw) catch return null;

	var names: std.ArrayListUnmanaged([]const u8) = .empty;

	for (json.list(parsed.value)) |monitor| {
		const name = json.textAt(monitor, "name");
		if (name.len == 0) continue;

		names.append(allocator, name) catch return null;
	}

	if (names.items.len == 0) return null;

	return names.items;
}

fn prune(allocator: Allocator, inks: *std.StringHashMapUnmanaged([]u8), live: []const []const u8) usize {
	var gone: std.ArrayListUnmanaged([]const u8) = .empty;

	var it = inks.keyIterator();
	while (it.next()) |key| {
		var known = false;

		for (live) |name| {
			if (!std.mem.eql(u8, name, key.*)) continue;

			known = true;
			break;
		}

		if (known) continue;

		gone.append(allocator, key.*) catch return 0;
	}

	for (gone.items) |key| {
		if (inks.fetchRemove(key)) |entry| {
			allocator.free(entry.key);
			allocator.free(entry.value);
		}
	}

	return gone.items.len;
}

fn verdictOf(allocator: Allocator, value: json.Value) ?Verdict {
	const ink = json.textAt(value, "ink");

	if (!std.mem.eql(u8, ink, ink_black) and !std.mem.eql(u8, ink, ink_white)) return null;

	return .{
		.mtime = json.integer(json.field(value, "mtime")),
		.size = json.integer(json.field(value, "size")),
		.band = json.integer(json.field(value, "band")),
		.width = json.integer(json.field(value, "width")),
		.height = json.integer(json.field(value, "height")),
		.ink = allocator.dupe(u8, ink) catch return null,
	};
}

fn writeVerdict(writer: *Writer, verdict: Verdict) !void {
	try writer.print("{{\"mtime\":{d},\"size\":{d},\"band\":{d},\"width\":{d},\"height\":{d},\"ink\":", .{
		verdict.mtime,
		verdict.size,
		verdict.band,
		verdict.width,
		verdict.height,
	});

	try json.write(writer, verdict.ink);
	try writer.writeAll("}");
}

fn sameInks(a: *const std.StringHashMapUnmanaged([]u8), b: *const std.StringHashMapUnmanaged([]u8)) bool {
	if (a.count() != b.count()) return false;

	var it = a.iterator();
	while (it.next()) |entry| {
		const other = b.get(entry.key_ptr.*) orelse return false;
		if (!std.mem.eql(u8, entry.value_ptr.*, other)) return false;
	}

	return true;
}

fn lessThan(_: void, a: []const u8, b: []const u8) bool {
	return std.mem.lessThan(u8, a, b);
}

test "the ink flips when the wallpaper is half switched" {
	const half = Moment.after(1000);

	try std.testing.expectEqual(@as(i64, 1200), half.at);
	try std.testing.expectEqual(@as(u64, 200), half.wait(1000));
	try std.testing.expectEqual(@as(u64, 50), half.wait(1150));
	try std.testing.expectEqual(@as(u64, 0), half.wait(1300));
}

test "the switch flips on the verdict write when it lands after the fade started" {
	const late = moment(.{ .mtime = 1200 * 1_000_000, .size = 5 }, 1000);
	try std.testing.expect(late.written);
	try std.testing.expectEqual(@as(i64, 1200), late.at);

	const early = moment(.{ .mtime = 960 * 1_000_000, .size = 5 }, 1000);
	try std.testing.expect(!early.written);
	try std.testing.expectEqual(@as(i64, 960 + first_frame_ms + fade_ms / 2), early.at);

	const none = moment(null, 1000);
	try std.testing.expect(!none.written);
	try std.testing.expectEqual(@as(i64, 1200), none.at);
}

test "a midpoint write wins only when it agrees with the colour the switch expects" {
	try std.testing.expectEqualStrings(black_ink, pickMidpoint(black_ink, black_ink));
	try std.testing.expectEqualStrings(black_ink, pickMidpoint(black_ink, white_ink));
	try std.testing.expectEqualStrings(black_ink, pickMidpoint(black_ink, ""));
	try std.testing.expectEqualStrings(white_ink, pickMidpoint("", white_ink));
	try std.testing.expectEqualStrings("", pickMidpoint("", ""));
}

test "the stored state keeps the band and the bare flag" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const parsed = try json.parse(arena.allocator(), "{\"bare\":true,\"band\":33}");
	const state = stateOf(parsed.value);

	try std.testing.expect(state.bare);
	try std.testing.expectEqual(@as(i64, 33), state.band);

	const empty = try json.parse(arena.allocator(), "{}");
	try std.testing.expect(!stateOf(empty.value).bare);
}

test "the awww ink file maps to the pure colour the bar paints" {
	try std.testing.expectEqualStrings("#000000", colourOf("black\n").?);
	try std.testing.expectEqualStrings("#ffffff", colourOf(" white ").?);

	try std.testing.expect(colourOf("purple") == null);
	try std.testing.expect(colourOf("") == null);
}

test "the ink map keeps every output" {
	var a: std.StringHashMapUnmanaged([]u8) = .empty;
	defer a.deinit(std.testing.allocator);
	var b: std.StringHashMapUnmanaged([]u8) = .empty;
	defer b.deinit(std.testing.allocator);

	const key = try std.testing.allocator.dupe(u8, "DP-2");
	const value = try std.testing.allocator.dupe(u8, "#ffffff");
	defer std.testing.allocator.free(key);
	defer std.testing.allocator.free(value);
	try a.put(std.testing.allocator, key, value);

	try std.testing.expectEqual(false, sameInks(&a, &b));

	const key2 = try std.testing.allocator.dupe(u8, "DP-2");
	const value2 = try std.testing.allocator.dupe(u8, "#ffffff");
	defer std.testing.allocator.free(key2);
	defer std.testing.allocator.free(value2);
	try b.put(std.testing.allocator, key2, value2);

	try std.testing.expect(sameInks(&a, &b));
}

test "a cached verdict only holds for the file, band and size it was measured with" {
	const verdict: Verdict = .{
		.mtime = 100,
		.size = 4096,
		.band = 33,
		.width = 1920,
		.height = 1080,
		.ink = @constCast(ink_black),
	};

	const stamp: Stamp = .{ .mtime = 100, .size = 4096 };
	const target: Size = .{ .width = 1920, .height = 1080 };

	try std.testing.expect(fresh(verdict, stamp, 33, target));
	try std.testing.expect(fresh(verdict, stamp, 33, null));

	try std.testing.expect(!fresh(verdict, .{ .mtime = 101, .size = 4096 }, 33, target));
	try std.testing.expect(!fresh(verdict, .{ .mtime = 100, .size = 8192 }, 33, target));
	try std.testing.expect(!fresh(verdict, stamp, 34, target));
	try std.testing.expect(!fresh(verdict, stamp, 33, .{ .width = 1280, .height = 720 }));
}

test "a verdict survives the round trip through the cache file" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();

	var buffer: Writer.Allocating = .init(allocator);
	try writeVerdict(&buffer.writer, .{
		.mtime = 17,
		.size = 8192,
		.band = 33,
		.width = 1920,
		.height = 1080,
		.ink = @constCast(ink_white),
	});

	const body = try buffer.toOwnedSlice();
	const parsed = try json.parse(allocator, body);
	const verdict = verdictOf(allocator, parsed.value).?;

	try std.testing.expectEqual(@as(i64, 17), verdict.mtime);
	try std.testing.expectEqual(@as(i64, 8192), verdict.size);
	try std.testing.expectEqual(@as(i64, 33), verdict.band);
	try std.testing.expectEqual(@as(i64, 1920), verdict.width);
	try std.testing.expectEqualStrings(ink_white, verdict.ink);

	const broken = try json.parse(allocator, "{\"mtime\":1,\"ink\":\"purple\"}");
	try std.testing.expect(verdictOf(allocator, broken.value) == null);
}

test "the measurement reads back from awww ink and awww query" {
	try std.testing.expectEqualStrings(ink_black, measuredOf("black 0.0521\n").?);
	try std.testing.expectEqualStrings(ink_white, measuredOf(" white 0.9102 ").?);
	try std.testing.expect(measuredOf("") == null);
	try std.testing.expect(measuredOf("error: no such file") == null);

	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const line = ": DP-2: 1920x1080, scale: 1.3333334, currently displaying: image: /home/me/wall.png, ink: black (#484953)";
	const target = targetOf(arena.allocator(), line, "").?;

	try std.testing.expectEqualStrings("DP-2", target.name);
	try std.testing.expectEqual(@as(i64, 1920), target.width);
	try std.testing.expectEqual(@as(i64, 1080), target.height);

	try std.testing.expect(targetOf(arena.allocator(), "nothing here", "") == null);

	const both = ": eDP-1: 1280x720, scale: 1.0, currently displaying: image: /home/me/wall.png, ink: white (#e2e2e2)\n" ++ line;
	const shown = targetOf(arena.allocator(), both, "DP-2").?;

	try std.testing.expectEqualStrings("DP-2", shown.name);
	try std.testing.expectEqual(@as(i64, 1920), shown.width);
	try std.testing.expectEqual(@as(i64, 1280), targetOf(arena.allocator(), both, "").?.width);
}

test "the live outputs come from the hypr monitor list" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const raw = "[{\"name\":\"DP-2\",\"focused\":true},{\"name\":\"eDP-1\",\"focused\":false}]";
	const names = monitorNames(arena.allocator(), raw).?;

	try std.testing.expectEqual(@as(usize, 2), names.len);
	try std.testing.expectEqualStrings("DP-2", names[0]);

	try std.testing.expect(monitorNames(arena.allocator(), "[]") == null);
	try std.testing.expect(monitorNames(arena.allocator(), "not json") == null);
}

test "a stale output is pruned and a live one kept" {
	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const allocator = arena.allocator();

	var inks: std.StringHashMapUnmanaged([]u8) = .empty;
	defer inks.deinit(allocator);

	try inks.put(allocator, try allocator.dupe(u8, "WAYLAND-9"), try allocator.dupe(u8, black_ink));
	try inks.put(allocator, try allocator.dupe(u8, "DP-2"), try allocator.dupe(u8, white_ink));

	const live = [_][]const u8{ "DP-2", "eDP-1" };

	try std.testing.expectEqual(@as(usize, 1), prune(allocator, &inks, &live));
	try std.testing.expect(inks.get("WAYLAND-9") == null);
	try std.testing.expectEqualStrings(white_ink, inks.get("DP-2").?);
}
