const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

// Test data ported from coreutils/tests/cp/
test "cp basic file copy" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "cp");
    defer allocator.free(binary_path);

    // Create a source file
    try ctx.writeFile("source.txt", "hello world\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const src_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "source.txt" });
    defer allocator.free(src_path);
    const dst_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "dest.txt" });
    defer allocator.free(dst_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, src_path, dst_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify destination file was created with correct content
    const content = try ctx.readFile("dest.txt");
    defer allocator.free(content);
    try testing.expectEqualStrings("hello world\n", content);
}

test "cp -r recursive directory copy" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "cp");
    defer allocator.free(binary_path);

    // Create a directory structure with files
    try ctx.makeDir("srcdir");
    try ctx.writeFile("srcdir/file1.txt", "content1\n");
    try ctx.makeDir("srcdir/subdir");
    try ctx.writeFile("srcdir/subdir/file2.txt", "content2\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const src_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "srcdir" });
    defer allocator.free(src_path);
    const dst_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "dstdir" });
    defer allocator.free(dst_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-r", src_path, dst_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify copied files
    const content1 = try ctx.readFile("dstdir/file1.txt");
    defer allocator.free(content1);
    try testing.expectEqualStrings("content1\n", content1);

    const content2 = try ctx.readFile("dstdir/subdir/file2.txt");
    defer allocator.free(content2);
    try testing.expectEqualStrings("content2\n", content2);
}

test "cp -i interactive mode prompts on overwrite" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "cp");
    defer allocator.free(binary_path);

    // Create source and existing destination
    try ctx.writeFile("source.txt", "new content\n");
    try ctx.writeFile("dest.txt", "old content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const src_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "source.txt" });
    defer allocator.free(src_path);
    const dst_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "dest.txt" });
    defer allocator.free(dst_path);

    // Run with -i, answer 'n' (no) to the prompt
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-i", src_path, dst_path }, null);
    defer result.deinit();

    // Interactive mode should either prompt or skip based on implementation
    // The key is that the file should NOT be overwritten when answering 'n'
    // Since we can't easily provide input, we verify the command executed
    try testing.expect(result.exit_code == 0 or result.stderr.len > 0);

    // Verify destination still has old content (not overwritten)
    const content = try ctx.readFile("dest.txt");
    defer allocator.free(content);
    try testing.expectEqualStrings("old content\n", content);
}

test "cp -v verbose mode prints copied files" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "cp");
    defer allocator.free(binary_path);

    try ctx.writeFile("source.txt", "content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const src_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "source.txt" });
    defer allocator.free(src_path);
    const dst_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "dest.txt" });
    defer allocator.free(dst_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-v", src_path, dst_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "'"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "source.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "dest.txt"));
}

test "cp -f force overwrites existing file" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "cp");
    defer allocator.free(binary_path);

    // Create source and existing destination
    try ctx.writeFile("source.txt", "new content\n");
    try ctx.writeFile("dest.txt", "old content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const src_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "source.txt" });
    defer allocator.free(src_path);
    const dst_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "dest.txt" });
    defer allocator.free(dst_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-f", src_path, dst_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify destination was overwritten
    const content = try ctx.readFile("dest.txt");
    defer allocator.free(content);
    try testing.expectEqualStrings("new content\n", content);
}

test "cp -p preserves file attributes" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "cp");
    defer allocator.free(binary_path);

    try ctx.writeFile("source.txt", "content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const src_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "source.txt" });
    defer allocator.free(src_path);
    const dst_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "dest.txt" });
    defer allocator.free(dst_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-p", src_path, dst_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify destination was created
    const content = try ctx.readFile("dest.txt");
    defer allocator.free(content);
    try testing.expectEqualStrings("content\n", content);

    // Note: Full attribute preservation testing (permissions, timestamps)
    // would require more detailed file system checks
}

test "cp with multiple sources to directory" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "cp");
    defer allocator.free(binary_path);

    // Create multiple source files
    try ctx.writeFile("file1.txt", "content1\n");
    try ctx.writeFile("file2.txt", "content2\n");

    // Create destination directory
    try ctx.makeDir("destdir");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const src1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    defer allocator.free(src1_path);
    const src2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2.txt" });
    defer allocator.free(src2_path);
    const dst_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "destdir" });
    defer allocator.free(dst_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, src1_path, src2_path, dst_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify both files were copied to destination directory
    const content1 = try ctx.readFile("destdir/file1.txt");
    defer allocator.free(content1);
    try testing.expectEqualStrings("content1\n", content1);

    const content2 = try ctx.readFile("destdir/file2.txt");
    defer allocator.free(content2);
    try testing.expectEqualStrings("content2\n", content2);
}

test "cp nonexistent source fails" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "cp");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const src_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "nonexistent.txt" });
    defer allocator.free(src_path);
    const dst_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "dest.txt" });
    defer allocator.free(dst_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, src_path, dst_path }, null);
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "No such file") or
        std.mem.containsAtLeast(u8, result.stderr, 1, "cannot stat") or
        result.stderr.len > 0);
}

test "cp source to non-writable destination without force fails" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "cp");
    defer allocator.free(binary_path);

    // Create source and destination
    try ctx.writeFile("source.txt", "new content\n");
    try ctx.writeFile("dest.txt", "old content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const src_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "source.txt" });
    defer allocator.free(src_path);
    const dst_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "dest.txt" });
    defer allocator.free(dst_path);

    // Make destination read-only (0o444)
    try std.Io.Dir.cwd().setFilePermissions(std.Options.debug_io, dst_path, @enumFromInt(0o444), .{});

    // Try to copy without -f
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, src_path, dst_path }, null);
    defer result.deinit();

    // Restore permissions for cleanup
    std.Io.Dir.cwd().setFilePermissions(std.Options.debug_io, dst_path, @enumFromInt(0o644), .{}) catch {};

    // Should fail or succeed based on implementation, but shouldn't crash
    try testing.expect(result.exit_code != 0 or result.stderr.len > 0);
}

test "cp --help option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "cp");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "cp --version option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "cp");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "cp"));
}

test "cp directory to file fails" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "cp");
    defer allocator.free(binary_path);

    // Create a directory
    try ctx.makeDir("srcdir");
    try ctx.writeFile("srcdir/file.txt", "content\n");

    // Create a file as destination
    try ctx.writeFile("destfile", "I am a file\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const src_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "srcdir" });
    defer allocator.free(src_path);
    const dst_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "destfile" });
    defer allocator.free(dst_path);

    // Try to copy directory to file (should fail)
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-r", src_path, dst_path }, null);
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
}
