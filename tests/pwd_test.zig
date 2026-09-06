const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "pwd basic output is absolute path" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "pwd");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{binary_path}, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(result.stdout.len > 0);
    try testing.expect(std.mem.startsWith(u8, result.stdout, "/"));
}

test "pwd output ends with newline" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "pwd");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{binary_path}, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.endsWith(u8, result.stdout, "\n"));
}

test "pwd -P physical path is absolute" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "pwd");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-P" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.startsWith(u8, result.stdout, "/"));
}

test "pwd -L logical path is absolute" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "pwd");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-L" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.startsWith(u8, result.stdout, "/"));
}

test "pwd -P resolves symlinks" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "pwd");
    defer allocator.free(binary_path);

    const tmp = try ctx.tmpPath(".");
    defer allocator.free(tmp);

    try ctx.makeDir("realdir");
    const real_dir = try std.fs.path.join(allocator, &[_][]const u8{ tmp, "realdir" });
    defer allocator.free(real_dir);
    const link_dir = try std.fs.path.join(allocator, &[_][]const u8{ tmp, "linkdir" });
    defer allocator.free(link_dir);
    try ctx.makeSymlink("realdir", "linkdir");

    var env = framework.EnvMap.init(allocator);
    defer env.deinit();

    var result = try ctx.runCommandInDir(&[_][]const u8{ binary_path, "-P" }, null, link_dir, &env);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const output = std.mem.trimEnd(u8, result.stdout, "\n");
    try testing.expectEqualStrings(real_dir, output);
}

test "pwd invalid option exits 2" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "pwd");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-Z" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "pwd --help exits 0" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "pwd");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(result.stdout.len > 0);
}

test "pwd --version exits 0" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "pwd");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(result.stdout.len > 0);
}
