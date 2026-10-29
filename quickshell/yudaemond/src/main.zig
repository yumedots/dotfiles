const std = @import("std");
const hubmod = @import("hub.zig");
const ipc = @import("ipc.zig");
const proc = @import("primitives/proc.zig");
const sock = @import("primitives/sock.zig");
const http = @import("primitives/http.zig");
const opencode = @import("providers/opencode.zig");
const codex = @import("providers/codex.zig");
const cursor = @import("providers/cursor.zig");
const daemon = @import("providers/daemon.zig");
const github = @import("providers/github.zig");
const weather = @import("providers/weather.zig");
const system = @import("providers/system.zig");
const apps = @import("providers/apps.zig");
const screen = @import("providers/screen.zig");
const settings = @import("providers/settings.zig");
const config_provider = @import("providers/config.zig");
const network = @import("providers/network.zig");
const audio = @import("providers/audio.zig");
const wallpaper = @import("providers/wallpaper.zig");
const ink = @import("providers/ink.zig");
const bar = @import("providers/bar.zig");
const launcher = @import("providers/launcher.zig");
const icons = @import("providers/icons.zig");
const subscriptions = @import("providers/subscriptions.zig");
const supervisor = @import("providers/supervisor.zig");
const versions = @import("providers/versions.zig");
const windows = @import("providers/windows.zig");
const media = @import("providers/media.zig");
const calendar = @import("providers/calendar.zig");
const iconsmod = @import("primitives/icons.zig");
const cli = @import("cli.zig");
const json = @import("primitives/json.zig");
const sleep = @import("primitives/sleep.zig");
const environ = @import("primitives/environ.zig");
const exec = @import("primitives/exec.zig");
const fmtmod = @import("primitives/fmt.zig");

pub const allocator = std.heap.smp_allocator;

pub const Context = struct {
	allocator: std.mem.Allocator,
	io: std.Io,
	hub: *hubmod.Hub,
	client: *http.Client,
	opencode: *opencode.Opencode,
	codex: *codex.Codex,
	cursor: *cursor.Cursor,
	daemon: *daemon.Daemon,
	github: *github.Github,
	weather: *weather.Weather,
	system: *system.System,
	apps: *apps.Apps,
	screen: *screen.Screen,
	settings: *settings.Settings,
	network: *network.Network,
	audio: *audio.Audio,
	wallpaper: *wallpaper.Wallpaper,
	ink: *ink.Ink,
	bar: *bar.Bar,
	launcher: *launcher.Launcher,
	icons: *icons.Icons,
	subscriptions: *subscriptions.Subscriptions,
	supervisor: *supervisor.Supervisor,
	versions: *versions.Versions,
	windows: *windows.Windows,
	media: *media.Media,
	calendar: *calendar.Calendar,
	socket_path: []const u8,
};

pub fn socketPath(io: std.Io, allocator_: std.mem.Allocator) ![]u8 {
	return proc.socketPath(io, allocator_);
}

fn dismissThunk(ctx: *anyopaque, id: []const u8) void {
	const context: *Context = @ptrCast(@alignCast(ctx));
	context.opencode.dismiss(id);
}

fn snapshotThunk(ctx: *anyopaque, allocator_: std.mem.Allocator) anyerror![]u8 {
	const context: *Context = @ptrCast(@alignCast(ctx));
	return context.hub.snapshot(allocator_);
}

fn syncThunk(ctx: *anyopaque, allocator_: std.mem.Allocator) anyerror![]u8 {
	const context: *Context = @ptrCast(@alignCast(ctx));
	return context.hub.syncSnapshot(allocator_);
}

fn commandThunk(ctx: *anyopaque, value: json.Value) void {
	const context: *Context = @ptrCast(@alignCast(ctx));

	if (json.field(value, "audio")) |audio_cmd| {
		if (json.field(audio_cmd, "volume")) |target| {
			const id = json.integer(json.field(target, "id"));
			const level = json.numberAt(target, "level");

			if (id > 0) context.audio.setVolume(id, level);
		}

		if (json.field(audio_cmd, "mute")) |target| {
			const id = json.integer(json.field(target, "id"));
			const muted = json.flag(target, "muted");

			if (id > 0) context.audio.setMute(id, muted);
		}

		if (json.field(audio_cmd, "default")) |target| {
			const id = json.integer(json.field(target, "id"));

			if (id > 0) context.audio.setDefault(id);
		}

		if (json.field(audio_cmd, "watch")) |target| {
			context.audio.setWatch(json.flag(target, "on"));
		}

		return;
	}

	if (json.field(value, "network")) |net_cmd| {
		if (json.flag(net_cmd, "scan")) context.network.scan(true);

		if (json.field(net_cmd, "connect")) |target| {
			const ssid = json.textAt(target, "ssid");
			const password = json.textAt(target, "password");

			if (ssid.len > 0) context.network.connect(ssid, password);
		}

		if (json.field(net_cmd, "dns")) |target| {
			context.network.dnsCmd(json.textAt(target, "action"), json.textAt(target, "server"));
		}

		if (json.field(net_cmd, "inject")) |target| {
			context.network.inject(target);
		}

		if (json.flag(net_cmd, "speed")) context.network.speedTest();
		if (json.flag(net_cmd, "speedCancel")) context.network.speedCancel();

		return;
	}

	if (json.field(value, "icons")) |icon_cmd| {
		if (json.field(icon_cmd, "want")) |list| {
			for (json.list(list)) |item| context.icons.want(json.text(item));
		}

		const pid = json.integer(json.field(icon_cmd, "pid"));
		if (pid > 0) context.icons.wantPid(pid);

		return;
	}

	if (json.field(value, "launcher")) |l_cmd| {
		if (json.field(l_cmd, "query") != null) {
			context.launcher.setQuery(
				json.textAt(l_cmd, "query"),
				json.textAt(l_cmd, "forced"),
				json.textAt(l_cmd, "group"),
			);
		}

		const pin = json.textAt(l_cmd, "pin");
		if (pin.len > 0) context.launcher.togglePin(pin);

		const save = json.textAt(l_cmd, "save");
		if (save.len > 0) context.launcher.saveQuery(save);

		const remember = json.textAt(l_cmd, "remember");
		if (remember.len > 0) context.launcher.remember(remember);

		const clip = json.textAt(l_cmd, "clip");
		if (json.field(l_cmd, "clip") != null) context.launcher.previewClip(clip);

		const copy = json.textAt(l_cmd, "copyClip");
		if (copy.len > 0) context.launcher.copyClip(copy);

		const activate = json.textAt(l_cmd, "activate");
		if (activate.len > 0) context.launcher.activate(activate);

		const copy_text = json.textAt(l_cmd, "copyText");
		if (json.field(l_cmd, "copyText") != null) context.launcher.copyText(copy_text);

		const kill = json.integer(json.field(l_cmd, "kill"));
		if (kill > 0) context.launcher.killProcess(@intCast(kill));

		if (json.flag(l_cmd, "clips")) context.launcher.refreshClips();

		if (json.field(l_cmd, "wake")) |target| {
			context.launcher.wake(
				json.textAt(target, "sock"),
				json.integer(json.field(target, "pid")),
				json.textAt(target, "path"),
			);
		}

		return;
	}

	if (json.field(value, "file")) |file_cmd| {
		if (json.field(file_cmd, "write")) |target| {
			const path = json.textAt(target, "path");

			if (path.len > 0) proc.writeFile(context.io, path, json.textAt(target, "text")) catch {};
		}

		return;
	}

	if (json.field(value, "ink")) |ink_cmd| {
		const band = json.integer(json.field(ink_cmd, "band"));
		const bare = if (json.field(ink_cmd, "bare") != null) json.flag(ink_cmd, "bare") else null;

		context.ink.set(band, bare);
		return;
	}

	if (json.field(value, "windows")) |wi_cmd| {
		if (json.field(wi_cmd, "query") != null) context.windows.setQuery(json.textAt(wi_cmd, "query"));

		const focus = json.textAt(wi_cmd, "focus");
		if (focus.len > 0) context.windows.focus(focus);

		const launch = json.textAt(wi_cmd, "launch");
		if (launch.len > 0) context.windows.launch(launch);

		return;
	}

	if (json.field(value, "wallpaper")) |wp_cmd| {
		if (json.field(wp_cmd, "apply")) |target| {
			const path = json.textAt(target, "path");
			const band = json.integer(json.field(target, "band"));

			if (path.len > 0) {
				const t0 = fmtmod.nowMs(context.io);
				context.wallpaper.save(path);
				const t1 = fmtmod.nowMs(context.io);
				context.ink.apply(path, band);
				const t2 = fmtmod.nowMs(context.io);
				std.debug.print("DBG cmd save={d} apply={d}\n", .{ t1 - t0, t2 - t1 });
			}
		}

		if (json.flag(wp_cmd, "scan")) context.wallpaper.reload();

		return;
	}

	if (json.field(value, "screen")) |screen_cmd| {
		const key = json.textAt(screen_cmd, "key");
		if (key.len > 0) context.screen.key(key);

		const code = json.field(screen_cmd, "keyCode");
		if (code) |value_code| context.screen.keyCode(json.integer(value_code));

		if (json.field(screen_cmd, "pick")) |pick| {
			const kind = json.textAt(pick, "kind");
			const choice = json.textAt(pick, "value");

			if (kind.len > 0) context.screen.pick(kind, choice);
		}

		if (json.flag(screen_cmd, "detect")) context.screen.detect();

		return;
	}

	if (json.field(value, "settings")) |settings_cmd| {
		if (json.field(settings_cmd, "font")) |size| {
			context.settings.setFontSize(json.integer(size));
		}

		if (json.field(settings_cmd, "output")) |output| {
			const name = json.textAt(output, "name");
			const mode = json.field(output, "mode");
			const scale = json.field(output, "scale");

			if (name.len > 0) {
				context.settings.setOutput(
					name,
					if (mode) |m| json.text(m) else null,
					if (scale) |s| json.number(s) else null,
				);
			}
		}

		return;
	}

	if (json.field(value, "system")) |system_cmd| {
		const governor = json.textAt(system_cmd, "governor");
		if (governor.len > 0) context.system.setGovernor(governor);

		if (json.field(system_cmd, "panel")) |panel| {
			context.system.setPanel(json.textAt(panel, "field"), json.textAt(panel, "query"));
		}

		return;
	}

	if (json.field(value, "calendar")) |calendar_cmd| {
		if (json.field(calendar_cmd, "days")) |days| context.calendar.shiftDays(json.integer(days));
		if (json.field(calendar_cmd, "months")) |months| context.calendar.shiftMonths(json.integer(months));
		if (json.field(calendar_cmd, "years")) |years| context.calendar.shiftYears(json.integer(years));
		if (json.field(calendar_cmd, "weekStart")) |start| context.calendar.setWeekStart(json.integer(start));
		if (json.flag(calendar_cmd, "reset")) context.calendar.reset();

		return;
	}

	if (json.field(value, "media")) |action| {
		context.media.action(json.text(action));
		return;
	}

	const weather_cmd = json.field(value, "weather") orelse return;

	if (json.field(weather_cmd, "shift")) |step| {
		context.weather.shift(json.integer(step));
		return;
	}

	if (json.field(weather_cmd, "focus")) |at| {
		context.weather.focus(@intCast(json.integer(at)));
		return;
	}

	if (json.field(weather_cmd, "query")) |query| {
		context.weather.setQuery(json.text(query));
		return;
	}

	if (json.field(weather_cmd, "search")) |query| {
		context.weather.search(json.text(query));
		return;
	}

	if (json.field(weather_cmd, "dismiss")) |_| {
		context.weather.dismissSuggestions();
		return;
	}

	const pick = json.field(weather_cmd, "choose") orelse json.field(weather_cmd, "add") orelse return;
	const label = json.textAt(pick, "label");
	const lat = json.numberAt(pick, "lat");
	const lon = json.numberAt(pick, "lon");

	if (json.field(weather_cmd, "add") != null) {
		context.weather.add(label, lat, lon);
	} else {
		context.weather.choose(label, lat, lon);
	}
}

fn refreshThunk(ctx: *anyopaque) void {
	const context: *Context = @ptrCast(@alignCast(ctx));
	context.opencode.refreshAll();
	context.subscriptions.refresh();
	context.github.refresh();
	context.weather.search("");
}

pub fn main() !void {
	const env = try environ.current(std.Io.Threaded.global_single_threaded.io(), allocator);
	var threaded: std.Io.Threaded = .init(allocator, .{ .environ = env, .async_limit = .nothing, .concurrent_limit = .nothing, .stack_size = 512 * 1024 });
	const io = threaded.io();

	const args = try proc.args(io, allocator);

	const command = if (args.len > 1) args[1] else "run";

	if (std.mem.eql(u8, command, "state") or std.mem.eql(u8, command, "--json")) {
		return cli.state(io, args);
	}

	if (std.mem.eql(u8, command, "doctor")) return cli.doctor(io, args);
	if (std.mem.eql(u8, command, "bench")) return cli.bench(io, args);
	if (std.mem.eql(u8, command, "parity")) return cli.parity(io, args);
	if (std.mem.eql(u8, command, "mcp")) return cli.mcp(io, args);

	if (!std.mem.eql(u8, command, "run")) {
		std.debug.print("usage: yudaemond [run|state|doctor|bench [widgets]|parity|mcp]\n", .{});
		return;
	}

	try run(io);
}

fn beat(hub: *hubmod.Hub) void {
	while (true) {
		sleep.ms(15_000);
		hub.publish();
	}
}

fn run(io: std.Io) !void {
	const socket_path = try socketPath(io, allocator);
	const lock_path = try std.fmt.allocPrint(allocator, "{s}.lock", .{socket_path});

	var guard = (try sock.Lock.take(lock_path)) orelse {
		std.debug.print("yudaemond already serves {s}\n", .{socket_path});
		return;
	};
	defer guard.release();

	const hub = try allocator.create(hubmod.Hub);
	hub.* = .{ .allocator = allocator, .io = io };

	const client = try allocator.create(http.Client);
	client.* = http.Client.init(allocator, io);

	const opencode_provider = try opencode.Opencode.create(allocator, io, hub, client);
	try hub.add(opencode_provider.provider());

	const codex_provider = try codex.Codex.create(allocator, io, hub, client);
	try hub.add(codex_provider.provider());

	const cursor_provider = try cursor.Cursor.create(allocator, io, hub);
	try hub.add(cursor_provider.provider());

	const daemon_provider = try daemon.Daemon.create(allocator, io, hub);
	try hub.add(daemon_provider.provider());

	const github_provider = try github.Github.create(allocator, io, hub, client);
	try hub.add(github_provider.provider());

	const weather_provider = try weather.Weather.create(allocator, io, hub, client);
	try hub.add(weather_provider.provider());

	const system_provider = try system.System.create(allocator, io, hub);
	try hub.add(system_provider.provider());

	const apps_provider = try apps.Apps.create(allocator, io, hub);
	try hub.add(apps_provider.provider());

	const screen_provider = try screen.Screen.create(allocator, io, hub);
	try hub.add(screen_provider.provider());

	const settings_provider = try settings.Settings.create(allocator, io, hub);
	try hub.add(settings_provider.provider());

	const config_settings = try config_provider.Config.create(allocator, io, hub);
	try hub.add(config_settings.provider());

	const network_provider = try network.Network.create(allocator, io, hub);
	try hub.add(network_provider.provider());

	const audio_provider = try audio.Audio.create(allocator, io, hub);
	try hub.add(audio_provider.provider());

	const wallpaper_provider = try wallpaper.Wallpaper.create(allocator, io, hub);
	try hub.add(wallpaper_provider.provider());

	const ink_provider = try ink.Ink.create(allocator, io, hub);
	ink_provider.attach(wallpaper_provider);
	wallpaper_provider.onRescan(.{ .ctx = ink_provider, .run = ink.Ink.rescanned });
	try hub.add(ink_provider.provider());

	const bar_provider = try bar.Bar.create(allocator, io, hub);
	try hub.add(bar_provider.provider());

	const versions_provider = try versions.Versions.create(allocator, io, hub);
	try hub.add(versions_provider.provider());

	const windows_provider = try windows.Windows.create(allocator, io, hub);
	try hub.add(windows_provider.provider());

	const supervisor_provider = try supervisor.Supervisor.create(allocator, io, hub);
	try hub.add(supervisor_provider.provider());

	const subscriptions_provider = try subscriptions.Subscriptions.create(allocator, io, hub, opencode_provider, codex_provider);
	try hub.add(subscriptions_provider.provider());

	const icon_resolver = try iconsmod.Icons.create(allocator, io);
	const icons_provider = try icons.Icons.create(allocator, io, hub, icon_resolver);
	icons_provider.attach(apps_provider);
	try hub.add(icons_provider.provider());

	const launcher_provider = try launcher.Launcher.create(allocator, io, hub);
	launcher_provider.attach(apps_provider, system_provider, windows_provider);
	try hub.add(launcher_provider.provider());

	const media_provider = try media.Media.create(allocator, io, hub);
	try hub.add(media_provider.provider());

	const calendar_provider = try calendar.Calendar.create(allocator, io, hub);
	try hub.add(calendar_provider.provider());

	screen_provider.attachSettings(settings_provider);

	const context = try allocator.create(Context);
	context.* = .{
		.allocator = allocator,
		.io = io,
		.hub = hub,
		.client = client,
		.opencode = opencode_provider,
		.codex = codex_provider,
		.cursor = cursor_provider,
		.daemon = daemon_provider,
		.github = github_provider,
		.weather = weather_provider,
		.system = system_provider,
		.apps = apps_provider,
		.screen = screen_provider,
		.settings = settings_provider,
		.network = network_provider,
		.audio = audio_provider,
		.wallpaper = wallpaper_provider,
		.ink = ink_provider,
		.bar = bar_provider,
		.launcher = launcher_provider,
		.icons = icons_provider,
		.subscriptions = subscriptions_provider,
		.supervisor = supervisor_provider,
		.versions = versions_provider,
		.windows = windows_provider,
		.media = media_provider,
		.calendar = calendar_provider,
		.socket_path = socket_path,
	};

	std.debug.print("yudaemond listening on {s}\n", .{context.socket_path});

	hub.ipc = try ipc.Ipc.init(allocator, io, context.socket_path, .{
		.ctx = context,
		.snapshot = snapshotThunk,
		.sync = syncThunk,
		.dismiss = dismissThunk,
		.refresh = refreshThunk,
		.command = commandThunk,
	});

	try hub.ipc.?.start();
	daemon_provider.markListening();
	try system_provider.start();
	try opencode_provider.start();
	try codex_provider.start();
	try cursor_provider.start();
	try github_provider.start();
	try weather_provider.start();
	try apps_provider.start();
	try screen_provider.start();
	try settings_provider.start();
	try config_settings.start();
	try network_provider.start();
	try audio_provider.start();
	try wallpaper_provider.start();
	try ink_provider.start();
	try bar_provider.start();
	try launcher_provider.start();
	try icons_provider.start();
	try media_provider.start();
	try subscriptions_provider.start();
	try supervisor_provider.start();
	try versions_provider.start();
	try windows_provider.start();

	hub.publish();

	const heartbeat = try std.Thread.spawn(.{}, beat, .{hub});
	heartbeat.detach();

	sleep.forever();
}
