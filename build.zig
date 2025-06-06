const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .dynamic,
        .name = "uuidz",
        .root_module = mod,
    });

    lib.linkLibC();
    lib.linkSystemLibrary("uuid");

    b.installArtifact(lib);

    const tests = b.addTest(.{
        .root_module = mod,
    });

    const test_artifact = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run unit tests");

    test_step.dependOn(&test_artifact.step);
}
