const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

// [FUNC-SORT-001] Stream & Operand Ingestion
test "sort [FUNC-SORT-001] basic lexicographical sort" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "sort");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "banana\napple\ncherry\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("apple\nbanana\ncherry\n", result.stdout);
}

test "sort [FUNC-SORT-001] multiple input files concatenated" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "sort");
    defer allocator.free(binary_path);

    try ctx.writeFile("file1.txt", "banana\n");
    try ctx.writeFile("file2.txt", "apple\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    defer allocator.free(file1_path);
    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2.txt" });
    defer allocator.free(file2_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, file1_path, file2_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("apple\nbanana\n", result.stdout);
}

// [FUNC-SORT-002b] Reverse Sort (-r)
test "sort [FUNC-SORT-002b] -r reverse sort" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "sort");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "apple\nbanana\ncherry\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-r", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("cherry\nbanana\napple\n", result.stdout);
}

// [FUNC-SORT-002c] Numeric Sort (-n)
test "sort [FUNC-SORT-002c] -n numeric sort" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "sort");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "10\n2\n1\n-5\n0\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-n", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("-5\n0\n1\n2\n10\n", result.stdout);
}

// [FUNC-SORT-002e] Human Numeric Sort (-h)
test "sort [FUNC-SORT-002e] -h human numeric sort" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "sort");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "1M\n2K\n500\n1G\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-h", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("500\n2K\n1M\n1G\n", result.stdout);
}

// [FUNC-SORT-002f] Month Sort (-M)
test "sort [FUNC-SORT-002f] -M month sort" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "sort");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "DEC\nFEB\nJAN\nOCT\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-M", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("JAN\nFEB\nOCT\nDEC\n", result.stdout);
}

// [FUNC-SORT-002g] Version Sort (-V)
test "sort [FUNC-SORT-002g] -V version sort" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "sort");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "v1.10.0\nv1.2.0\nv1.1.0\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-V", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("v1.1.0\nv1.2.0\nv1.10.0\n", result.stdout);
}

// [FUNC-SORT-003a] Delimiter and Key (-t, -k)
test "sort [FUNC-SORT-003a] -t and -k field selection" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "sort");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "apple:3\nbanana:1\ncherry:2\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-t", ":", "-k", "2n", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("banana:1\ncherry:2\napple:3\n", result.stdout);
}

// [FUNC-SORT-003d] Case Folding (-f)
test "sort [FUNC-SORT-003d] -f fold case" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "sort");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "apple\nBanana\ncherry\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-f", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("apple\nBanana\ncherry\n", result.stdout);
}

// [FUNC-SORT-004a] Unique Mode (-u)
test "sort [FUNC-SORT-004a] -u unique lines" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "sort");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "apple\nbanana\napple\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-u", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("apple\nbanana\n", result.stdout);
}

// [FUNC-SORT-004b] Check Mode (-c, -C)
test "sort [FUNC-SORT-004b] -c check mode passes on sorted input" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "sort");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "apple\nbanana\ncherry\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-c", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "sort [FUNC-SORT-004b] -c check mode fails and emits diagnostic on unsorted input" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "sort");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "banana\napple\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-c", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "disorder:"));
}

// [FUNC-SORT-004c] Merge Mode (-m)
test "sort [FUNC-SORT-004c] -m merge pre-sorted files" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "sort");
    defer allocator.free(binary_path);

    try ctx.writeFile("a.txt", "apple\ncherry\n");
    try ctx.writeFile("b.txt", "banana\ndate\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const fa = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "a.txt" });
    defer allocator.free(fa);
    const fb = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "b.txt" });
    defer allocator.free(fb);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-m", fa, fb }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("apple\nbanana\ncherry\ndate\n", result.stdout);
}

// [FUNC-SORT-005] Diagnostics & CLI help
test "sort [FUNC-SORT-005] --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "sort");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "sort [FUNC-SORT-005] --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "sort");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "sort"));
}
