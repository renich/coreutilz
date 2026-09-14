const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

// [FUNC-UNIQ-001] Adjacent Duplicate Line Filtering
test "uniq [FUNC-UNIQ-001] basic adjacent deduplication" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "uniq");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "apple\napple\nbanana\napple\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("apple\nbanana\napple\n", result.stdout);
}

// [FUNC-UNIQ-002a] Prefix Count (-c)
test "uniq [FUNC-UNIQ-002a] -c prefix count occurrences" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "uniq");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "apple\napple\nbanana\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-c", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "2 apple\n"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "1 banana\n"));
}

// [FUNC-UNIQ-002b] Repeated Only (-d)
test "uniq [FUNC-UNIQ-002b] -d print duplicates only" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "uniq");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "apple\napple\nbanana\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-d", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("apple\n", result.stdout);
}

// [FUNC-UNIQ-002c] All Repeated (-D)
test "uniq [FUNC-UNIQ-002c] -D print all duplicate lines" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "uniq");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "apple\napple\nbanana\ncherry\ncherry\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-D", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("apple\napple\ncherry\ncherry\n", result.stdout);
}

// [FUNC-UNIQ-002d] Unique Only (-u)
test "uniq [FUNC-UNIQ-002d] -u print unique lines only" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "uniq");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "apple\napple\nbanana\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-u", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("banana\n", result.stdout);
}

// [FUNC-UNIQ-003d] Ignore Case (-i)
test "uniq [FUNC-UNIQ-003d] -i ignore case" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "uniq");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "apple\nAPPLE\nbanana\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-i", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("apple\nbanana\n", result.stdout);
}

// [FUNC-UNIQ-003a] Skip Fields (-f)
test "uniq [FUNC-UNIQ-003a] -f skip fields" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "uniq");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "1 apple\n2 apple\n3 banana\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-f", "1", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("1 apple\n3 banana\n", result.stdout);
}

// [FUNC-UNIQ-003b] Skip Characters (-s)
test "uniq [FUNC-UNIQ-003b] -s skip chars" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "uniq");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "aapple\nbapple\ncherry\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "1", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("aapple\ncherry\n", result.stdout);
}

// [FUNC-UNIQ-004] Output File Operand & Help
test "uniq [FUNC-UNIQ-004] write to output file" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "uniq");
    defer allocator.free(binary_path);

    try ctx.writeFile("in.txt", "a\na\nb\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const in_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "in.txt" });
    defer allocator.free(in_path);
    const out_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "out.txt" });
    defer allocator.free(out_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, in_path, out_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const out_content = try ctx.readFile("out.txt");
    defer allocator.free(out_content);
    try testing.expectEqualStrings("a\nb\n", out_content);
}

test "uniq [FUNC-UNIQ-004] --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "uniq");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "uniq [FUNC-UNIQ-004] --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "uniq");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "uniq"));
}
