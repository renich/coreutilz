const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "comm basic comparison" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "comm");
    defer allocator.free(binary_path);

    try ctx.writeFile("file1", "a\nb\nc\n");
    try ctx.writeFile("file2", "b\nc\nd\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const f1 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1" });
    defer allocator.free(f1);
    const f2 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2" });
    defer allocator.free(f2);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, f1, f2 }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("a\n\t\tb\n\t\tc\n\td\n", result.stdout);
}

test "comm suppress columns" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "comm");
    defer allocator.free(binary_path);

    try ctx.writeFile("file1", "a\nb\nc\n");
    try ctx.writeFile("file2", "b\nc\nd\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const f1 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1" });
    defer allocator.free(f1);
    const f2 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2" });
    defer allocator.free(f2);

    // Suppress column 1 (only in file 1)
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-1", f1, f2 }, null);
        defer result.deinit();
        try testing.expectEqualStrings("\tb\n\tc\nd\n", result.stdout);
    }

    // Suppress column 2 (only in file 2)
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-2", f1, f2 }, null);
        defer result.deinit();
        try testing.expectEqualStrings("a\n\tb\n\tc\n", result.stdout);
    }

    // Suppress column 3 (common)
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-3", f1, f2 }, null);
        defer result.deinit();
        try testing.expectEqualStrings("a\n\td\n", result.stdout);
    }
}

test "comm output delimiter" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "comm");
    defer allocator.free(binary_path);

    try ctx.writeFile("file1", "a\nb\n");
    try ctx.writeFile("file2", "b\nc\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const f1 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1" });
    defer allocator.free(f1);
    const f2 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2" });
    defer allocator.free(f2);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--output-delimiter=,", f1, f2 }, null);
    defer result.deinit();

    try testing.expectEqualStrings("a\n,,b\n,c\n", result.stdout);
}

test "comm check-order" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "comm");
    defer allocator.free(binary_path);

    try ctx.writeFile("file1", "b\na\n");
    try ctx.writeFile("file2", "c\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const f1 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1" });
    defer allocator.free(f1);
    const f2 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2" });
    defer allocator.free(f2);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--check-order", f1, f2 }, null);
    defer result.deinit();

    // Should return non-zero exit code if not sorted
    try testing.expect(result.exit_code != 0);
}

test "comm nocheck-order" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "comm");
    defer allocator.free(binary_path);

    try ctx.writeFile("file1", "b\na\n");
    try ctx.writeFile("file2", "c\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const f1 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1" });
    defer allocator.free(f1);
    const f2 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2" });
    defer allocator.free(f2);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--nocheck-order", f1, f2 }, null);
    defer result.deinit();

    // Should return zero exit code even if not sorted when --nocheck-order is used
    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "comm --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "comm");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "comm --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "comm");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "comm"));
}
