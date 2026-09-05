const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;
const isRoot = framework.isRoot;

test "rm removes single file" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rm");
    defer allocator.free(binary_path);

    try ctx.writeFile("file.txt", "content");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "file.txt" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(!ctx.pathExists("file.txt"));
}

test "rm nonexistent file without -f exits 1" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rm");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "nonexistent.txt" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "rm -f ignores nonexistent file exits 0" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rm");
    defer allocator.free(binary_path);

    try ctx.makeDir("d");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-f", "d/no-such-file" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "rm directory without -r exits 1 with diagnostic" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rm");
    defer allocator.free(binary_path);

    try ctx.makeDir("d");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "d" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "Is a directory") != null);
}

test "rm -r removes directory recursively" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rm");
    defer allocator.free(binary_path);

    try ctx.makeDir("a");
    try ctx.makeDir("a/sub");
    try ctx.writeFile("a/file.txt", "data");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-r", "a" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(!ctx.pathExists("a"));
}

test "rm --verbose -r prints removed items" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rm");
    defer allocator.free(binary_path);

    try ctx.makeDir("a");
    try ctx.makeDir("a/a");
    try ctx.writeFile("b", "data");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--verbose", "-r", "a", "b" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "removed directory 'a/a'") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "removed directory 'a'") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "removed 'b'") != null);
}

test "rm --dir --verbose removes empty dir and file" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rm");
    defer allocator.free(binary_path);

    try ctx.makeDir("a");
    try ctx.writeFile("b", "data");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--verbose", "--dir", "a", "b" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "removed directory 'a'") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "removed 'b'") != null);
    try testing.expect(!ctx.pathExists("a"));
    try testing.expect(!ctx.pathExists("b"));
}

test "rm -d removes empty directory" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rm");
    defer allocator.free(binary_path);

    try ctx.makeDir("emptydir");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-d", "emptydir" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(!ctx.pathExists("emptydir"));
}

test "rm dangling symlink removed without prompt" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rm");
    defer allocator.free(binary_path);

    try ctx.makeSymlink("no-file", "dangle");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "dangle" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(!ctx.pathExists("dangle"));
}

test "rm -rf partial failure due to permissions" {
    if (isRoot()) return error.SkipZigTest;

    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rm");
    defer allocator.free(binary_path);

    try ctx.makeDir("b");
    try ctx.makeDir("b/a");
    try ctx.makeDir("b/a/p");
    try ctx.makeDir("b/c");
    try ctx.makeDir("b/d");

    const a_path = try ctx.tmpPath("b/a");
    defer allocator.free(a_path);
    try std.Io.Dir.cwd().setFilePermissions(std.Options.debug_io, a_path, @enumFromInt(0o555), .{});

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-rf", "b" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expect(ctx.pathExists("b/a/p"));
    try testing.expect(!ctx.pathExists("b/c"));
    try testing.expect(!ctx.pathExists("b/d"));

    std.Io.Dir.cwd().setFilePermissions(std.Options.debug_io, a_path, @enumFromInt(0o755), .{}) catch {};
}

test "rm --help exits 0" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rm");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "rm --version exits 0" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "rm");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}
