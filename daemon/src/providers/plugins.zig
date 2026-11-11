const std = @import("std");
const hubmod = @import("../hub.zig");
const configmod = @import("../primitives/config.zig");
const exec = @import("../primitives/exec.zig");
const hypr = @import("../primitives/hypr.zig");
const proc = @import("../primitives/proc.zig");
const notifications = @import("notifications.zig");
const config_provider = @import("config.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Writer = std.Io.Writer;
const Hub = hubmod.Hub;

const manifest_keys = [_][]const u8{ "id", "kind", "version", "requires", "build", "provides" };
const template_prefix = "_template";

pub const Kind = enum { hypr, theme, shell, app, daemon };

pub const Paths = struct {
	load: []const u8,
	repo: []const u8,
	data: []const u8,
	state: []const u8,

	pub fn loaded(self: Paths, allocator: Allocator) ![]u8 {
		return std.fmt.allocPrint(allocator, "{s}/loaded.lua", .{self.state});
	}

	pub fn theme(self: Paths, allocator: Allocator) ![]u8 {
		return std.fmt.allocPrint(allocator, "{s}/theme.toml", .{self.state});
	}

	pub fn build(self: Paths, allocator: Allocator, id: []const u8) ![]u8 {
		return std.fmt.allocPrint(allocator, "{s}/build/{s}", .{ self.state, id });
	}

	pub fn commit(self: Paths, allocator: Allocator, id: []const u8) ![]u8 {
		return std.fmt.allocPrint(allocator, "{s}/commits/{s}", .{ self.state, id });
	}
};

pub const Row = struct {
	id: []const u8,
	kind: []const u8,
	version: []const u8,
	source: []const u8,
	dir: []const u8,
	out: []const u8,
	commit: []const u8,
	entry: []const u8,
	load: bool,
	state: []const u8,
	failure: []const u8,
};

pub const ThemeRow = struct {
	id: []const u8,
	active: bool,
	surface: []const u8,
	foreground: []const u8,
	accents: []const []const u8,
};

const accent_keys = [_][]const u8{ "borderFallbackColor", "cpuBase", "memoryBase", "weatherBase", "yellow", "red" };

const Out = struct {
	list: []const Row,
	themes: []const ThemeRow,
	hyprland: []const u8,
	failure: []const u8,
};

const Manifest = struct {
	id: []const u8,
	kind: Kind,
	version: []const u8,
	build: []const u8,
	provides: []const []const u8,
	hyprland: []const u8,
};

const Loaded = struct {
	manifest: Manifest,
	dir: []const u8,
	out: []const u8,
	options: ?configmod.Value,
};

const Candidate = struct {
	row: Row,
	manifest: Manifest,
	options: ?configmod.Value,
};

const Color = struct {
	key: []const u8,
	value: []const u8,
	flag: ?bool = null,
};

const Section = struct {
	name: []const u8,
	entries: []const Color,
};

const Theme = struct {
	sections: []const Section,
};

const MergeSection = struct {
	name: []const u8,
	entries: std.ArrayListUnmanaged(Color) = .empty,
};

const SourceFile = struct {
	path: []const u8,
	digest: [32]u8,
};

pub const Plugins = struct {
	allocator: Allocator,
	io: Io,
	hub: *Hub,
	notes: ?*notifications.Notifications,
	config: ?*config_provider.Config = null,
	paths: Paths,
	live: bool = true,
	mutex: std.Io.Mutex = .init,
	scratch: std.heap.ArenaAllocator,
	rows: []const Row = &.{},
	themes: []const ThemeRow = &.{},
	hyprland: []const u8 = &.{},
	error_text: []const u8 = &.{},

	pub fn create(allocator: Allocator, io: Io, hub: *Hub, notes: ?*notifications.Notifications) !*Plugins {
		return createAt(allocator, io, hub, notes, defaultPaths(io, allocator));
	}

	pub fn createAt(allocator: Allocator, io: Io, hub: *Hub, notes: ?*notifications.Notifications, paths: Paths) !*Plugins {
		const self = try allocator.create(Plugins);
		self.* = .{
			.allocator = allocator,
			.io = io,
			.hub = hub,
			.notes = notes,
			.paths = paths,
			.scratch = std.heap.ArenaAllocator.init(allocator),
		};

		return self;
	}

	pub fn provider(self: *Plugins) hubmod.Provider {
		return .{ .key = "plugins", .ctx = self, .render = renderThunk };
	}

	pub fn attachConfig(self: *Plugins, config: *config_provider.Config) void {
		self.config = config;
	}

	fn renderThunk(ctx: *anyopaque, writer: *Writer) anyerror!void {
		const self: *Plugins = @ptrCast(@alignCast(ctx));
		try self.render(writer);
	}

	fn render(self: *Plugins, writer: *Writer) !void {
		self.mutex.lockUncancelable(self.io);
		defer self.mutex.unlock(self.io);

		const out = Out{ .list = self.rows, .themes = self.themes, .hyprland = self.hyprland, .failure = self.error_text };
		try writer.print("{f}", .{std.json.fmt(out, .{})});
	}

	pub fn start(self: *Plugins) !void {
		const thread = try std.Thread.spawn(.{}, startThread, .{self});
		thread.detach();
	}

	fn startThread(self: *Plugins) void {
		self.reload();
	}

	pub fn reload(self: *Plugins) void {
		self.mutex.lockUncancelable(self.io);
		self.reloadLocked();
		self.mutex.unlock(self.io);

		self.hub.publish();
		self.reloadConfig();
	}

	fn reloadConfig(self: *Plugins) void {
		if (self.config) |config| config.reload();
	}

	pub fn call(self: *Plugins, method: []const u8, args: std.json.Value, allocator: Allocator) ![]u8 {
		if (std.mem.eql(u8, method, "list")) {
			self.mutex.lockUncancelable(self.io);
			defer self.mutex.unlock(self.io);

			return self.listJson(allocator);
		}

		if (std.mem.eql(u8, method, "reload")) {
			self.mutex.lockUncancelable(self.io);
			self.reloadLocked();
			self.mutex.unlock(self.io);
			self.hub.publish();
			self.reloadConfig();

			return allocator.dupe(u8, "{\"ok\":true}");
		}

		const id = jsonText(args, "id");
		const url = jsonText(args, "url");

		if (std.mem.eql(u8, method, "build")) {
			if (id.len == 0) return error.MissingArgs;

			self.mutex.lockUncancelable(self.io);
			self.buildOneLocked(id) catch |err| {
				self.mutex.unlock(self.io);
				return err;
			};
			self.mutex.unlock(self.io);
			self.hub.publish();
			self.reloadConfig();

			return allocator.dupe(u8, "{\"ok\":true}");
		}

		const theme = std.mem.eql(u8, method, "theme");

		if (theme or std.mem.eql(u8, method, "load") or std.mem.eql(u8, method, "unload")) {
			if (id.len == 0) return error.MissingArgs;

			self.mutex.lockUncancelable(self.io);
			(if (theme) self.setThemeLocked(id) else self.editListLocked(id, std.mem.eql(u8, method, "load"))) catch |err| {
				self.mutex.unlock(self.io);
				return err;
			};
			self.reloadLocked();
			const body = self.loadListJson(allocator) catch |err| {
				self.mutex.unlock(self.io);
				return err;
			};
			self.mutex.unlock(self.io);
			self.hub.publish();
			self.reloadConfig();

			return body;
		}

		if (std.mem.eql(u8, method, "add")) {
			if (url.len == 0) return error.MissingArgs;

			self.mutex.lockUncancelable(self.io);
			const summary = self.addLocked(url, allocator) catch |err| {
				self.mutex.unlock(self.io);
				return err;
			};
			self.reloadLocked();
			self.mutex.unlock(self.io);
			self.hub.publish();
			self.reloadConfig();

			return summary;
		}

		if (std.mem.eql(u8, method, "update")) {
			if (id.len == 0) return error.MissingArgs;

			self.mutex.lockUncancelable(self.io);
			const summary = self.updateLocked(id, allocator) catch |err| {
				self.mutex.unlock(self.io);
				return err;
			};
			self.reloadLocked();
			self.mutex.unlock(self.io);
			self.hub.publish();
			self.reloadConfig();

			return summary;
		}

		return error.UnknownMethod;
	}

	fn listJson(self: *Plugins, allocator: Allocator) ![]u8 {
		const out = Out{ .list = self.rows, .themes = self.themes, .hyprland = self.hyprland, .failure = self.error_text };

		var buffer: Writer.Allocating = .init(allocator);
		try buffer.writer.print("{f}", .{std.json.fmt(out, .{})});
		return buffer.toOwnedSlice();
	}

	fn loadListJson(self: *Plugins, allocator: Allocator) ![]u8 {
		const arena = self.scratch.allocator();
		const state = self.readList(arena) catch {
			return allocator.dupe(u8, "{\"load\":[],\"failure\":\"ConfigUnreadable\"}");
		};

		var buffer: Writer.Allocating = .init(allocator);
		try buffer.writer.writeAll("{\"load\":[");
		for (state.ids, 0..) |id, index| {
			if (index > 0) try buffer.writer.writeByte(',');
			try writeJsonString(&buffer.writer, id);
		}
		try buffer.writer.writeAll("],\"failure\":");
		try writeJsonString(&buffer.writer, state.error_text);
		try buffer.writer.writeAll("}");
		return buffer.toOwnedSlice();
	}

	fn reloadLocked(self: *Plugins) void {
		_ = self.scratch.reset(.retain_capacity);

		const arena = self.scratch.allocator();
		self.error_text = &.{};
		self.rows = &.{};
		self.themes = &.{};

		const load = self.readList(arena) catch |err| {
			self.error_text = std.fmt.allocPrint(arena, "plugins.toml: {s}", .{@errorName(err)}) catch "plugins.toml is invalid";
			self.hyprland = self.hyprlandVersion(arena);
			self.writeLoadedOwned(arena, &.{});
			self.writeThemeOwned(arena, &.{});
			return;
		};

		if (load.error_text.len > 0) {
			self.error_text = load.error_text;
			self.hyprland = self.hyprlandVersion(arena);
			self.writeLoadedOwned(arena, &.{});
			self.writeThemeOwned(arena, &.{});
			if (self.notes) |notes| notes.post("yudae", "plugins.toml is invalid", self.error_text, 8000);
			return;
		}

		self.hyprland = self.hyprlandVersion(arena);

		var rows: std.ArrayListUnmanaged(Row) = .empty;
		var loaded: std.ArrayListUnmanaged(Loaded) = .empty;
		var themes: std.ArrayListUnmanaged(Theme) = .empty;
		var seen: std.StringHashMapUnmanaged(void) = .empty;

		for (load.ids) |id| {
			const candidate = self.rowFor(arena, id, load.config, &seen) catch |err| {
				rows.append(arena, .{
					.id = id,
					.kind = "",
					.version = "",
					.source = "",
					.dir = "",
					.out = "",
					.commit = "",
					.entry = "",
					.load = true,
					.state = "failed",
					.failure = @errorName(err),
				}) catch {};
				continue;
			};

			seen.put(arena, id, {}) catch {};

			if (candidate.manifest.kind == .hypr) {
				const built = self.prepareHypr(arena, candidate) catch |err| {
					var row = candidate.row;
					row.state = "failed";
					row.failure = self.error_textOrName(arena, err);
					rows.append(arena, row) catch {};
					continue;
				};

				var row = candidate.row;
				row.state = "loaded";
				rows.append(arena, row) catch {};
				loaded.append(arena, built) catch {};
				continue;
			}

			if (candidate.manifest.kind == .theme) {
				const theme = self.prepareTheme(arena, candidate) catch |err| {
					const detail = self.error_textOrName(arena, err);
					self.note(arena, candidate.row.id, "build failed", detail);
					var row = candidate.row;
					row.state = "failed";
					row.failure = detail;
					rows.append(arena, row) catch {};
					continue;
				};

				var row = candidate.row;
				row.state = "loaded";
				rows.append(arena, row) catch {};
				themes.append(arena, theme) catch {};
				continue;
			}

			if (candidate.manifest.kind == .shell or candidate.manifest.kind == .app) {
				const entry = self.prepareRendered(arena, candidate) catch |err| {
					const detail = self.error_textOrName(arena, err);
					self.note(arena, candidate.row.id, "build failed", detail);
					var row = candidate.row;
					row.state = "failed";
					row.failure = detail;
					rows.append(arena, row) catch {};
					continue;
				};

				var row = candidate.row;
				row.state = "loaded";
				row.entry = entry;
				rows.append(arena, row) catch {};
				continue;
			}

			rows.append(arena, candidate.row) catch {};
		}

		self.writeLoadedOwned(arena, loaded.items);
		self.writeThemeOwned(arena, themes.items);
		if (self.live) self.liveLoad(loaded.items);
		self.rows = rows.items;
		self.themes = self.scanThemes(arena, load.ids);
	}

	fn kindOf(self: *Plugins, arena: Allocator, id: []const u8) ?Kind {
		const dir = self.findDir(arena, id) orelse return null;
		const path = std.fmt.allocPrint(arena, "{s}/plugin.toml", .{dir}) catch return null;
		const body = proc.readFile(self.io, self.allocator, path) catch return null;
		defer self.allocator.free(body);

		const manifest = parseManifest(arena, id, body) catch return null;
		return manifest.kind;
	}

	fn scanThemes(self: *Plugins, arena: Allocator, loaded: []const []const u8) []const ThemeRow {
		var found: std.ArrayListUnmanaged(ThemeRow) = .empty;

		for ([_][]const u8{ self.paths.repo, self.paths.data }) |base| {
			var handle = std.Io.Dir.cwd().openDir(self.io, base, .{ .iterate = true }) catch continue;
			defer handle.close(self.io);

			var it = handle.iterate();
			next: while (it.next(self.io) catch null) |entry| {
				if (!validId(entry.name) or entry.name[0] == '_') continue;
				for (found.items) |row| {
					if (std.mem.eql(u8, row.id, entry.name)) continue :next;
				}

				const id = arena.dupe(u8, entry.name) catch continue;
				if (self.kindOf(arena, id) != .theme) continue;

				const dir = self.findDir(arena, id) orelse continue;
				const path = std.fmt.allocPrint(arena, "{s}/theme.toml", .{dir}) catch continue;
				const body = proc.readFile(self.io, self.allocator, path) catch continue;
				defer self.allocator.free(body);
				const cfg = configmod.Config.parse(arena, body) catch continue;

				var accents: std.ArrayListUnmanaged([]const u8) = .empty;
				for (accent_keys) |key| {
					const value = themeColor(cfg, key);
					if (value.len > 0) accents.append(arena, value) catch {};
				}

				var active = false;
				for (loaded) |other| {
					if (std.mem.eql(u8, other, id)) active = true;
				}

				found.append(arena, .{
					.id = id,
					.active = active,
					.surface = themeColor(cfg, "surface"),
					.foreground = themeColor(cfg, "foreground"),
					.accents = accents.items,
				}) catch {};
			}
		}

		std.mem.sort(ThemeRow, found.items, {}, themeBefore);

		var any = false;
		for (found.items) |row| {
			if (row.active) any = true;
		}
		if (!any) {
			for (found.items) |*row| {
				if (std.mem.eql(u8, row.id, "gray")) row.active = true;
			}
		}

		return found.items;
	}

	fn setThemeLocked(self: *Plugins, id: []const u8) !void {
		if (!validId(id)) return error.BadId;

		const arena = self.scratch.allocator();
		if (self.kindOf(arena, id) != .theme) return error.NotATheme;

		const state = self.readList(arena) catch return error.BadConfig;
		if (state.error_text.len > 0) return error.BadConfig;

		var ids: std.ArrayListUnmanaged([]const u8) = .empty;
		for (state.ids) |existing| {
			if (self.kindOf(arena, existing) == .theme) continue;
			ids.append(arena, existing) catch return error.OutOfMemory;
		}
		ids.append(arena, id) catch return error.OutOfMemory;

		try self.writeList(arena, state.config, ids.items);
	}

	const LoadState = struct {
		config: configmod.Config,
		ids: []const []const u8,
		error_text: []const u8,
	};

	fn readList(self: *Plugins, arena: Allocator) !LoadState {
		const body = proc.readFile(self.io, self.allocator, self.paths.load) catch |err| switch (err) {
			error.FileNotFound => "",
			else => return err,
		};
		defer if (body.len > 0) self.allocator.free(body);

		const parsed = configmod.Config.parse(self.allocator, body) catch {
			return .{
				.config = try configmod.Config.parse(arena, ""),
				.ids = &.{},
				.error_text = "plugins.toml is not valid TOML",
			};
		};

		const ids = try parsed.strings("load", arena);
		parsed.deinit();

		return .{ .config = try configmod.Config.parse(arena, body), .ids = ids, .error_text = "" };
	}

	fn rowFor(self: *Plugins, arena: Allocator, id: []const u8, load_config: configmod.Config, seen: *std.StringHashMapUnmanaged(void)) !Candidate {
		if (!validId(id)) return error.BadId;
		if (seen.contains(id)) return error.DuplicateId;

		const dir = self.findDir(arena, id) orelse return error.MissingFolder;
		const body = try proc.readFile(self.io, self.allocator, try std.fmt.allocPrint(arena, "{s}/plugin.toml", .{dir}));
		defer self.allocator.free(body);

		const manifest = try parseManifest(arena, id, body);
		if (self.sourceBinary(arena, dir)) |path| {
			self.error_text = std.fmt.allocPrint(arena, "binary in plugin folder: {s}", .{path}) catch "binary in plugin folder";
			return error.BinaryInPlugin;
		}
		const out = try self.paths.build(arena, id);
		const commit = self.readCommit(arena, id) catch "";
		var options: ?configmod.Value = null;
		if (load_config.direct(id)) |value| {
			switch (value) {
				.table => |table| options = .{ .table = table },
				else => {},
			}
		}

		return .{
			.manifest = manifest,
			.options = options,
			.row = .{
				.id = id,
				.kind = @tagName(manifest.kind),
				.version = manifest.version,
				.source = if (std.mem.startsWith(u8, dir, self.paths.data)) "data" else "repo",
				.dir = dir,
				.out = out,
				.commit = commit,
				.entry = "",
				.load = true,
				.state = "ready",
				.failure = "",
			},
		};
	}

	fn prepareHypr(self: *Plugins, arena: Allocator, candidate: Candidate) !Loaded {
		const manifest = candidate.manifest;

		if (self.hyprland.len == 0) {
			self.note(arena, candidate.row.id, "hyprland headers not found", "pkg-config --modversion hyprland failed");
			return error.NoHyprlandHeaders;
		}

		if (manifest.hyprland.len > 0 and !satisfies(self.hyprland, manifest.hyprland)) {
			self.note(arena, candidate.row.id, "hyprland version mismatch", manifest.hyprland);
			return error.HyprlandVersion;
		}

		const expected = try self.stamp(arena, candidate.row.dir, candidate.row.out);
		const current = proc.readFile(self.io, self.allocator, try std.fmt.allocPrint(arena, "{s}/stamp", .{candidate.row.out})) catch "";
		defer if (current.len > 0) self.allocator.free(current);

		if (!std.mem.eql(u8, current, expected)) {
			self.buildOne(arena, manifest, candidate.row.dir, candidate.row.out) catch |err| {
				self.note(arena, candidate.row.id, "build failed", if (self.error_text.len > 0) self.error_text else @errorName(err));
				return err;
			};
		}

		return .{ .manifest = manifest, .dir = candidate.row.dir, .out = candidate.row.out, .options = candidate.options };
	}

	fn prepareTheme(self: *Plugins, arena: Allocator, candidate: Candidate) !Theme {
		try self.runBuild(arena, candidate.manifest, candidate.row.dir, candidate.row.out);

		const body = try proc.readFile(self.io, self.allocator, try std.fmt.allocPrint(arena, "{s}/theme.toml", .{candidate.row.out}));
		defer self.allocator.free(body);

		const cfg = configmod.Config.parse(arena, body) catch return error.BadTheme;

		var sections: std.ArrayListUnmanaged(Section) = .empty;
		for (cfg.root.entries.items) |entry| {
			const table = switch (entry.value) {
				.table => |inner| inner,
				else => continue,
			};

			var colors: std.ArrayListUnmanaged(Color) = .empty;
			for (table.entries.items) |item| {
				switch (item.value) {
					.string => |value| colors.append(arena, .{ .key = item.key, .value = value }) catch return error.BadTheme,
					.boolean => |flag| {
						colors.append(arena, .{ .key = item.key, .value = "", .flag = flag }) catch return error.BadTheme;
					},
					else => return error.BadTheme,
				}
			}

			if (colors.items.len > 0) {
				sections.append(arena, .{ .name = entry.key, .entries = colors.items }) catch return error.BadTheme;
			}
		}

		if (sections.items.len == 0) return error.BadTheme;

		return .{ .sections = sections.items };
	}

	fn sourceBinary(self: *Plugins, arena: Allocator, dir: []const u8) ?[]const u8 {
		var handle = std.Io.Dir.cwd().openDir(self.io, dir, .{ .iterate = true }) catch return null;
		defer handle.close(self.io);

		var walker = handle.walk(self.allocator) catch return null;
		defer walker.deinit();

		while (walker.next(self.io) catch null) |entry| {
			if (entry.kind != .file) continue;
			if (ignoredPath(entry.path)) continue;

			const binary_suffix = std.mem.endsWith(u8, entry.basename, ".so") or
				std.mem.endsWith(u8, entry.basename, ".bin") or
				std.mem.endsWith(u8, entry.basename, ".o") or
				std.mem.endsWith(u8, entry.basename, ".a") or
				std.mem.endsWith(u8, entry.basename, ".dylib") or
				std.mem.endsWith(u8, entry.basename, ".dll") or
				std.mem.endsWith(u8, entry.basename, ".exe");

			if (binary_suffix) return arena.dupe(u8, entry.path) catch entry.path;

			var file = entry.dir.openFile(self.io, entry.basename, .{}) catch continue;
			var buffer: [4]u8 = undefined;
			var reader = file.reader(self.io, &buffer);
			const count = reader.interface.readSliceShort(&buffer) catch 0;
			file.close(self.io);

			if (count == 4 and std.mem.eql(u8, &buffer, "\x7fELF")) return arena.dupe(u8, entry.path) catch entry.path;
		}

		return null;
	}

	fn prepareRendered(self: *Plugins, arena: Allocator, candidate: Candidate) ![]const u8 {
		try self.runBuild(arena, candidate.manifest, candidate.row.dir, candidate.row.out);

		if (candidate.manifest.kind != .shell) return "";

		for (candidate.manifest.provides) |item| {
			if (!std.mem.endsWith(u8, item, ".qml")) continue;
			return std.fmt.allocPrint(arena, "file://{s}/{s}", .{ candidate.row.out, item });
		}

		return error.MissingEntry;
	}

	fn writeThemeOwned(self: *Plugins, arena: Allocator, themes: []const Theme) void {
		const path = self.paths.theme(arena) catch return;
		std.Io.Dir.cwd().createDirPath(self.io, self.paths.state) catch {};

		var merged: std.ArrayListUnmanaged(MergeSection) = .empty;
		for (themes) |theme| {
			for (theme.sections) |section| {
				var target: *MergeSection = undefined;
				var found = false;
				for (merged.items) |*existing| {
					if (!std.mem.eql(u8, existing.name, section.name)) continue;
					target = existing;
					found = true;
					break;
				}

				if (!found) {
					merged.append(arena, .{ .name = section.name }) catch return;
					target = &merged.items[merged.items.len - 1];
				}

				for (section.entries) |color| {
					var replaced = false;
					for (target.entries.items) |*existing| {
						if (!std.mem.eql(u8, existing.key, color.key)) continue;
						existing.value = color.value;
						existing.flag = color.flag;
						replaced = true;
						break;
					}
					if (!replaced) target.entries.append(arena, color) catch {};
				}
			}
		}

		var out: Writer.Allocating = .init(arena);
		for (merged.items) |section| {
			out.writer.print("[{s}]\n", .{section.name}) catch return;
			for (section.entries.items) |color| {
				out.writer.print("{s} = ", .{color.key}) catch return;
				if (color.flag) |flag| {
					out.writer.writeAll(if (flag) "true" else "false") catch return;
				} else {
					writeTomlString(&out.writer, color.value) catch return;
				}
				out.writer.writeAll("\n") catch return;
			}
			out.writer.writeAll("\n") catch return;
		}

		proc.writeFileAtomic(self.io, self.allocator, path, out.written()) catch {};
	}

	fn buildOneLocked(self: *Plugins, id: []const u8) !void {
		const arena = self.scratch.allocator();
		const dir = self.findDir(arena, id) orelse return error.MissingFolder;
		const body = try proc.readFile(self.io, self.allocator, try std.fmt.allocPrint(arena, "{s}/plugin.toml", .{dir}));
		defer self.allocator.free(body);

		const manifest = try parseManifest(arena, id, body);

		self.hyprland = self.hyprlandVersion(arena);
		const out = try self.paths.build(arena, id);
		if (manifest.kind == .hypr) {
			try self.buildOne(arena, manifest, dir, out);
		} else {
			try self.runBuild(arena, manifest, dir, out);
		}

		_ = self.scratch.reset(.retain_capacity);
		self.reloadLocked();
	}

	fn buildOne(self: *Plugins, arena: Allocator, manifest: Manifest, dir: []const u8, out: []const u8) !void {
		try self.runBuild(arena, manifest, dir, out);

		const expected = try self.stamp(arena, dir, out);
		try proc.writeFileAtomic(self.io, self.allocator, try std.fmt.allocPrint(arena, "{s}/stamp", .{out}), expected);
	}

	fn runBuild(self: *Plugins, arena: Allocator, manifest: Manifest, dir: []const u8, out: []const u8) !void {
		self.error_text = &.{};
		std.Io.Dir.cwd().deleteTree(self.io, out) catch {};
		try std.Io.Dir.cwd().createDirPath(self.io, out);

		var map = std.process.Environ.Map.init(self.allocator);
		defer map.deinit();
		try self.putEnviron(&map);
		try map.put("OUT", out);

		const result = exec.runDir(self.io, self.allocator, &.{ "sh", "-c", manifest.build }, dir, &map) catch |err| {
			self.error_text = try std.fmt.allocPrint(arena, "{s}", .{@errorName(err)});
			return error.BuildFailed;
		};
		defer result.deinit(self.allocator);

		if (result.code != 0) {
			self.error_text = try tail(arena, if (result.err.len > 0) result.err else result.out);
			return error.BuildFailed;
		}

		for (manifest.provides) |item| {
			const path = try std.fmt.allocPrint(arena, "{s}/{s}", .{ out, item });
			_ = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch {
				self.error_text = try std.fmt.allocPrint(arena, "build did not write {s}", .{item});
				return error.MissingProvides;
			};
		}
	}

	fn putEnviron(self: *Plugins, map: *std.process.Environ.Map) !void {
		const block = proc.environ(self.io, self.allocator) orelse return;
		var it = std.mem.splitScalar(u8, block, 0);

		while (it.next()) |entry| {
			const at = std.mem.indexOfScalar(u8, entry, '=') orelse continue;
			try map.put(entry[0..at], entry[at + 1 ..]);
		}
	}

	fn stamp(self: *Plugins, arena: Allocator, dir: []const u8, out: []const u8) ![]u8 {
		_ = out;
		const digest = try self.hashSource(arena, dir);
		const hex = std.fmt.bytesToHex(digest, .lower);
		return std.fmt.allocPrint(arena, "{s}\n{s}\n", .{ self.hyprland, hex });
	}

	fn hashSource(self: *Plugins, arena: Allocator, dir: []const u8) ![32]u8 {
		var handle = try std.Io.Dir.cwd().openDir(self.io, dir, .{ .iterate = true });
		defer handle.close(self.io);

		var walker = try handle.walk(self.allocator);
		defer walker.deinit();

		var files: std.ArrayListUnmanaged(SourceFile) = .empty;

		while (try walker.next(self.io)) |entry| {
			if (entry.kind != .file) continue;
			if (ignoredPath(entry.path)) continue;

			const body = try entry.dir.readFileAlloc(self.io, entry.basename, self.allocator, .limited(4 * 1024 * 1024));
			defer self.allocator.free(body);

			var digest: [32]u8 = undefined;
			std.crypto.hash.sha2.Sha256.hash(body, &digest, .{});

			try files.append(arena, .{ .path = try arena.dupe(u8, entry.path), .digest = digest });
		}

		std.mem.sort(SourceFile, files.items, {}, struct {
			fn less(_: void, a: SourceFile, b: SourceFile) bool {
				return std.mem.order(u8, a.path, b.path) == .lt;
			}
		}.less);

		var hash = std.crypto.hash.sha2.Sha256.init(.{});
		for (files.items) |file| {
			hash.update(file.path);
			hash.update(&.{0});
			hash.update(&file.digest);
		}

		return hash.finalResult();
	}

	fn writeLoadedOwned(self: *Plugins, arena: Allocator, loaded: []const Loaded) void {
		const path = self.paths.loaded(arena) catch return;
		std.Io.Dir.cwd().createDirPath(self.io, self.paths.state) catch {};

		var out: Writer.Allocating = .init(arena);
		out.writer.writeAll("-- generated by yudaemond; edits are overwritten\n") catch return;

		for (loaded) |entry| {
			out.writer.writeAll("do\n\tlocal YUDAE_PLUGIN = {\n\t\tid = ") catch return;
			writeLuaString(&out.writer, entry.manifest.id) catch return;
			out.writer.writeAll(",\n\t\tdir = ") catch return;
			writeLuaString(&out.writer, entry.dir) catch return;
			out.writer.writeAll(",\n\t\tout = ") catch return;
			writeLuaString(&out.writer, entry.out) catch return;
			out.writer.writeAll(",\n\t\toptions = ") catch return;
			if (entry.options) |options| {
				writeLuaValue(&out.writer, options) catch return;
			} else {
				out.writer.writeAll("{ }") catch return;
			}
			out.writer.writeAll(",\n\t}\n") catch return;

			for (entry.manifest.provides) |item| {
				if (!std.mem.endsWith(u8, item, ".so") and !std.mem.endsWith(u8, item, ".bin")) continue;

				const binary = std.fmt.allocPrint(arena, "{s}/{s}", .{ entry.out, item }) catch return;
				out.writer.writeAll("\thl.permission({ binary = ") catch return;
				writeLuaString(&out.writer, binary) catch return;
				out.writer.writeAll(", type = \"plugin\", mode = \"allow\" })\n\thl.plugin.load(") catch return;
				writeLuaString(&out.writer, binary) catch return;
				out.writer.writeAll(")\n") catch return;
			}

			const lua_path = std.fmt.allocPrint(arena, "{s}/hypr.lua", .{entry.dir}) catch return;
			const body = proc.readFile(self.io, self.allocator, lua_path) catch "";
			defer if (body.len > 0) self.allocator.free(body);
			out.writer.writeAll(body) catch return;
			if (body.len > 0 and body[body.len - 1] != '\n') out.writer.writeAll("\n") catch return;
			out.writer.writeAll("end\n") catch return;
		}

		proc.writeFileAtomic(self.io, self.allocator, path, out.written()) catch {};
	}

	fn liveLoad(self: *Plugins, loaded: []const Loaded) void {
		if (loaded.len == 0) return;

		const signature = hypr.findSignature(self.io, self.allocator) catch return;
		defer self.allocator.free(signature);

		var map = std.process.Environ.Map.init(self.allocator);
		defer map.deinit();
		self.putEnviron(&map) catch return;
		map.put("HYPRLAND_INSTANCE_SIGNATURE", signature) catch return;

		const list = exec.runEnv(self.io, self.allocator, &.{ "hyprctl", "plugin", "list" }, &map) catch return;
		defer list.deinit(self.allocator);
		if (list.code != 0) return;

		for (loaded) |entry| {
			if (std.mem.indexOf(u8, list.out, entry.manifest.id) != null) continue;

			for (entry.manifest.provides) |item| {
				if (!std.mem.endsWith(u8, item, ".so") and !std.mem.endsWith(u8, item, ".bin")) continue;

				const binary = std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ entry.out, item }) catch continue;
				const result = exec.runEnv(self.io, self.allocator, &.{ "hyprctl", "plugin", "load", binary }, &map) catch {
					self.allocator.free(binary);
					continue;
				};
				result.deinit(self.allocator);
				self.allocator.free(binary);
			}
		}
	}

	fn editListLocked(self: *Plugins, id: []const u8, add: bool) !void {
		if (!validId(id)) return error.BadId;

		const arena = self.scratch.allocator();
		const state = self.readList(arena) catch return error.BadConfig;
		if (state.error_text.len > 0) return error.BadConfig;

		var ids: std.ArrayListUnmanaged([]const u8) = .empty;
		for (state.ids) |existing| {
			if (add and std.mem.eql(u8, existing, id)) return;
			if (!add and std.mem.eql(u8, existing, id)) continue;
			ids.append(arena, existing) catch return error.OutOfMemory;
		}

		if (add) {
			if (self.findDir(arena, id) == null) return error.MissingFolder;
			ids.append(arena, id) catch return error.OutOfMemory;
		}

		try self.writeList(arena, state.config, ids.items);
	}

	fn writeList(self: *Plugins, arena: Allocator, load_config: configmod.Config, ids: []const []const u8) !void {
		var out: Writer.Allocating = .init(arena);

		try out.writer.writeAll("load = [");
		for (ids, 0..) |id, index| {
			if (index > 0) try out.writer.writeAll(", ");
			try writeTomlString(&out.writer, id);
		}
		try out.writer.writeAll("]\n");

		for (load_config.root.entries.items) |entry| {
			if (std.mem.eql(u8, entry.key, "load")) continue;

			const table = switch (entry.value) {
				.table => |inner| inner,
				else => continue,
			};

			try out.writer.print("\n[{s}]\n", .{entry.key});
			for (table.entries.items) |item| {
				if (item.value == .table) continue;
				try out.writer.print("{s} = ", .{item.key});
				try writeTomlValue(&out.writer, item.value);
				try out.writer.writeAll("\n");
			}
		}

		try proc.writeFileAtomic(self.io, self.allocator, self.paths.load, out.written());
	}

	fn addLocked(self: *Plugins, url: []const u8, allocator: Allocator) ![]u8 {
		if (url.len == 0 or url[0] == '-') return error.BadUrl;

		const arena = self.scratch.allocator();
		const base = try idFromUrl(arena, url);
		if (!validId(base)) return error.BadUrlId;

		const dest0 = try std.fmt.allocPrint(arena, "{s}/{s}", .{ self.paths.data, base });
		if (pathExists(self.io, dest0)) return error.AlreadyInstalled;
		try std.Io.Dir.cwd().createDirPath(self.io, self.paths.data);

		const clone = exec.run(self.io, self.allocator, &.{ "git", "clone", url, dest0 }) catch return error.CloneFailed;
		defer clone.deinit(self.allocator);
		if (clone.code != 0) return error.CloneFailed;

		var installed: []const u8 = dest0;
		errdefer std.Io.Dir.cwd().deleteTree(self.io, installed) catch {};

		const body = proc.readFile(self.io, self.allocator, try std.fmt.allocPrint(arena, "{s}/plugin.toml", .{dest0})) catch return error.NotAPlugin;
		defer self.allocator.free(body);

		const id = try manifestId(arena, body);
		if (!validId(id)) return error.BadManifestId;

		const repo_plugin = try std.fmt.allocPrint(arena, "{s}/{s}", .{ self.paths.repo, id });
		if (pathExists(self.io, repo_plugin)) return error.AlreadyInstalled;

		const dest = try std.fmt.allocPrint(arena, "{s}/{s}", .{ self.paths.data, id });
		if (!std.mem.eql(u8, dest, dest0)) {
			if (pathExists(self.io, dest)) return error.AlreadyInstalled;
			try std.Io.Dir.cwd().rename(dest0, std.Io.Dir.cwd(), dest, self.io);
			installed = dest;
		}

		const manifest = try parseManifest(arena, id, body);
		const commit = self.gitHead(arena, dest);

		try self.recordCommit(arena, id, commit);
		try self.editListLocked(id, true);

		var out: Writer.Allocating = .init(allocator);
		try out.writer.print("{{\"id\":", .{});
		try writeJsonString(&out.writer, id);
		try out.writer.print(",\"kind\":", .{});
		try writeJsonString(&out.writer, @tagName(manifest.kind));
		try out.writer.print(",\"version\":", .{});
		try writeJsonString(&out.writer, manifest.version);
		try out.writer.print(",\"commit\":", .{});
		try writeJsonString(&out.writer, commit);
		try out.writer.print(",\"path\":", .{});
		try writeJsonString(&out.writer, dest);
		try out.writer.writeAll(",\"files\":");
		try writeFileList(&out.writer, self.io, self.allocator, dest);
		try out.writer.writeAll("}");

		return out.toOwnedSlice();
	}

	fn updateLocked(self: *Plugins, id: []const u8, allocator: Allocator) ![]u8 {
		if (!validId(id)) return error.BadId;

		const arena = self.scratch.allocator();
		const dir = self.findDir(arena, id) orelse return error.MissingFolder;
		if (!std.mem.startsWith(u8, dir, self.paths.data)) return error.RepositoryPlugin;

		const pull = exec.run(self.io, self.allocator, &.{ "git", "-C", dir, "pull", "--ff-only" }) catch return error.UpdateFailed;
		defer pull.deinit(self.allocator);
		if (pull.code != 0) return error.UpdateFailed;

		const commit = self.gitHead(arena, dir);
		try self.recordCommit(arena, id, commit);

		var out: Writer.Allocating = .init(allocator);
		try out.writer.print("{{\"id\":", .{});
		try writeJsonString(&out.writer, id);
		try out.writer.print(",\"commit\":", .{});
		try writeJsonString(&out.writer, commit);
		try out.writer.writeAll("}");

		return out.toOwnedSlice();
	}

	fn gitHead(self: *Plugins, arena: Allocator, dir: []const u8) []const u8 {
		const result = exec.run(self.io, self.allocator, &.{ "git", "-C", dir, "rev-parse", "HEAD" }) catch return "";
		defer result.deinit(self.allocator);
		if (result.code != 0) return "";

		const text = std.mem.trim(u8, result.out, " \t\r\n");
		return arena.dupe(u8, text) catch "";
	}

	fn recordCommit(self: *Plugins, arena: Allocator, id: []const u8, commit: []const u8) !void {
		if (commit.len == 0) return;
		const path = try self.paths.commit(arena, id);
		std.Io.Dir.cwd().createDirPath(self.io, std.fs.path.dirname(path) orelse ".") catch {};
		try proc.writeFileAtomic(self.io, self.allocator, path, try std.fmt.allocPrint(arena, "{s}\n", .{commit}));
	}

	fn readCommit(self: *Plugins, arena: Allocator, id: []const u8) ![]const u8 {
		const path = try self.paths.commit(arena, id);
		const body = proc.readFile(self.io, self.allocator, path) catch return "";
		defer self.allocator.free(body);
		return arena.dupe(u8, std.mem.trim(u8, body, " \t\r\n"));
	}

	fn findDir(self: *Plugins, arena: Allocator, id: []const u8) ?[]const u8 {
		const first = std.fmt.allocPrint(arena, "{s}/{s}", .{ self.paths.repo, id }) catch return null;
		if (isDir(self.io, first)) return first;

		const second = std.fmt.allocPrint(arena, "{s}/{s}", .{ self.paths.data, id }) catch return null;
		if (isDir(self.io, second)) return second;

		return null;
	}

	fn hyprlandVersion(self: *Plugins, arena: Allocator) []const u8 {
		const result = exec.run(self.io, self.allocator, &.{ "pkg-config", "--modversion", "hyprland" }) catch return "";
		defer result.deinit(self.allocator);
		if (result.code != 0) return "";

		return arena.dupe(u8, std.mem.trim(u8, result.out, " \t\r\n")) catch "";
	}

	fn error_textOrName(self: *Plugins, arena: Allocator, err: anyerror) []const u8 {
		if (self.error_text.len > 0) return self.error_text;
		return std.fmt.allocPrint(arena, "{s}", .{@errorName(err)}) catch @errorName(err);
	}

	fn note(self: *Plugins, arena: Allocator, id: []const u8, summary: []const u8, body: []const u8) void {
		const notes = self.notes orelse return;
		const title = std.fmt.allocPrint(arena, "plugin {s}: {s}", .{ id, summary }) catch return;
		notes.post("yudae", title, body, 8000);
	}

	pub fn deinit(self: *Plugins) void {
		self.scratch.deinit();
		self.allocator.destroy(self);
	}
};

fn defaultPaths(io: Io, allocator: Allocator) Paths {
	const state = std.fmt.allocPrint(allocator, "{s}/yudae", .{proc.stateHome(io, allocator)}) catch "/tmp/yudae";
	const data_home = proc.env(io, allocator, "XDG_DATA_HOME") orelse std.fmt.allocPrint(allocator, "{s}/.local/share", .{proc.home(io, allocator)}) catch "/tmp";
	const data = std.fmt.allocPrint(allocator, "{s}/yudae/plugins", .{data_home}) catch "/tmp/yudae/plugins";
	const repo = std.fmt.allocPrint(allocator, "{s}/plugins", .{proc.repo(io, allocator)}) catch "plugins";
	const load = proc.env(io, allocator, "YUDAE_PLUGINS") orelse std.fmt.allocPrint(allocator, "{s}/plugins.toml", .{state}) catch "/tmp/yudae/plugins.toml";

	return .{ .load = load, .repo = repo, .data = data, .state = state };
}

fn parseManifest(arena: Allocator, folder: []const u8, body: []const u8) !Manifest {
	const cfg = configmod.Config.parse(arena, body) catch return error.BadManifest;

	for (cfg.root.entries.items) |entry| {
		var known = false;
		for (manifest_keys) |key| {
			if (std.mem.eql(u8, entry.key, key)) {
				known = true;
				break;
			}
		}
		if (!known) return error.BadManifest;
	}

	const id = cfg.string("id", arena) orelse return error.BadManifest;
	if (!validId(id) or !std.mem.eql(u8, id, folder)) return error.BadId;

	const kind_text = cfg.string("kind", arena) orelse return error.BadManifest;
	const kind = std.meta.stringToEnum(Kind, kind_text) orelse return error.UnknownKind;

	const version = cfg.string("version", arena) orelse return error.BadManifest;
	if (version.len == 0) return error.BadManifest;

	const build = cfg.string("build", arena) orelse return error.BadManifest;
	if (build.len == 0) return error.BadManifest;

	const provides_raw = try cfg.strings("provides", arena);
	if (provides_raw.len == 0) return error.BadManifest;

	const provides = try arena.alloc([]const u8, provides_raw.len);
	for (provides_raw, 0..) |item, index| {
		if (item.len == 0 or item[0] == '/' or std.mem.indexOf(u8, item, "..") != null) return error.BadManifest;
		provides[index] = item;
	}

	var hyprland: []const u8 = "";
	if (cfg.direct("requires")) |value| {
		const table = switch (value) {
			.table => |inner| inner,
			else => return error.BadManifest,
		};

		for (table.entries.items) |entry| {
			if (!std.mem.eql(u8, entry.key, "hyprland")) return error.BadManifest;
			hyprland = switch (entry.value) {
				.string => |text| try arena.dupe(u8, text),
				else => return error.BadManifest,
			};
		}
	}

	return .{
		.id = id,
		.kind = kind,
		.version = version,
		.build = build,
		.provides = provides,
		.hyprland = hyprland,
	};
}

fn themeBefore(_: void, a: ThemeRow, b: ThemeRow) bool {
	return std.mem.lessThan(u8, a.id, b.id);
}

fn themeColor(cfg: configmod.Config, key: []const u8) []const u8 {
	for (cfg.root.entries.items) |entry| {
		const table = switch (entry.value) {
			.table => |inner| inner,
			else => continue,
		};

		for (table.entries.items) |item| {
			if (!std.mem.eql(u8, item.key, key)) continue;
			switch (item.value) {
				.string => |value| return value,
				else => {},
			}
		}
	}

	return "";
}

fn validId(id: []const u8) bool {
	if (id.len == 0 or id.len > 80) return false;
	var at: usize = 0;
	if (id[0] == '_') at = 1;
	if (at >= id.len or !std.ascii.isLower(id[at])) return false;
	at += 1;
	while (at < id.len) : (at += 1) {
		const byte = id[at];
		if (!std.ascii.isLower(byte) and !std.ascii.isDigit(byte) and byte != '-') return false;
	}

	return true;
}

fn isDir(io: Io, path: []const u8) bool {
	var dir = std.Io.Dir.cwd().openDir(io, path, .{}) catch return false;
	dir.close(io);
	return true;
}

fn pathExists(io: Io, path: []const u8) bool {
	_ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
	return true;
}

fn ignoredPath(path: []const u8) bool {
	return std.mem.indexOf(u8, path, ".git/") != null or
		std.mem.startsWith(u8, path, ".git") or
		std.mem.indexOf(u8, path, ".zig-cache/") != null;
}

fn manifestId(arena: Allocator, body: []const u8) ![]const u8 {
	const cfg = configmod.Config.parse(arena, body) catch return error.BadManifest;
	return cfg.string("id", arena) orelse error.BadManifest;
}

fn idFromUrl(allocator: Allocator, url: []const u8) ![]u8 {
	var trimmed = std.mem.trimEnd(u8, url, "/");
	if (std.mem.endsWith(u8, trimmed, ".git")) trimmed = trimmed[0 .. trimmed.len - 4];
	const slash = std.mem.lastIndexOfScalar(u8, trimmed, '/') orelse std.mem.lastIndexOfScalar(u8, trimmed, ':') orelse return error.BadId;
	return allocator.dupe(u8, trimmed[slash + 1 ..]);
}

fn satisfies(have: []const u8, requirement: []const u8) bool {
	const parsed_have = versionParts(have) orelse return false;
	var text = std.mem.trim(u8, requirement, " \t");
	var operator: enum { eq, ge, le, gt, lt } = .eq;

	const operators = [_]struct { text: []const u8, op: @TypeOf(operator) }{
		. { .text = ">=", .op = .ge },
		. { .text = "<=", .op = .le },
		. { .text = ">", .op = .gt },
		. { .text = "<", .op = .lt },
		. { .text = "=", .op = .eq },
	};
	for (operators) |candidate| {
		if (std.mem.startsWith(u8, text, candidate.text)) {
			operator = candidate.op;
			text = std.mem.trim(u8, text[candidate.text.len..], " \t");
			break;
		}
	}

	const parsed_want = versionParts(text) orelse return false;
	return switch (operator) {
		.eq => std.mem.eql(u64, &parsed_have, &parsed_want),
		.ge => std.mem.order(u64, &parsed_have, &parsed_want) != .lt,
		.le => std.mem.order(u64, &parsed_have, &parsed_want) != .gt,
		.gt => std.mem.order(u64, &parsed_have, &parsed_want) == .gt,
		.lt => std.mem.order(u64, &parsed_have, &parsed_want) == .lt,
	};
}

fn versionParts(text: []const u8) ?[3]u64 {
	var out = [_]u64{ 0, 0, 0 };
	var index: usize = 0;
	var it = std.mem.splitScalar(u8, text, '.');

	while (it.next()) |part| {
		if (index >= out.len) break;
		var digits: usize = 0;
		while (digits < part.len and std.ascii.isDigit(part[digits])) digits += 1;
		if (digits == 0) return null;
		out[index] = std.fmt.parseInt(u64, part[0..digits], 10) catch return null;
		index += 1;
	}

	return if (index == 0) null else out;
}

fn tail(arena: Allocator, text: []const u8) ![]const u8 {
	const trimmed = std.mem.trim(u8, text, " \t\r\n");
	if (trimmed.len <= 1200) return arena.dupe(u8, trimmed);

	return arena.dupe(u8, trimmed[trimmed.len - 1200 ..]);
}

fn writeLuaString(writer: *Writer, text: []const u8) !void {
	try writer.writeByte('"');
	for (text) |byte| {
		switch (byte) {
			'"', '\\' => {
				try writer.writeByte('\\');
				try writer.writeByte(byte);
			},
			'\n' => try writer.writeAll("\\n"),
			'\r' => try writer.writeAll("\\r"),
			else => try writer.writeByte(byte),
		}
	}
	try writer.writeByte('"');
}

fn writeLuaValue(writer: *Writer, value: configmod.Value) !void {
	switch (value) {
		.string => |text| try writeLuaString(writer, text),
		.integer => |number| try writer.print("{d}", .{number}),
		.float => |number| try writer.print("{d}", .{number}),
		.boolean => |flag| try writer.writeAll(if (flag) "true" else "false"),
		.array => |items| {
			try writer.writeByte('{');
			for (items, 0..) |item, index| {
				if (index > 0) try writer.writeAll(", ");
				try writeLuaValue(writer, item);
			}
			try writer.writeByte('}');
		},
		.table => |table| {
			try writer.writeAll("{ ");
			for (table.entries.items, 0..) |entry, index| {
				if (index > 0) try writer.writeAll(", ");
				try writer.writeAll("[");
				try writeLuaString(writer, entry.key);
				try writer.writeAll("] = ");
				try writeLuaValue(writer, entry.value);
			}
			try writer.writeAll(" }");
		},
	}
}

fn writeTomlString(writer: *Writer, text: []const u8) !void {
	try writer.writeByte('"');
	for (text) |byte| {
		switch (byte) {
			'"', '\\' => {
				try writer.writeByte('\\');
				try writer.writeByte(byte);
			},
			'\n' => try writer.writeAll("\\n"),
			'\r' => try writer.writeAll("\\r"),
			'\t' => try writer.writeAll("\\t"),
			else => try writer.writeByte(byte),
		}
	}
	try writer.writeByte('"');
}

fn writeTomlValue(writer: *Writer, value: configmod.Value) !void {
	switch (value) {
		.string => |text| try writeTomlString(writer, text),
		.integer => |number| try writer.print("{d}", .{number}),
		.float => |number| try writer.print("{d}", .{number}),
		.boolean => |flag| try writer.writeAll(if (flag) "true" else "false"),
		.array => |items| {
			try writer.writeByte('[');
			for (items, 0..) |item, index| {
				if (index > 0) try writer.writeAll(", ");
				try writeTomlValue(writer, item);
			}
			try writer.writeByte(']');
		},
		.table => |table| {
			try writer.writeAll("{ ");
			for (table.entries.items, 0..) |entry, index| {
				if (index > 0) try writer.writeAll(", ");
				try writer.print("{s} = ", .{entry.key});
				try writeTomlValue(writer, entry.value);
			}
			try writer.writeAll(" }");
		},
	}
}

fn writeJsonString(writer: *Writer, text: []const u8) !void {
	try std.json.Stringify.encodeJsonString(text, .{}, writer);
}

fn writeFileList(writer: *Writer, io: Io, allocator: Allocator, dir: []const u8) !void {
	var handle = try std.Io.Dir.cwd().openDir(io, dir, .{ .iterate = true });
	defer handle.close(io);

	var walker = try handle.walk(allocator);
	defer walker.deinit();

	try writer.writeByte('[');
	var count: usize = 0;

	while (try walker.next(io)) |entry| {
		if (entry.kind != .file or ignoredPath(entry.path)) continue;
		if (count == 200) break;

		if (count > 0) try writer.writeByte(',');
		try std.json.Stringify.encodeJsonString(entry.path, .{}, writer);
		count += 1;
	}

	try writer.writeByte(']');
}

fn jsonText(value: std.json.Value, key: []const u8) []const u8 {
	const field = switch (value) {
		.object => |object| object.get(key) orelse return "",
		else => return "",
	};

	return switch (field) {
		.string => |text| text,
		else => "",
	};
}

fn testLoader(tmp: *std.testing.TmpDir, arena: Allocator) !*Plugins {
	const cwd = try std.process.currentPathAlloc(std.testing.io, arena);
	const base = try std.fmt.allocPrint(arena, "{s}/.zig-cache/tmp/{s}", .{ cwd, tmp.sub_path });
	const paths = Paths{
		.load = try std.fmt.allocPrint(arena, "{s}/plugins.toml", .{base}),
		.repo = try std.fmt.allocPrint(arena, "{s}/plugins", .{base}),
		.data = try std.fmt.allocPrint(arena, "{s}/data", .{base}),
		.state = try std.fmt.allocPrint(arena, "{s}/state", .{base}),
	};

	const hub = try arena.create(Hub);
	hub.* = .{ .allocator = std.testing.allocator, .io = std.testing.io };

	const loader = try Plugins.createAt(std.testing.allocator, std.testing.io, hub, null, paths);
	loader.live = false;
	return loader;
}

fn testPlugin(arena: Allocator, paths: Paths, id: []const u8, kind: []const u8, extra: []const u8) !void {
	const dir = try std.fmt.allocPrint(arena, "{s}/{s}", .{ paths.repo, id });
	const body = try std.fmt.allocPrint(arena, "id = \"{s}\"\nkind = \"{s}\"\nversion = \"0.1.0\"\nbuild = \"touch $OUT/out.txt\"\nprovides = [\"out.txt\"]\n{s}", .{ id, kind, extra });
	try proc.writeFile(std.testing.io, try std.fmt.allocPrint(arena, "{s}/plugin.toml", .{dir}), body);
}

fn parseLoad(arena: Allocator, path: []const u8) !configmod.Config {
	const body = try proc.readFile(std.testing.io, std.testing.allocator, path);
	defer std.testing.allocator.free(body);
	return configmod.Config.parse(arena, body);
}

test "an absent load list means no plugins" {
	var tmp = std.testing.tmpDir(.{});
	defer tmp.cleanup();

	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();

	const loader = try testLoader(&tmp, arena.allocator());
	defer loader.deinit();

	loader.reloadLocked();

	try std.testing.expectEqual(@as(usize, 0), loader.rows.len);
	const body = try proc.readFile(std.testing.io, std.testing.allocator, try loader.paths.loaded(arena.allocator()));
	defer std.testing.allocator.free(body);
	try std.testing.expect(std.mem.indexOf(u8, body, "generated by yudaemond") != null);
}

test "a listed plugin with no folder fails alone" {
	var tmp = std.testing.tmpDir(.{});
	defer tmp.cleanup();

	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();
	const a = arena.allocator();

	const loader = try testLoader(&tmp, a);
	defer loader.deinit();

	try proc.writeFile(std.testing.io, loader.paths.load, "load = [\"nope\"]\n");
	loader.reloadLocked();

	try std.testing.expectEqual(@as(usize, 1), loader.rows.len);
	try std.testing.expectEqualStrings("failed", loader.rows[0].state);
	try std.testing.expectEqualStrings("MissingFolder", loader.rows[0].failure);
}

test "broken plugins.toml loads nothing and reports it" {
	var tmp = std.testing.tmpDir(.{});
	defer tmp.cleanup();

	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();
	const a = arena.allocator();

	const loader = try testLoader(&tmp, a);
	defer loader.deinit();

	try proc.writeFile(std.testing.io, loader.paths.load, "load = [\n");
	loader.reloadLocked();

	try std.testing.expect(loader.error_text.len > 0);
	try std.testing.expectEqual(@as(usize, 0), loader.rows.len);
}

test "an unknown kind fails without stopping the order" {
	var tmp = std.testing.tmpDir(.{});
	defer tmp.cleanup();

	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();
	const a = arena.allocator();

	const loader = try testLoader(&tmp, a);
	defer loader.deinit();

	try testPlugin(a, loader.paths, "bad", "weird", "");
	try testPlugin(a, loader.paths, "good", "app", "");
	try proc.writeFile(std.testing.io, loader.paths.load, "load = [\"bad\", \"good\"]\n");
	loader.reloadLocked();

	try std.testing.expectEqual(@as(usize, 2), loader.rows.len);
	try std.testing.expectEqualStrings("UnknownKind", loader.rows[0].failure);
	try std.testing.expectEqualStrings("good", loader.rows[1].id);
	try std.testing.expectEqualStrings("loaded", loader.rows[1].state);
}

test "duplicate ids fail and keep the first row" {
	var tmp = std.testing.tmpDir(.{});
	defer tmp.cleanup();

	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();
	const a = arena.allocator();

	const loader = try testLoader(&tmp, a);
	defer loader.deinit();

	try testPlugin(a, loader.paths, "one", "app", "");
	try proc.writeFile(std.testing.io, loader.paths.load, "load = [\"one\", \"one\"]\n");
	loader.reloadLocked();

	try std.testing.expectEqual(@as(usize, 2), loader.rows.len);
	try std.testing.expectEqualStrings("loaded", loader.rows[0].state);
	try std.testing.expectEqualStrings("DuplicateId", loader.rows[1].failure);
}

test "load order is the file order" {
	var tmp = std.testing.tmpDir(.{});
	defer tmp.cleanup();

	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();
	const a = arena.allocator();

	const loader = try testLoader(&tmp, a);
	defer loader.deinit();

	try testPlugin(a, loader.paths, "first", "app", "");
	try testPlugin(a, loader.paths, "second", "app", "");
	try proc.writeFile(std.testing.io, loader.paths.load, "load = [\"second\", \"first\"]\n");
	loader.reloadLocked();

	try std.testing.expectEqualStrings("second", loader.rows[0].id);
	try std.testing.expectEqualStrings("first", loader.rows[1].id);
}

test "unload edits only the load list and keeps options" {
	var tmp = std.testing.tmpDir(.{});
	defer tmp.cleanup();

	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();
	const a = arena.allocator();

	const loader = try testLoader(&tmp, a);
	defer loader.deinit();

	try testPlugin(a, loader.paths, "keep", "app", "");
	try testPlugin(a, loader.paths, "drop", "app", "");
	try proc.writeFile(std.testing.io, loader.paths.load, "load = [\"keep\", \"drop\"]\n\n[keep]\ntone = \"blue\"\n");

	try loader.editListLocked("drop", false);

	const cfg = try parseLoad(a, loader.paths.load);
	const ids = try cfg.strings("load", a);
	try std.testing.expectEqual(@as(usize, 1), ids.len);
	try std.testing.expectEqualStrings("keep", ids[0]);
	const options = cfg.direct("keep") orelse return error.MissingOptions;
	try std.testing.expectEqualStrings("blue", options.table.entries.items[0].value.string);
}

test "a requires mismatch skips only the hypr plugin" {
	var tmp = std.testing.tmpDir(.{});
	defer tmp.cleanup();

	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();
	const a = arena.allocator();

	const loader = try testLoader(&tmp, a);
	defer loader.deinit();

	try proc.writeFile(std.testing.io, loader.paths.load, "load = [\"future\"]\n");
	try testPlugin(a, loader.paths, "future", "hypr", "\n[requires]\nhyprland = \">=999.0\"\n");
	loader.reloadLocked();

	if (loader.hyprland.len == 0) return error.SkipZigTest;

	try std.testing.expectEqual(@as(usize, 1), loader.rows.len);
	try std.testing.expectEqualStrings("failed", loader.rows[0].state);
	try std.testing.expectEqualStrings("HyprlandVersion", loader.rows[0].failure);
}

test "a binary in a plugin folder fails that plugin" {
	var tmp = std.testing.tmpDir(.{});
	defer tmp.cleanup();

	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();
	const a = arena.allocator();

	const loader = try testLoader(&tmp, a);
	defer loader.deinit();

	try testPlugin(a, loader.paths, "bad", "app", "");
	try proc.writeFile(std.testing.io, try std.fmt.allocPrint(a, "{s}/bad/x.bin", .{loader.paths.repo}), "\x7fELF");
	try proc.writeFile(std.testing.io, loader.paths.load, "load = [\"bad\"]\n");
	loader.reloadLocked();

	try std.testing.expectEqual(@as(usize, 1), loader.rows.len);
	try std.testing.expectEqualStrings("BinaryInPlugin", loader.rows[0].failure);
}

test "themes layer in load order" {
	var tmp = std.testing.tmpDir(.{});
	defer tmp.cleanup();

	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();
	const a = arena.allocator();

	const loader = try testLoader(&tmp, a);
	defer loader.deinit();

	try testTheme(a, loader.paths, "base", "surface", "#101010", "red", "#ff0000");
	try testTheme(a, loader.paths, "over", "surface", "#202020", "yellow", "#ffff00");
	try proc.writeFile(std.testing.io, loader.paths.load, "load = [\"base\", \"over\"]\n");
	loader.reloadLocked();

	try std.testing.expectEqual(@as(usize, 2), loader.rows.len);
	try std.testing.expectEqualStrings("loaded", loader.rows[0].state);
	try std.testing.expectEqualStrings("loaded", loader.rows[1].state);

	const body = try proc.readFile(std.testing.io, std.testing.allocator, try loader.paths.theme(a));
	defer std.testing.allocator.free(body);
	try std.testing.expect(std.mem.indexOf(u8, body, "surface = \"#202020\"") != null);
	try std.testing.expect(std.mem.indexOf(u8, body, "red = \"#ff0000\"") != null);
	try std.testing.expect(std.mem.indexOf(u8, body, "yellow = \"#ffff00\"") != null);
}

test "the theme verb swaps the loaded theme and keeps the rest" {
	var tmp = std.testing.tmpDir(.{});
	defer tmp.cleanup();

	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();
	const a = arena.allocator();

	const loader = try testLoader(&tmp, a);
	defer loader.deinit();

	try testTheme(a, loader.paths, "base", "surface", "#101010", "red", "#ff0000");
	try testTheme(a, loader.paths, "over", "surface", "#202020", "yellow", "#ffff00");
	try proc.writeFile(std.testing.io, loader.paths.load, "load = [\"base\", \"missing\"]\n");

	try loader.setThemeLocked("over");
	try std.testing.expectError(error.NotATheme, loader.setThemeLocked("missing"));
	loader.reloadLocked();

	try std.testing.expectEqual(@as(usize, 2), loader.rows.len);
	try std.testing.expectEqualStrings("missing", loader.rows[0].id);
	try std.testing.expectEqualStrings("over", loader.rows[1].id);

	try std.testing.expectEqual(@as(usize, 2), loader.themes.len);
	try std.testing.expectEqualStrings("base", loader.themes[0].id);
	try std.testing.expect(!loader.themes[0].active);
	try std.testing.expect(loader.themes[1].active);
	try std.testing.expectEqualStrings("#202020", loader.themes[1].surface);
	try std.testing.expectEqualStrings("#ffff00", loader.themes[1].accents[0]);
}

fn testTheme(arena: Allocator, paths: Paths, id: []const u8, key_a: []const u8, value_a: []const u8, key_b: []const u8, value_b: []const u8) !void {
	const dir = try std.fmt.allocPrint(arena, "{s}/{s}", .{ paths.repo, id });
	const manifest = try std.fmt.allocPrint(arena, "id = \"{s}\"\nkind = \"theme\"\nversion = \"0.1.0\"\nbuild = \"cp theme.toml $OUT\"\nprovides = [\"theme.toml\"]\n", .{id});
	const theme = try std.fmt.allocPrint(arena, "[colors]\n{s} = \"{s}\"\n{s} = \"{s}\"\n", .{ key_a, value_a, key_b, value_b });
	try proc.writeFile(std.testing.io, try std.fmt.allocPrint(arena, "{s}/plugin.toml", .{dir}), manifest);
	try proc.writeFile(std.testing.io, try std.fmt.allocPrint(arena, "{s}/theme.toml", .{dir}), theme);
}

test "a real hypr template builds and writes loaded.lua" {
	var tmp = std.testing.tmpDir(.{});
	defer tmp.cleanup();

	var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
	defer arena.deinit();
	const a = arena.allocator();

	const loader = try testLoader(&tmp, a);
	defer loader.deinit();

	const repo = proc.repo(std.testing.io, a);
	const paths = Paths{
		.load = loader.paths.load,
		.repo = try std.fmt.allocPrint(a, "{s}/plugins", .{repo}),
		.data = loader.paths.data,
		.state = loader.paths.state,
	};
	loader.paths = paths;
	loader.live = false;

	try proc.writeFile(std.testing.io, paths.load, "load = [\"_template-hypr\"]\n\n[_template-hypr]\nenabled = false\n");
	loader.reloadLocked();

	if (loader.hyprland.len == 0) return error.SkipZigTest;

	try std.testing.expectEqual(@as(usize, 1), loader.rows.len);
	try std.testing.expectEqualStrings("", loader.rows[0].failure);
	try std.testing.expectEqualStrings("loaded", loader.rows[0].state);

	const body = try proc.readFile(std.testing.io, std.testing.allocator, try paths.loaded(a));
	defer std.testing.allocator.free(body);
	try std.testing.expect(std.mem.indexOf(u8, body, "template-hypr.so") != null);
	try std.testing.expect(std.mem.indexOf(u8, body, "options = { [\"enabled\"] = false }") != null);
}

