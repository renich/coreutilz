const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "rmdir removes empty directory" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rmdir");
    defer allocator.free(binary_path);

    try ctx.makeDir("emptydir");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "emptydir" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(!ctx.pathExists("emptydir"));
}

test "rmdir fails on non-empty directory" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rmdir");
    defer allocator.free(binary_path);

    try ctx.makeDir("nonempty");
    try ctx.writeFile("nonempty/file.txt", "data");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "nonempty" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "rmdir -p removes parent directories" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rmdir");
    defer allocator.free(binary_path);

    try ctx.makeDir("parent");
    try ctx.makeDir("parent/child");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-p", "parent/child" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(!ctx.pathExists("parent/child"));
    try testing.expect(!ctx.pathExists("parent"));
}

test "rmdir -p with trailing slash works" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rmdir");
    defer allocator.free(binary_path);

    try ctx.makeDir("dir");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-p", "dir/" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(!ctx.pathExists("dir"));
}

test "rmdir -v prints removed directory" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rmdir");
    defer allocator.free(binary_path);

    try ctx.makeDir("verbose");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-v", "verbose" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "verbose") != null);
}

test "rmdir --ignore-fail-on-non-empty succeeds on non-empty dir" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rmdir");
    defer allocator.free(binary_path);

    try ctx.makeDir("nonempty");
    try ctx.writeFile("nonempty/file.txt", "data");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--ignore-fail-on-non-empty", "nonempty" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "rmdir -p --ignore-fail-on-non-empty removes leaf but not blocked parent" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rmdir");
    defer allocator.free(binary_path);

    try ctx.makeDir("a");
    try ctx.makeDir("a/b");
    try ctx.makeDir("a/b/c");
    try ctx.makeDir("a/x");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-p", "--ignore-fail-on-non-empty", "a/b/c" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(!ctx.pathExists("a/b"));
    try testing.expect(!ctx.pathExists("a/b/c"));
    try testing.expect(ctx.pathExists("a/x"));
}

test "rmdir nonexistent directory exits 1" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rmdir");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "nonexistent" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "rmdir on symlink to directory exits 1" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rmdir");
    defer allocator.free(binary_path);

    try ctx.makeDir("dir");
    try ctx.makeSymlink("dir", "sl");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "sl" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "rmdir multiple empty directories" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rmdir");
    defer allocator.free(binary_path);

    try ctx.makeDir("dir1");
    try ctx.makeDir("dir2");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "dir1", "dir2" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(!ctx.pathExists("dir1"));
    try testing.expect(!ctx.pathExists("dir2"));
}

test "rmdir --help exits 0" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rmdir");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "rmdir --version exits 0" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rmdir");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}
