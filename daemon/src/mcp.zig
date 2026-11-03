const std = @import("std");
const json = @import("primitives/json.zig");
const proc = @import("primitives/proc.zig");
const sock = @import("primitives/sock.zig");
const exec = @import("primitives/exec.zig");

const gpa = std.heap.smp_allocator;
const Io = std.Io;

const Tool = struct {
	name: []const u8,
	description: []const u8,
	inputSchema: []const u8,
};

const tools = [_]Tool{
	.{ .name = "state", .description = "Full yudaemond state as JSON.", .inputSchema = "{\"type\":\"object\",\"properties\":{}}" },
	.{ .name = "providers", .description = "Per provider health: opencode, codex, cursor.", .inputSchema = "{\"type\":\"object\",\"properties\":{}}" },
	.{ .name = "bench", .description = "Build, start, idle RSS/CPU, shell total and hoggers.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"seconds\":{\"type\":\"integer\"}}}" },
	.{ .name = "parity", .description = "State parity check for the panel.", .inputSchema = "{\"type\":\"object\",\"properties\":{}}" },
	.{ .name = "hypr_start", .description = "Start the nested Hyprland test instance.", .inputSchema = "{\"type\":\"object\",\"properties\":{}}" },
	.{ .name = "hypr_shot", .description = "Screenshot the test instance, returns the png path.", .inputSchema = "{\"type\":\"object\",\"properties\":{}}" },
	.{ .name = "hypr_run", .description = "Run a command inside the test instance.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"args\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}},\"required\":[\"args\"]}" },
	.{ .name = "hypr_stop", .description = "Stop the test instance and remove its worktree.", .inputSchema = "{\"type\":\"object\",\"properties\":{}}" },
	.{ .name = "qs_log", .description = "Tail the newest quickshell log.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"lines\":{\"type\":\"integer\"}}}" },
	.{ .name = "vm_create", .description = "Boot a VM from the golden layer.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"from\":{\"type\":\"string\"},\"cores\":{\"type\":\"integer\"},\"mem\":{\"type\":\"integer\"},\"gl\":{\"type\":\"boolean\"},\"agent\":{\"type\":\"string\"}}}" },
	.{ .name = "vm_start", .description = "Boot an existing VM.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}},\"required\":[\"name\"]}" },
	.{ .name = "vm_list", .description = "List VMs, tiers and resource use.", .inputSchema = "{\"type\":\"object\",\"properties\":{}}" },
	.{ .name = "vm_state", .description = "The guest daemon snapshot.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}},\"required\":[\"name\"]}" },
	.{ .name = "vm_exec", .description = "Run a command in the guest daemon.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"cmd\":{\"type\":\"string\"},\"argv\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}},\"required\":[\"name\"]}" },
	.{ .name = "vm_screenshot", .description = "Write a PNG screenshot and return its path.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"path\":{\"type\":\"string\"}},\"required\":[\"name\"]}" },
	.{ .name = "vm_key", .description = "Send key codes at compositor level.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"keys\":{\"type\":\"array\",\"items\":{\"type\":\"string\"}}},\"required\":[\"name\",\"keys\"]}" },
	.{ .name = "vm_type", .description = "Type text at compositor level.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"text\":{\"type\":\"string\"}},\"required\":[\"name\",\"text\"]}" },
	.{ .name = "vm_click", .description = "Move and click the pointer.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"x\":{\"type\":\"number\"},\"y\":{\"type\":\"number\"},\"button\":{\"type\":\"string\"}},\"required\":[\"name\",\"x\",\"y\"]}" },
	.{ .name = "vm_move", .description = "Move the pointer.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"x\":{\"type\":\"number\"},\"y\":{\"type\":\"number\"}},\"required\":[\"name\",\"x\",\"y\"]}" },
	.{ .name = "vm_wait", .description = "Wait for a guest predicate, no sleep loops.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"until\":{\"type\":\"string\"},\"timeout\":{\"type\":\"integer\"}},\"required\":[\"name\",\"until\"]}" },
	.{ .name = "vm_stop", .description = "Exit QEMU and keep the run overlay for an offline snapshot.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}},\"required\":[\"name\"]}" },
	.{ .name = "vm_sleep", .description = "Stop the VM and inflate the balloon.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}},\"required\":[\"name\"]}" },
	.{ .name = "vm_park", .description = "Stop the VM and reclaim its cgroup memory.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}},\"required\":[\"name\"]}" },
	.{ .name = "vm_wake", .description = "Deflate the balloon and continue the VM.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}},\"required\":[\"name\"]}" },
	.{ .name = "vm_destroy", .description = "Quit QEMU and delete the run overlay.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}},\"required\":[\"name\"]}" },
	.{ .name = "vm_snapshot", .description = "Snapshot the run overlay.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"tag\":{\"type\":\"string\"}},\"required\":[\"name\",\"tag\"]}" },
	.{ .name = "vm_restore", .description = "Restore the run overlay snapshot.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"tag\":{\"type\":\"string\"}},\"required\":[\"name\",\"tag\"]}" },
	.{ .name = "vm_fork", .description = "Clone a VM disk into a new VM.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"from\":{\"type\":\"string\"}},\"required\":[\"name\",\"from\"]}" },
	.{ .name = "vm_view", .description = "Open the VM window and hand input to the human.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}},\"required\":[\"name\"]}" },
	.{ .name = "vm_push", .description = "Copy a host file into the guest.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"path\":{\"type\":\"string\"},\"to\":{\"type\":\"string\"}},\"required\":[\"name\",\"path\"]}" },
	.{ .name = "vm_pull", .description = "Copy a guest file to the host.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"path\":{\"type\":\"string\"},\"to\":{\"type\":\"string\"}},\"required\":[\"name\",\"path\"]}" },
	.{ .name = "vm_ui_tree", .description = "Guest state plus the Hyprland client tree.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"}},\"required\":[\"name\"]}" },
	.{ .name = "vm_run_scenario", .description = "Run a deterministic VM scenario.", .inputSchema = "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\"},\"scenario\":{\"type\":\"string\"}},\"required\":[\"scenario\"]}" },
};

pub fn run(io: Io, args: []const []const u8) !void {
	_ = args;

	var in_buffer: [65536]u8 = undefined;
	var reader = std.Io.File.stdin().reader(io, &in_buffer);

	var out_buffer: [16384]u8 = undefined;
	var file_writer = std.Io.File.stdout().writer(io, &out_buffer);
	const writer = &file_writer.interface;

	while (true) {
		const line = reader.interface.takeDelimiter('\n') catch break orelse break;
		const message = std.mem.trim(u8, line, " \r");
		if (message.len == 0) continue;

		var arena = std.heap.ArenaAllocator.init(gpa);
		defer arena.deinit();
		const allocator = arena.allocator();

		const parsed = json.parse(allocator, message) catch continue;
		const root = parsed.value;
		const id = json.field(root, "id") orelse json.Value{ .null = {} };
		const method = json.textAt(root, "method");

		if (std.mem.eql(u8, method, "initialize")) {
			try respond(writer, allocator, id, Initialize{
				.protocolVersion = "2025-06-18",
				.serverInfo = .{ .name = "yudaemond", .version = "1" },
				.capabilities = .{ .tools = .{} },
			});
			continue;
		}

		if (std.mem.eql(u8, method, "tools/list")) {
			try respond(writer, allocator, id, .{ .tools = &tools });
			continue;
		}

		if (std.mem.eql(u8, method, "tools/call")) {
			const params = json.field(root, "params") orelse json.Value{ .null = {} };
			const name = json.textAt(params, "name");
			const arguments = json.field(params, "arguments") orelse json.Value{ .object = .empty };

			const body = call(io, allocator, name, arguments) catch |err| {
				try respondError(writer, allocator, id, @errorName(err));
				continue;
			};

			try respond(writer, allocator, id, .{
				.content = &.{.{ .type = "text", .text = body }},
				.isError = false,
			});
			continue;
		}

		try respondError(writer, allocator, id, "unknown method");
	}
}

fn call(io: Io, allocator: std.mem.Allocator, name: []const u8, arguments: json.Value) ![]const u8 {
	if (std.mem.eql(u8, name, "state")) return fetch(io, allocator);

	if (std.mem.eql(u8, name, "providers")) {
		const body = try fetch(io, allocator);
		const parsed = json.parse(allocator, body) catch return "{}";

		var report: std.ArrayList(u8) = .empty;

		for ([_][]const u8{ "opencode", "codex", "cursor", "daemon" }) |key| {
			const entry = json.field(parsed.value, key) orelse continue;
			try report.print(allocator, "{s}: {f}\n", .{ key, std.json.fmt(entry, .{}) });
		}

		return report.toOwnedSlice(allocator);
	}

	if (std.mem.eql(u8, name, "bench")) {
		const seconds = json.textAt(arguments, "seconds");
		const value = if (seconds.len > 0) seconds else "5";

		return runSelf(io, allocator, &.{ "bench", "--json", "--seconds", value });
	}

	if (std.mem.eql(u8, name, "parity")) return runSelf(io, allocator, &.{"parity"});

	if (std.mem.eql(u8, name, "hypr_start")) return hypr(io, allocator, &.{"start"});
	if (std.mem.eql(u8, name, "hypr_shot")) return hypr(io, allocator, &.{"shot"});
	if (std.mem.eql(u8, name, "hypr_stop")) return hypr(io, allocator, &.{"stop"});

	if (std.mem.eql(u8, name, "hypr_run")) {
		const list = json.listAt(arguments, "args");
		if (list.len == 0) return error.MissingArgs;

		var argv: std.ArrayList([]const u8) = .empty;
		try argv.append(allocator, "run");
		for (list) |entry| try argv.append(allocator, json.text(entry));

		return hypr(io, allocator, argv.items);
	}

	if (std.mem.eql(u8, name, "qs_log")) return logTail(io, allocator, arguments);

	if (std.mem.eql(u8, name, "vm_view")) {
		spawnViewer(io, allocator, json.textAt(arguments, "name"));
		return std.fmt.allocPrint(allocator, "{{\"viewing\":\"{s}\"}}", .{json.textAt(arguments, "name")});
	}

	if (std.mem.startsWith(u8, name, "vm_")) return callDaemon(io, allocator, "vms", name["vm_".len..], arguments);

	return error.UnknownTool;
}

fn spawnViewer(io: Io, allocator: std.mem.Allocator, name: []const u8) void {
	if (name.len == 0) return;

	const script = std.fmt.allocPrint(allocator, "{s}/scripts/yudae", .{proc.repo(io, allocator)}) catch return;

	_ = exec.spawn(io, .{
		.argv = &.{ "setsid", script, "vm", "view", name },
		.stdin = .ignore,
		.stdout = .ignore,
		.stderr = .ignore,
	}) catch return;
}

fn callDaemon(io: Io, allocator: std.mem.Allocator, target: []const u8, method: []const u8, arguments: json.Value) ![]const u8 {
	const path = try proc.socketPath(io, allocator);

	var out: std.Io.Writer.Allocating = .init(allocator);
	const writer = &out.writer;

	try writer.writeAll("{\"call\":{\"target\":");
	try std.json.Stringify.encodeJsonString(target, .{}, writer);
	try writer.writeAll(",\"method\":");
	try std.json.Stringify.encodeJsonString(method, .{}, writer);
	try writer.writeAll(",\"args\":");
	try writer.print("{f}", .{std.json.fmt(arguments, .{})});
	try writer.writeAll("}}");

	var buffer: [1048576]u8 = undefined;
	var connection = sock.Connection.connect(path, &buffer) catch return error.DaemonDown;
	defer connection.close();

	try connection.writeLine(out.written());

	var attempts: usize = 0;
	while (attempts < 20) : (attempts += 1) {
		const line = try connection.readLine() orelse return error.NoReply;
		const parsed = try json.parse(allocator, line);

		if (json.field(parsed.value, "ok") == null) continue;
		if (!json.flag(parsed.value, "ok")) return error.CallFailed;

		const result = json.field(parsed.value, "result") orelse return allocator.dupe(u8, "{}");

		var body: std.Io.Writer.Allocating = .init(allocator);
		try body.writer.print("{f}", .{std.json.fmt(result, .{})});
		return body.written();
	}

	return error.NoReply;
}

fn fetch(io: Io, allocator: std.mem.Allocator) ![]const u8 {
	const path = try proc.socketPath(io, allocator);
	var buffer: [1048576]u8 = undefined;
	var connection = sock.Connection.connect(path, &buffer) catch return error.DaemonDown;
	defer connection.close();

	try connection.writeLine(sock.sync);

	const line = try connection.readLine();
	return line orelse error.NoState;
}

fn runSelf(io: Io, allocator: std.mem.Allocator, argv: []const []const u8) ![]const u8 {
	const self_path = try proc.readFile(io, allocator, "/proc/self/exe");
	var full: std.ArrayList([]const u8) = .empty;
	try full.append(allocator, std.mem.trimEnd(u8, self_path, "\x00\n"));

	for (argv) |arg| try full.append(allocator, arg);

	const result = try exec.run(io, allocator, full.items);
	return result.out;
}

fn hypr(io: Io, allocator: std.mem.Allocator, argv: []const []const u8) ![]const u8 {
	const root = std.mem.trimEnd(u8, try proc.readFile(io, allocator, "/proc/self/exe"), "\x00\n");
	_ = root;

	const script = try std.fmt.allocPrint(allocator, "{s}/scripts/hypr-test", .{proc.repo(io, allocator)});

	var full: std.ArrayList([]const u8) = .empty;
	try full.append(allocator, script);
	for (argv) |arg| try full.append(allocator, arg);

	const result = try exec.run(io, allocator, full.items);
	return result.out;
}

fn logTail(io: Io, allocator: std.mem.Allocator, arguments: json.Value) ![]const u8 {
	const base = try std.fmt.allocPrint(allocator, "{s}/quickshell/by-id", .{proc.runtimeDir(io, allocator)});
	const newest = try newestDir(io, allocator, base);
	const path = try std.fmt.allocPrint(allocator, "{s}/log.qslog", .{newest});
	const body = try proc.readFile(io, allocator, path);

	const wanted = json.integer(json.field(arguments, "lines"));

	if (wanted <= 0) return body;

	var lines: std.ArrayList([]const u8) = .empty;
	var it = std.mem.splitScalar(u8, body, '\n');
	while (it.next()) |line| try lines.append(allocator, line);

	const total = lines.items.len;
	const count: usize = @intCast(@min(wanted, @as(i64, @intCast(total))));
	return std.mem.join(allocator, "\n", lines.items[total - count ..]);
}

fn newestDir(io: Io, allocator: std.mem.Allocator, base: []const u8) ![]const u8 {
	var dir = try std.Io.Dir.cwd().openDir(io, base, .{ .iterate = true });
	defer dir.close(io);

	var best: []const u8 = base;
	var it = dir.iterate();

	while (try it.next(io)) |entry| {
		if (entry.kind != .directory) continue;

		const candidate = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ base, entry.name });
		const stat = std.Io.Dir.cwd().statFile(io, candidate, .{}) catch continue;
		const current = std.Io.Dir.cwd().statFile(io, best, .{}) catch continue;

		if (stat.mtime.nanoseconds > current.mtime.nanoseconds) best = candidate;
	}

	return best;
}

const Initialize = struct {
	protocolVersion: []const u8,
	serverInfo: struct { name: []const u8, version: []const u8 },
	capabilities: struct { tools: struct {} },
};

fn write(writer: *std.Io.Writer, body: []const u8) !bool {
	writer.writeAll(body) catch return false;
	writer.flush() catch return false;
	return true;
}

fn respond(writer: *std.Io.Writer, allocator: std.mem.Allocator, id: json.Value, result: anytype) !void {
	const body = std.fmt.allocPrint(allocator, "{{\"jsonrpc\":\"2.0\",\"id\":{f},\"result\":{f}}}\n", .{ std.json.fmt(id, .{}), std.json.fmt(result, .{}) }) catch return error.OutOfMemory;

	_ = try write(writer, body);
}

fn respondError(writer: *std.Io.Writer, allocator: std.mem.Allocator, id: json.Value, message: []const u8) !void {
	const body = std.fmt.allocPrint(allocator, "{{\"jsonrpc\":\"2.0\",\"id\":{f},\"error\":{{\"code\":-32601,\"message\":\"{s}\"}}}}\n", .{ std.json.fmt(id, .{}), message }) catch return error.OutOfMemory;

	_ = try write(writer, body);
}
