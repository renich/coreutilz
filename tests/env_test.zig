const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "env no-args prints environment" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "env");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{binary_path}, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(result.stdout.len > 0);
}

test "env -i prints nothing" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "env");
    defer allocator.free(binary_path);

    var env = framework.EnvMap.init(allocator);
    defer env.deinit();
    try env.put("SOME_VAR", "x");

    const tmp = try ctx.tmpPath(".");
    defer allocator.free(tmp);

    var result = try ctx.runCommandInDir(&[_][]const u8{ binary_path, "-i" }, null, tmp, &env);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("", result.stdout);
}

test "env -i with assignment prints only that var" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "env");
    defer allocator.free(binary_path);

    var env = framework.EnvMap.init(allocator);
    defer env.deinit();
    try env.put("OUTSIDE", "ignored");

    const tmp = try ctx.tmpPath(".");
    defer allocator.free(tmp);

    var result = try ctx.runCommandInDir(&[_][]const u8{ binary_path, "-i", "MYVAR=hello" }, null, tmp, &env);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("MYVAR=hello\n", result.stdout);
}

test "env ignores-environment alias -" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "env");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-", "ONLY=one" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("ONLY=one\n", result.stdout);
}

test "env -u unsets variable" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "env");
    defer allocator.free(binary_path);

    var env = framework.EnvMap.init(allocator);
    defer env.deinit();
    try env.put("RM_ME", "gone");

    const tmp = try ctx.tmpPath(".");
    defer allocator.free(tmp);

    var result = try ctx.runCommandInDir(&[_][]const u8{ binary_path, "-i", "RM_ME=present", "-u", "RM_ME" }, null, tmp, &env);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("", result.stdout);
}

test "env unknown option exits 125" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "env");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--unknown-option" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 125), result.exit_code);
}

test "env --help exits 0" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "env");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(result.stdout.len > 0);
}

test "env --version exits 0" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "env");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(result.stdout.len > 0);
}
