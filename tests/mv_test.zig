const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

// Test data ported from coreutils/tests/mv/
test "mv basic file rename" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mv");
    defer allocator.free(binary_path);

    // Create source file
    try ctx.writeFile("source.txt", "hello world\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const source_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "source.txt" });
    defer allocator.free(source_path);
    const dest_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "dest.txt" });
    defer allocator.free(dest_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, source_path, dest_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify file was moved
    const exists = ctx.compareContent("hello world\n", "dest.txt");
    try testing.expect(try exists);
}

test "mv directory to new name" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mv");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const source_dir = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "olddir" });
    defer allocator.free(source_dir);
    const dest_dir = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "newdir" });
    defer allocator.free(dest_dir);

    // Create source directory with file
    try ctx.makeDir("olddir");
    try ctx.writeFile("olddir/file.txt", "");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, source_dir, dest_dir }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "mv -v prints moved files" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mv");
    defer allocator.free(binary_path);

    try ctx.writeFile("verbose.txt", "content");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const source_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "verbose.txt" });
    defer allocator.free(source_path);
    const dest_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "moved.txt" });
    defer allocator.free(dest_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-v", source_path, dest_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "verbose.txt"));
}

test "mv -f forces overwrite" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mv");
    defer allocator.free(binary_path);

    try ctx.writeFile("source.txt", "new content");
    try ctx.writeFile("dest.txt", "old content");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const source_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "source.txt" });
    defer allocator.free(source_path);
    const dest_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "dest.txt" });
    defer allocator.free(dest_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-f", source_path, dest_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify destination has new content
    const matches = ctx.compareContent("new content", "dest.txt");
    try testing.expect(try matches);
}

test "mv multiple files to directory" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mv");
    defer allocator.free(binary_path);

    try ctx.writeFile("file1.txt", "content1");
    try ctx.writeFile("file2.txt", "content2");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    defer allocator.free(file1_path);
    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2.txt" });
    defer allocator.free(file2_path);
    const dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "targetdir" });
    defer allocator.free(dir_path);

    // Create target directory
    try ctx.makeDir("targetdir");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, file1_path, file2_path, dir_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "mv nonexistent source fails" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mv");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const source_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "nonexistent.txt" });
    defer allocator.free(source_path);
    const dest_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "dest.txt" });
    defer allocator.free(dest_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, source_path, dest_path }, null);
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
}

test "mv to nonexistent directory fails" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mv");
    defer allocator.free(binary_path);

    try ctx.writeFile("file.txt", "content");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const source_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file.txt" });
    defer allocator.free(source_path);
    const dest_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "nonexistent", "dest.txt" });
    defer allocator.free(dest_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, source_path, dest_path }, null);
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
}

test "mv fails without destination" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mv");
    defer allocator.free(binary_path);

    try ctx.writeFile("file.txt", "content");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const source_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file.txt" });
    defer allocator.free(source_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, source_path }, null);
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
}

test "mv -i interactive mode" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mv");
    defer allocator.free(binary_path);

    try ctx.writeFile("source.txt", "new content");
    try ctx.writeFile("dest.txt", "old content");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const source_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "source.txt" });
    defer allocator.free(source_path);
    const dest_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "dest.txt" });
    defer allocator.free(dest_path);

    // Run with -i flag - should prompt (we can't interact, but we can verify it doesn't error immediately)
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-i", source_path, dest_path }, null);
    defer result.deinit();

    // -i with conflicting file should either prompt or succeed depending on implementation
    // We'll just verify it doesn't crash
    try testing.expect(result.exit_code == 0 or result.exit_code == 1);
}

test "mv --help option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mv");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "mv --version option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mv");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "mv"));
}
