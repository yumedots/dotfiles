const std = @import("std");

pub fn build(b: *std.Build) void {
	const target = b.standardTargetOptions(.{});
	const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .safe });

	const exe = b.addExecutable(.{
		.name = "yudaemond",
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
	b.step("test", "run the logic checks").dependOn(&run_tests.step);
}
