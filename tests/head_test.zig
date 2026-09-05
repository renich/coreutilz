const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "head basic (default 10 lines)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "head");
    defer allocator.free(binary_path);

    // Create a test file with 15 lines
    var buffer: [100]u8 = undefined;
    var content: std.ArrayList(u8) = .empty;
    defer content.deinit(allocator);
    var i: usize = 1;
    while (i <= 15) : (i += 1) {
        const line = try std.fmt.bufPrint(&buffer, "line {d}\n", .{i});
        try content.appendSlice(allocator, line);
    }
    try ctx.writeFile("test.txt", content.items);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    var expected: std.ArrayList(u8) = .empty;
    defer expected.deinit(allocator);
    i = 1;
    while (i <= 10) : (i += 1) {
        const line = try std.fmt.bufPrint(&buffer, "line {d}\n", .{i});
        try expected.appendSlice(allocator, line);
    }
    try testing.expectEqualStrings(expected.items, result.stdout);
}

test "head -n (specific count)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "head");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "line 1\nline 2\nline 3\nline 4\nline 5\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-n", "2", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("line 1\nline 2\n", result.stdout);
}

test "head -c (bytes)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "head");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "1234567890");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-c", "5", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("12345", result.stdout);
}

test "head multiple files" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "head");
    defer allocator.free(binary_path);

    try ctx.writeFile("file1.txt", "f1l1\n");
    try ctx.writeFile("file2.txt", "f2l1\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    defer allocator.free(file1_path);
    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2.txt" });
    defer allocator.free(file2_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, file1_path, file2_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Check if headers are present
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "==>"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "file1.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "file2.txt"));
}

test "head -v (verbose)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "head");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "line1\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-v", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "==>"));
}

test "head -q (quiet)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "head");
    defer allocator.free(binary_path);

    try ctx.writeFile("file1.txt", "f1l1\n");
    try ctx.writeFile("file2.txt", "f2l1\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    defer allocator.free(file1_path);
    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2.txt" });
    defer allocator.free(file2_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-q", file1_path, file2_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, "==>"));
}

test "head --help" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "head");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "head --version" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "head");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "head"));
}

test "head nonexistent file" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "head");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "nonexistent.txt" }, null);
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
}

test "head reads stdin by default" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "head");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-n", "2" }, "line 1\nline 2\nline 3\n");
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("line 1\nline 2\n", result.stdout);
}

test "head reads stdin with - operand" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "head");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-n", "1", "-" }, "alpha\nbeta\n");
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("alpha\n", result.stdout);
}

test "head -n negative elides tail lines" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "head");
    defer allocator.free(binary_path);

    try ctx.writeFile("file.txt", "1\n2\n3\n4\n5\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-n", "-2", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("1\n2\n3\n", result.stdout);
}

test "head -c negative elides tail bytes" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "head");
    defer allocator.free(binary_path);

    try ctx.writeFile("file.txt", "hello world");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-c", "-6", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("hello", result.stdout);
}

test "head -z zero-terminated" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "head");
    defer allocator.free(binary_path);

    try ctx.writeFile("zero.txt", "rec1\x00rec2\x00rec3\x00");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "zero.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-z", "-n", "2", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("rec1\x00rec2\x00", result.stdout);
}

test "head obsolete -NUM syntax" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "head");
    defer allocator.free(binary_path);

    try ctx.writeFile("lines.txt", "1\n2\n3\n4\n5\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "lines.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-3", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("1\n2\n3\n", result.stdout);
}

test "head -c multiplier suffix (1K)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "head");
    defer allocator.free(binary_path);

    var big_buf: [2048]u8 = undefined;
    @memset(&big_buf, 'x');
    try ctx.writeFile("big.txt", &big_buf);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "big.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-c", "1K", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqual(@as(usize, 1024), result.stdout.len);
}

test "head invalid count exits 1" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "head");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-n", "invalid" }, null);
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
}
