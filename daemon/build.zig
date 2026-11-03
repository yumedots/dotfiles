const std = @import("std");

pub fn build(b: *std.Build) void {
	const target = b.standardTargetOptions(.{});
	const debug = b.option(bool, "debug", "debug build with symbols") orelse false;
	const small = b.option(bool, "small", "optimize for size") orelse false;
	const optimize = if (debug) std.builtin.OptimizeMode.Debug else if (small) std.builtin.OptimizeMode.ReleaseSmall else b.standardOptimizeOption(.{ .preferred_optimize_mode = .safe });
	const use_llvm = b.option(bool, "llvm", "use LLVM (false is much faster to build but much slower to run)") orelse true;

	const root = b.root.toString(b.allocator) catch @panic("OOM");
	const index_path: []const u8 = b.pathResolve(&.{ root, "assets", "launcher-index.bin.gz" });
	const script_path: []const u8 = b.pathResolve(&.{ root, "tools", "build-index.py" });
	const index_step = b.addSystemCommand(&.{
		"sh", "-c", "test -f \"$1\" || exec python3 \"$2\" \"$1\"", "sh", index_path, script_path,
	});
	index_step.has_side_effects = true;

	const exe = b.addExecutable(.{
		.name = "yudaemond",
		.use_llvm = use_llvm,
		.root_module = b.createModule(.{
			.root_source_file = b.path("src/main.zig"),
			.target = target,
			.optimize = optimize,
			.strip = optimize != .debug,
		}),
	});

	exe.root_module.link_libc = true;
	exe.root_module.addIncludePath(b.path("src/c"));
	exe.root_module.addCSourceFile(.{ .file = b.path("src/c/notifybus.c"), .flags = &.{"-std=c11"} });
	exe.root_module.addCSourceFile(.{ .file = b.path("src/c/traybus.c"), .flags = &.{"-std=c11"} });
	exe.root_module.linkSystemLibrary("libsystemd", .{});

	exe.step.dependOn(&index_step.step);

	b.installArtifact(exe);

	const run = b.addRunArtifact(exe);
	b.step("run", "run yudaemond").dependOn(&run.step);

	const tests = b.addTest(.{
		.root_module = b.createModule(.{
			.root_source_file = b.path("src/tests.zig"),
			.target = target,
			.optimize = optimize,
		}),
	});

	tests.root_module.link_libc = true;
	tests.root_module.addIncludePath(b.path("src/c"));
	tests.root_module.addCSourceFile(.{ .file = b.path("src/c/notifybus.c"), .flags = &.{"-std=c11"} });
	tests.root_module.addCSourceFile(.{ .file = b.path("src/c/traybus.c"), .flags = &.{"-std=c11"} });
	tests.root_module.linkSystemLibrary("libsystemd", .{});

	const run_tests = b.addRunArtifact(tests);
	run_tests.step.dependOn(&index_step.step);
	b.step("test", "run the logic checks").dependOn(&run_tests.step);
}
