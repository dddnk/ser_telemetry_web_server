const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Dependencies
    const serialz = b.dependency("serial", .{
        .target = target,
        .optimize = optimize,
    });
    const clap = b.dependency("clap", .{
        .target = target,
        .optimize = optimize,
    });
    const httpz = b.dependency("httpz", .{
        .target = target,
        .optimize = optimize,
    });

    // Modules
    const mod = b.addModule("ser_broadcast", .{ .root_source_file = b.path("src/root.zig"), .target = target, .strip = optimize != .Debug, .imports = &.{
        .{ .name = "httpz", .module = httpz.module("httpz") },
    } });

    const exe = b.addExecutable(.{
        .name = b.fmt("[{s}-{s}]ser_broadcast", .{ @tagName(target.result.cpu.arch), @tagName(target.result.os.tag) }),
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = optimize != .Debug,
            .imports = &.{
                .{ .name = "ser_broadcast", .module = mod },
                .{ .name = "serial", .module = serialz.module("serial") },
                .{ .name = "clap", .module = clap.module("clap") },
            },
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
