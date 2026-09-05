const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

// Test data ported from coreutils/tests/touch/
test "touch creates new file" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "newfile.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify file exists
    const file = std.fs.cwd().openFile(file_path, .{}) catch {
        try testing.expect(false);
        return;
    };
    defer file.close();
}

test "touch updates timestamp of existing file" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    // Create an existing file
    try ctx.writeFile("existing.txt", "content");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "existing.txt" });
    defer allocator.free(file_path);

    // Get original modification time
    const original_stat = try std.fs.cwd().statFile(file_path);
    const original_mtime = original_stat.mtime;

    // Small delay to ensure time change is detectable
    std.Thread.sleep(10_000_000); // 10ms in nanoseconds

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify timestamp was updated
    const new_stat = try std.fs.cwd().statFile(file_path);
    try testing.expect(new_stat.mtime > original_mtime);
}

test "touch -a updates only access time" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    try ctx.writeFile("access.txt", "content");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "access.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-a", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify file still exists and is accessible
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();
}

test "touch -m updates only modification time" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    try ctx.writeFile("modify.txt", "content");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "modify.txt" });
    defer allocator.free(file_path);

    // Get original modification time
    const original_stat = try std.fs.cwd().statFile(file_path);
    const original_mtime = original_stat.mtime;

    // Small delay to ensure time change is detectable
    std.Thread.sleep(10_000_000); // 10ms in nanoseconds

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-m", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify modification time was updated
    const new_stat = try std.fs.cwd().statFile(file_path);
    try testing.expect(new_stat.mtime > original_mtime);
}

test "touch -t sets specific time" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "timed.txt" });
    defer allocator.free(file_path);

    // Use a specific timestamp: 202401011200 (Jan 1, 2024 12:00)
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-t", "202401011200", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify file exists
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();
}

test "touch -d sets time from date string" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "dated.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-d", "2024-01-01 12:00:00", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify file exists
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();
}

test "touch -r uses reference file timestamp" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    // Create reference file
    try ctx.writeFile("reference.txt", "reference content");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const ref_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "reference.txt" });
    defer allocator.free(ref_path);
    const target_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "target.txt" });
    defer allocator.free(target_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-r", ref_path, target_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify target file exists
    const file = try std.fs.cwd().openFile(target_path, .{});
    defer file.close();
}

test "touch -c does not create file" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "nocreate.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-c", file_path }, null);
    defer result.deinit();

    // Should succeed but not create the file
    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify file does NOT exist
    const file = std.fs.cwd().openFile(file_path, .{}) catch {
        try testing.expect(true);
        return;
    };
    defer file.close();
    try testing.expect(false); // File should not exist
}

test "touch -c updates existing file" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    // Create existing file
    try ctx.writeFile("existing.txt", "content");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "existing.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-c", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify file still exists
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();
}

test "touch multiple files" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file1 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    defer allocator.free(file1);
    const file2 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2.txt" });
    defer allocator.free(file2);
    const file3 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file3.txt" });
    defer allocator.free(file3);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, file1, file2, file3 }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify all files exist
    const f1 = try std.fs.cwd().openFile(file1, .{});
    defer f1.close();
    const f2 = try std.fs.cwd().openFile(file2, .{});
    defer f2.close();
    const f3 = try std.fs.cwd().openFile(file3, .{});
    defer f3.close();
}

test "touch --help option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "touch --version option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "touch"));
}
