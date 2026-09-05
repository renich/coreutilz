const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "ls basic directory listing" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    // Create test files
    try ctx.writeFile("file1.txt", "content1\n");
    try ctx.writeFile("file2.txt", "content2\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "file1.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "file2.txt"));
}

test "ls -l option (long format)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "hello\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    // Long format should contain file permissions
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "-"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "test.txt"));
}

test "ls -a option (show hidden files)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("regular.txt", "content\n");
    try ctx.writeFile(".hidden", "hidden content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-a", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "regular.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, ".hidden"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "."));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, ".."));
}

test "ls -la option (combined long format and all files)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("regular.txt", "content\n");
    try ctx.writeFile(".hidden", "hidden content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-la", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should show hidden files in long format
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, ".hidden"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "."));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, ".."));
}

test "ls -R option (recursive)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("file.txt", "content\n");
    const tmp_path_for_mkdir = try ctx.tmpPath(".");
    defer std.testing.allocator.free(tmp_path_for_mkdir);
    const subdir_path = try std.fs.path.join(std.testing.allocator, &[_][]const u8{ tmp_path_for_mkdir, "subdir" });
    defer std.testing.allocator.free(subdir_path);
    try std.fs.cwd().makeDir(subdir_path);
    const nested_path = try std.fs.path.join(std.testing.allocator, &[_][]const u8{ tmp_path_for_mkdir, "subdir", "nested.txt" });
    defer std.testing.allocator.free(nested_path);
    const nested_file = try std.fs.cwd().createFile(nested_path, .{});
    nested_file.close();
    try ctx.writeFile("subdir/nested.txt", "nested content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-R", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "file.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "subdir"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "nested.txt"));
}

test "ls -t option (sort by time)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("old_file.txt", "old content\n");

    // Small delay to ensure different timestamps (10ms)
    std.Thread.sleep(10_000_000);

    try ctx.writeFile("new_file.txt", "new content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-t", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "old_file.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "new_file.txt"));
}

test "ls -S option (sort by size)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("small.txt", "x\n");
    try ctx.writeFile("large.txt", "this is a much larger file with more content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-S", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "small.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "large.txt"));
}

test "ls -r option (reverse order)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("aaa.txt", "aaa\n");
    try ctx.writeFile("zzz.txt", "zzz\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-r", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "aaa.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "zzz.txt"));
}

test "ls -1 option (one per line)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("file1.txt", "content1\n");
    try ctx.writeFile("file2.txt", "content2\n");
    try ctx.writeFile("file3.txt", "content3\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-1", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "file1.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "file2.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "file3.txt"));
    // Each file should be on its own line
    const newline_count = std.mem.count(u8, result.stdout, "\n");
    try testing.expect(newline_count >= 3);
}

test "ls with specific files" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("target.txt", "target content\n");
    try ctx.writeFile("other.txt", "other content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "target.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "target.txt"));
    try testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, "other.txt"));
}

test "ls nonexistent directory returns error" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const nonexistent = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "nonexistent" });
    defer allocator.free(nonexistent);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, nonexistent }, null);
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
}

test "ls --help option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "ls --version option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "ls"));
}
