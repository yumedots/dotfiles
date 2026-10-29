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

	const run_tests = b.addRunArtifact(tests);
	b.step("test", "run the logic checks").dependOn(&run_tests.step);
}
