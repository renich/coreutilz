const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "printenv no args outputs environment" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "printenv");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{binary_path}, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(result.stdout.len > 0);
}

test "printenv single variable prints its value" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "printenv");
    defer allocator.free(binary_path);

    const cwd = try ctx.tmpPath(".");
    defer allocator.free(cwd);

    var env = framework.EnvMap.init(allocator);
    defer env.deinit();
    try env.put("ENV_TEST", "a");

    var result = try ctx.runCommandInDir(
        &[_][]const u8{ binary_path, "ENV_TEST" },
        null,
        cwd,
        &env,
    );
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("a\n", result.stdout);
}

test "printenv missing variable exits 1 with no output" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "printenv");
    defer allocator.free(binary_path);

    const cwd = try ctx.tmpPath(".");
    defer allocator.free(cwd);

    var env = framework.EnvMap.init(allocator);
    defer env.deinit();

    var result = try ctx.runCommandInDir(
        &[_][]const u8{ binary_path, "ENV_TEST" },
        null,
        cwd,
        &env,
    );
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expectEqualStrings("", result.stdout);
}

test "printenv multiple variables order follows command line" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "printenv");
    defer allocator.free(binary_path);

    const cwd = try ctx.tmpPath(".");
    defer allocator.free(cwd);

    var env = framework.EnvMap.init(allocator);
    defer env.deinit();
    try env.put("ENV_TEST1", "a");
    try env.put("ENV_TEST2", "b");

    var result = try ctx.runCommandInDir(
        &[_][]const u8{ binary_path, "ENV_TEST2", "ENV_TEST1", "ENV_TEST2" },
        null,
        cwd,
        &env,
    );
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("b\na\nb\n", result.stdout);
}

test "printenv missing var exits 1 but still prints found vars" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "printenv");
    defer allocator.free(binary_path);

    const cwd = try ctx.tmpPath(".");
    defer allocator.free(cwd);

    var env = framework.EnvMap.init(allocator);
    defer env.deinit();
    try env.put("ENV_TEST1", "a");

    var result = try ctx.runCommandInDir(
        &[_][]const u8{ binary_path, "ENV_TEST2", "ENV_TEST1" },
        null,
        cwd,
        &env,
    );
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expectEqualStrings("a\n", result.stdout);
}

test "printenv non-standard var name with leading dash" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "printenv");
    defer allocator.free(binary_path);

    const cwd = try ctx.tmpPath(".");
    defer allocator.free(cwd);

    var env = framework.EnvMap.init(allocator);
    defer env.deinit();
    try env.put("-a", "b");

    var result = try ctx.runCommandInDir(
        &[_][]const u8{ binary_path, "--", "-a" },
        null,
        cwd,
        &env,
    );
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("b\n", result.stdout);
}

test "printenv --help exits 0" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "printenv");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "printenv --version exits 0" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "printenv");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}
