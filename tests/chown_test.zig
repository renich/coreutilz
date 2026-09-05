const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "chown with user:group" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chown");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "root:root", file_path }, null);
    defer result.deinit();

    // Note: chown may fail if not running as root
    // Exit code 0 means success, non-zero means permission denied
    if (result.exit_code == 0) {
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "") or result.stderr.len == 0);
    } else {
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "Operation not permitted") or
            std.mem.containsAtLeast(u8, result.stderr, 1, "Permission denied"));
    }
}

test "chown with just user" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chown");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "root", file_path }, null);
    defer result.deinit();

    if (result.exit_code == 0) {
        try testing.expect(result.stderr.len == 0);
    } else {
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "Operation not permitted") or
            std.mem.containsAtLeast(u8, result.stderr, 1, "Permission denied"));
    }
}

test "chown with :group" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chown");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, ":root", file_path }, null);
    defer result.deinit();

    if (result.exit_code == 0) {
        try testing.expect(result.stderr.len == 0);
    } else {
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "Operation not permitted") or
            std.mem.containsAtLeast(u8, result.stderr, 1, "Permission denied"));
    }
}

test "chown -R recursive" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chown");
    defer allocator.free(binary_path);

    try ctx.tmp_dir.dir.makePath("testdir/subdir");
    try ctx.writeFile("testdir/file1.txt", "content1\n");
    try ctx.writeFile("testdir/subdir/file2.txt", "content2\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "testdir" });
    defer allocator.free(dir_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-R", "root:root", dir_path }, null);
    defer result.deinit();

    // Recursive chown may fail if not running as root
    if (result.exit_code == 0) {
        try testing.expect(result.stderr.len == 0);
    } else {
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "Operation not permitted") or
            std.mem.containsAtLeast(u8, result.stderr, 1, "Permission denied"));
    }
}

test "chown --reference file" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chown");
    defer allocator.free(binary_path);

    try ctx.writeFile("reference.txt", "reference content\n");
    try ctx.writeFile("target.txt", "target content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const ref_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "reference.txt" });
    defer allocator.free(ref_path);
    const target_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "target.txt" });
    defer allocator.free(target_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--reference", ref_path, target_path }, null);
    defer result.deinit();

    if (result.exit_code == 0) {
        try testing.expect(result.stderr.len == 0);
    } else {
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "Operation not permitted") or
            std.mem.containsAtLeast(u8, result.stderr, 1, "Permission denied"));
    }
}

test "chown nonexistent file returns error" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chown");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "nonexistent.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "root:root", file_path }, null);
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "No such file") or
        std.mem.containsAtLeast(u8, result.stderr, 1, "cannot access"));
}

test "chown invalid user returns error" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chown");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "nonexistentuser12345:", file_path }, null);
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "invalid user") or
        std.mem.containsAtLeast(u8, result.stderr, 1, "unknown user") or
        std.mem.containsAtLeast(u8, result.stderr, 1, "no such user"));
}

test "chown --help option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chown");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "chown --version option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chown");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "chown"));
}
