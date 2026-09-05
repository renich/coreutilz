const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "mkdir creates directory" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mkdir");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "newdir" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(ctx.pathExists("newdir"));
}

test "mkdir -p creates nested parent directories" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mkdir");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-p", "foo/a/b/c/d" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(ctx.pathExists("foo/a/b/c/d"));
}

test "mkdir --parents long form creates nested dirs" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mkdir");
    defer allocator.free(binary_path);

    const cwd = try ctx.tmpPath(".");
    defer allocator.free(cwd);
    const abs = try std.fs.path.join(allocator, &.{ cwd, "t" });
    defer allocator.free(abs);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--parents", abs }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(ctx.pathExists("t"));
}

test "mkdir fails if directory already exists" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mkdir");
    defer allocator.free(binary_path);

    try ctx.makeDir("existing");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "existing" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "mkdir -p succeeds if directory already exists" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mkdir");
    defer allocator.free(binary_path);

    try ctx.makeDir("existing");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-p", "existing" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "mkdir -pv prints created directory message for each" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mkdir");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-pv", "foo/a/b/c/d" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "mkdir: created directory 'foo'") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "mkdir: created directory 'foo/a'") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "mkdir: created directory 'foo/a/b'") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "mkdir: created directory 'foo/a/b/c'") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "mkdir: created directory 'foo/a/b/c/d'") != null);
}

test "mkdir -v prints created directory message" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mkdir");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-v", "verbose" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "created directory") != null);
}

test "mkdir with trailing slash creates directory" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mkdir");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "d2/" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(ctx.pathExists("d2"));
}

test "mkdir -p with trailing slash works" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mkdir");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-p", "dir/" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(ctx.pathExists("dir"));
}

test "mkdir -m sets permissions" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mkdir");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-m", "700", "withmode" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(ctx.pathExists("withmode"));
}

test "mkdir multiple directories" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mkdir");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "dir1", "dir2" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(ctx.pathExists("dir1"));
    try testing.expect(ctx.pathExists("dir2"));
}

test "mkdir --help exits 0" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mkdir");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "mkdir --version exits 0" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mkdir");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "mkdir -p with trailing dot and dotdot" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mkdir");
    defer allocator.free(binary_path);

    var r1 = try ctx.runCommand(&[_][]const u8{ binary_path, "-p", "d1/." }, null);
    defer r1.deinit();
    try testing.expectEqual(@as(u8, 0), r1.exit_code);
    try testing.expect(ctx.pathExists("d1"));

    var r2 = try ctx.runCommand(&[_][]const u8{ binary_path, "-p", "d2/.." }, null);
    defer r2.deinit();
    try testing.expectEqual(@as(u8, 0), r2.exit_code);
    try testing.expect(ctx.pathExists("d2"));
}
