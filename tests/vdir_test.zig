const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

// [FUNC-LS-003] Detailed Long Listing (vdir default format)
test "vdir [FUNC-LS-003] default long listing format without -l" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "vdir");
    defer allocator.free(binary_path);

    try ctx.writeFile("file1.txt", "content1\n");
    try ctx.writeFile("file2.txt", "content2\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    // vdir default is long listing: contains permission bit, total line, and filenames
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "-"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "file1.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "file2.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "total"));
}

test "vdir [FUNC-LS-002a] -a displays hidden files in long format" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "vdir");
    defer allocator.free(binary_path);

    try ctx.writeFile(".hidden", "hidden\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-a", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, ".hidden"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "-"));
}

test "vdir [FUNC-LS-004b] -C overrides long format with multi-column columns" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "vdir");
    defer allocator.free(binary_path);

    try ctx.writeFile("col_a.txt", "a\n");
    try ctx.writeFile("col_b.txt", "b\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-C", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "col_a.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "col_b.txt"));
    // Overridden from long format: should not contain "total" line
    try testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, "total"));
}

test "vdir [FUNC-LS-004c] -x overrides long format with multi-column across" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "vdir");
    defer allocator.free(binary_path);

    try ctx.writeFile("x_a.txt", "a\n");
    try ctx.writeFile("x_b.txt", "b\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-x", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "x_a.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "x_b.txt"));
    try testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, "total"));
}

test "vdir [FUNC-LS-004a] -1 overrides long format with single column" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "vdir");
    defer allocator.free(binary_path);

    try ctx.writeFile("single_a.txt", "a\n");
    try ctx.writeFile("single_b.txt", "b\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-1", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "single_a.txt\n"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "single_b.txt\n"));
    try testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, "total"));
}

test "vdir [FUNC-LS-004d] -m overrides long format with comma stream" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "vdir");
    defer allocator.free(binary_path);

    try ctx.writeFile("stream_a.txt", "a\n");
    try ctx.writeFile("stream_b.txt", "b\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-m", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "stream_a.txt, stream_b.txt"));
    try testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, "total"));
}

test "vdir [FUNC-LS-005e] -r reverses listing" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "vdir");
    defer allocator.free(binary_path);

    try ctx.writeFile("first.txt", "1\n");
    try ctx.writeFile("second.txt", "2\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-r", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const sec_idx = std.mem.indexOf(u8, result.stdout, "second.txt") orelse return error.TestExpectedEqual;
    const fir_idx = std.mem.indexOf(u8, result.stdout, "first.txt") orelse return error.TestExpectedEqual;
    try testing.expect(sec_idx < fir_idx);
}

test "vdir [FUNC-LS-008] exit 2 on nonexistent operand" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "vdir");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const missing = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "not_found" });
    defer allocator.free(missing);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, missing }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 2), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "vdir: cannot access '"));
}

test "vdir [FUNC-LS-008] --version reports vdir" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "vdir");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "vdir"));
}

test "vdir [FUNC-LS-008] --help reports vdir usage" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "vdir");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "vdir"));
}
