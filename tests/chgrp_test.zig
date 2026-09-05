const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "chgrp with group name" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chgrp");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "root", file_path }, null);
    defer result.deinit();

    // chgrp may fail if not running as root
    if (result.exit_code == 0) {
        try testing.expect(result.stderr.len == 0);
    } else {
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "Operation not permitted") or
            std.mem.containsAtLeast(u8, result.stderr, 1, "Permission denied"));
    }
}

test "chgrp with numeric GID" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chgrp");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "0", file_path }, null);
    defer result.deinit();

    if (result.exit_code == 0) {
        try testing.expect(result.stderr.len == 0);
    } else {
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "Operation not permitted") or
            std.mem.containsAtLeast(u8, result.stderr, 1, "Permission denied"));
    }
}

test "chgrp -R recursive" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chgrp");
    defer allocator.free(binary_path);

    try ctx.tmp_dir.dir.makePath("testdir/subdir");
    try ctx.writeFile("testdir/file1.txt", "content1\n");
    try ctx.writeFile("testdir/subdir/file2.txt", "content2\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "testdir" });
    defer allocator.free(dir_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-R", "root", dir_path }, null);
    defer result.deinit();

    // Recursive chgrp may fail if not running as root
    if (result.exit_code == 0) {
        try testing.expect(result.stderr.len == 0);
    } else {
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "Operation not permitted") or
            std.mem.containsAtLeast(u8, result.stderr, 1, "Permission denied"));
    }
}

test "chgrp --reference file" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chgrp");
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

test "chgrp on multiple files" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chgrp");
    defer allocator.free(binary_path);

    try ctx.writeFile("file1.txt", "content1\n");
    try ctx.writeFile("file2.txt", "content2\n");
    try ctx.writeFile("file3.txt", "content3\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    defer allocator.free(file1_path);
    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2.txt" });
    defer allocator.free(file2_path);
    const file3_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file3.txt" });
    defer allocator.free(file3_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "root", file1_path, file2_path, file3_path }, null);
    defer result.deinit();

    if (result.exit_code == 0) {
        try testing.expect(result.stderr.len == 0);
    } else {
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "Operation not permitted") or
            std.mem.containsAtLeast(u8, result.stderr, 1, "Permission denied"));
    }
}

test "chgrp nonexistent file returns error" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chgrp");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "nonexistent.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "root", file_path }, null);
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "No such file") or
        std.mem.containsAtLeast(u8, result.stderr, 1, "cannot access"));
}

test "chgrp invalid group returns error" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chgrp");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "nonexistentgroup12345", file_path }, null);
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "invalid group") or
        std.mem.containsAtLeast(u8, result.stderr, 1, "unknown group") or
        std.mem.containsAtLeast(u8, result.stderr, 1, "no such group"));
}

test "chgrp --help option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chgrp");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "chgrp --version option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chgrp");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "chgrp"));
}
