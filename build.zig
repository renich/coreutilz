const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("coreutilz", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const commands = [_][]const u8{
        "true",  "false",  "echo",   "cat",     "hostname", "logname",  "tty",  "whoami",
        "nproc", "hostid", "unlink", "dirname", "basename", "printenv", "pwd",  "readlink",
        "mkdir", "rmdir",  "rm",     "link",    "yes",      "sleep",    "sync", "env",
        "cp",    "mv",     "chmod",  "ln",      "stat",     "dd",       "head", "wc",
        "tee",   "truncate", "touch", "cut",
    };

    const needs_libc = [_][]const u8{
        "hostname", "logname",  "tty", "whoami", "nproc", "hostid", "sync", "env",
        "printenv", "sleep",    "pwd", "cp",     "mv",    "chmod",  "ln",   "stat",
        "dd",       "readlink", "rm",  "touch",
    };

    const install_step = b.getInstallStep();

    for (commands) |cmd| {
        const exe = b.addExecutable(.{
            .name = cmd,
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("src/wrappers/{s}_main.zig", .{cmd})),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "coreutilz", .module = mod },
                },
            }),
        });

        for (needs_libc) |libc_cmd| {
            if (std.mem.eql(u8, cmd, libc_cmd)) {
                exe.root_module.link_libc = true;
                break;
            }
        }

        b.installArtifact(exe);

        const cmd_step = b.step(cmd, b.fmt("Build {s}", .{cmd}));
        cmd_step.dependOn(&b.addInstallArtifact(exe, .{}).step);
    }

    const main_exe = b.addExecutable(.{
        .name = "coreutilz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "coreutilz", .module = mod },
            },
        }),
    });
    main_exe.root_module.link_libc = true;
    b.installArtifact(main_exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(main_exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(install_step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // Module unit tests (embedded tests in source files)
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const main_tests = b.addTest(.{
        .root_module = main_exe.root_module,
    });
    const run_main_tests = b.addRunArtifact(main_tests);

    // Integration tests
    const test_framework = b.addModule("framework", .{
        .root_source_file = b.path("tests/framework.zig"),
        .target = target,
    });
    const integration_test_step = b.step("integration-test", "Run integration tests");

    for (commands) |cmd| {
        const test_file = b.fmt("tests/{s}_test.zig", .{cmd});
        const test_mod = b.createModule(.{
            .root_source_file = b.path(test_file),
            .target = target,
            .optimize = optimize,
        });
        test_mod.addImport("framework", test_framework);

        const test_exe = b.addTest(.{
            .root_module = test_mod,
        });

        const run_test = b.addRunArtifact(test_exe);
        run_test.step.dependOn(install_step);
        integration_test_step.dependOn(&run_test.step);
    }

    // Main test step runs all tests
    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_main_tests.step);
    test_step.dependOn(integration_test_step);
}
