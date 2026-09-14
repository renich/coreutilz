const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

// [FUNC-COMM-001] Three-Column Stream Comparison
test "comm [FUNC-COMM-001] three-column stream comparison" {
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

// [FUNC-COMM-002] Column Suppression Modes
test "comm [FUNC-COMM-002a] -1 suppress column 1" {
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

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-1", f1, f2 }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("\tb\n\tc\nd\n", result.stdout);
}

test "comm [FUNC-COMM-002b] -2 suppress column 2" {
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

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-2", f1, f2 }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("a\n\tb\n\tc\n", result.stdout);
}

test "comm [FUNC-COMM-002c] -3 suppress column 3" {
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

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-3", f1, f2 }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("a\n\td\n", result.stdout);
}

test "comm [FUNC-COMM-002] -12 suppress columns 1 and 2" {
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

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-12", f1, f2 }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("b\nc\n", result.stdout);
}

// [FUNC-COMM-003a] Custom Output Delimiter
test "comm [FUNC-COMM-003a] --output-delimiter custom delimiter" {
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

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("a\n,,b\n,c\n", result.stdout);
}

// [FUNC-COMM-004] Order Verification
test "comm [FUNC-COMM-004a] --check-order fails on unsorted input" {
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

    try testing.expect(result.exit_code != 0);
}

test "comm [FUNC-COMM-004b] --nocheck-order ignores unsorted input" {
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

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "comm [FUNC-COMM-004] --help" {
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

test "comm [FUNC-COMM-004] --version" {
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
