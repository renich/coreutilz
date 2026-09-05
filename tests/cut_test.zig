const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "cut -c (characters)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "cut");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "abcdef\n123456\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    // Cut characters 1-3
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-c", "1-3", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("abc\n123\n", result.stdout);
}

test "cut -f (fields) and -d (delimiter)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "cut");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "apple:banana:cherry\n1:2:3\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    // Cut fields 1 and 3 with ":" delimiter
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-d", ":", "-f", "1,3", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("apple:cherry\n1:3\n", result.stdout);
}

test "cut --complement" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "cut");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "apple:banana:cherry\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    // Complement of field 2 is fields 1 and 3
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-d", ":", "-f", "2", "--complement", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("apple:cherry\n", result.stdout);
}

test "cut -s (suppress)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "cut");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "apple:banana\nno_delimiter\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    // With -s, lines without delimiter are suppressed
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-d", ":", "-f", "1", "-s", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("apple\n", result.stdout);
}

test "cut multiple files" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "cut");
    defer allocator.free(binary_path);

    try ctx.writeFile("file1.txt", "abc\n");
    try ctx.writeFile("file2.txt", "123\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    defer allocator.free(file1_path);
    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2.txt" });
    defer allocator.free(file2_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-c", "1", file1_path, file2_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("a\n1\n", result.stdout);
}

test "cut invalid range error" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "cut");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-c", "b-a" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "cut invalid field error" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "cut");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-f", "0" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "cut --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "cut");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "cut --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "cut");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "cut"));
}
