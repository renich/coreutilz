const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

// [FUNC-LS-004b] Multi-Column Down Columns (dir default format)
test "dir [FUNC-LS-004b] default multi-column format without -C" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dir");
    defer allocator.free(binary_path);

    try ctx.writeFile("item1.txt", "1\n");
    try ctx.writeFile("item2.txt", "2\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "item1.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "item2.txt"));
    // Default dir is multi-column: does NOT output permissions like vdir/ls -l
    try testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, "total"));
}

test "dir [FUNC-LS-003] -l overrides multi-column with detailed long listing" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dir");
    defer allocator.free(binary_path);

    try ctx.writeFile("detail.txt", "content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "-"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "detail.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "total"));
}

test "dir [FUNC-LS-004a] -1 overrides multi-column with single column" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dir");
    defer allocator.free(binary_path);

    try ctx.writeFile("single_1.txt", "1\n");
    try ctx.writeFile("single_2.txt", "2\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-1", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "single_1.txt\n"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "single_2.txt\n"));
}

test "dir [FUNC-LS-004d] -m overrides multi-column with comma stream" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dir");
    defer allocator.free(binary_path);

    try ctx.writeFile("m1.txt", "1\n");
    try ctx.writeFile("m2.txt", "2\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-m", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "m1.txt, m2.txt"));
}

test "dir [FUNC-LS-002a] -a displays all files including dotfiles" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dir");
    defer allocator.free(binary_path);

    try ctx.writeFile(".hidden_dir", "hide\n");
    try ctx.writeFile("norm.txt", "norm\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-a", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, ".hidden_dir"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "norm.txt"));
}

test "dir [FUNC-LS-005b] -S sorts by file size" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dir");
    defer allocator.free(binary_path);

    try ctx.writeFile("small.txt", "1\n");
    try ctx.writeFile("huge.txt", "123456789012345678901234567890\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-1S", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const huge_idx = std.mem.indexOf(u8, result.stdout, "huge.txt") orelse return error.TestExpectedEqual;
    const small_idx = std.mem.indexOf(u8, result.stdout, "small.txt") orelse return error.TestExpectedEqual;
    try testing.expect(huge_idx < small_idx);
}

test "dir [FUNC-LS-008] exit 2 on nonexistent operand" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dir");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const missing = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "not_existing" });
    defer allocator.free(missing);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, missing }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 2), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "dir: cannot access '"));
}

test "dir [FUNC-LS-008] --version reports dir" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dir");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "dir"));
}

test "dir [FUNC-LS-008] --help reports dir usage" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dir");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "dir"));
}
