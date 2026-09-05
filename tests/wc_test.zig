const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "wc basic (default)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "wc");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "hello world\nthis is a test\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    // 2 lines, 7 words, 27 bytes (hello world\n = 12, this is a test\n = 15)
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "2"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "7"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "27"));
}

test "wc -l (lines only)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "wc");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "line 1\nline 2\nline 3\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "3"));
    try testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, "12")); // Should not have word count
}

test "wc -w (words only)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "wc");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "one two three four five");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-w", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "5"));
}

test "wc -c (bytes only)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "wc");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "1234567890");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-c", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "10"));
}

test "wc -m (chars)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "wc");
    defer allocator.free(binary_path);

    // Multi-byte characters: "hello 🌍" (🌍 is 4 bytes in UTF-8)
    try ctx.writeFile("test.txt", "hello \xf0\x9f\x8c\x8d");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-m", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    // "hello " (6) + "🌍" (1) = 7 chars
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "7"));
}

test "wc -L (max line length)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "wc");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "short\nthis is a longer line\nmedium\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-L", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    // "this is a longer line" is 21 characters
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "21"));
}

test "wc multiple files" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "wc");
    defer allocator.free(binary_path);

    try ctx.writeFile("file1.txt", "l1\n");
    try ctx.writeFile("file2.txt", "l1\nl2\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    defer allocator.free(file1_path);
    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2.txt" });
    defer allocator.free(file2_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l", file1_path, file2_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "1"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "2"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "3")); // total
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "total"));
}

test "wc --help" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "wc");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "wc --version" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "wc");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "wc"));
}

test "wc nonexistent file" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "wc");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "nonexistent.txt" }, null);
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
}

test "wc stdin default no args" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "wc");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{binary_path}, "one two three\nfour five\n");
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    // 2 lines, 5 words, 24 bytes
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "2"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "5"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "24"));
    // No filename when reading stdin by default
    try testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, "-"));
}

test "wc stdin with - argument" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "wc");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l", "-" }, "line 1\nline 2\n");
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "2"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "-"));
}

test "wc --total=always" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "wc");
    defer allocator.free(binary_path);

    try ctx.writeFile("file.txt", "hello world\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l", "--total=always", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "total"));
}

test "wc --total=only" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "wc");
    defer allocator.free(binary_path);

    try ctx.writeFile("f1.txt", "a\n");
    try ctx.writeFile("f2.txt", "b\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const f1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f1.txt" });
    defer allocator.free(f1_path);
    const f2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f2.txt" });
    defer allocator.free(f2_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l", "--total=only", f1_path, f2_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "2 total"));
    try testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, "f1.txt"));
}

test "wc --total=never" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "wc");
    defer allocator.free(binary_path);

    try ctx.writeFile("f1.txt", "a\n");
    try ctx.writeFile("f2.txt", "b\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const f1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f1.txt" });
    defer allocator.free(f1_path);
    const f2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f2.txt" });
    defer allocator.free(f2_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l", "--total=never", f1_path, f2_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, "total"));
}

test "wc --files0-from" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "wc");
    defer allocator.free(binary_path);

    try ctx.writeFile("a.txt", "aaa\n");
    try ctx.writeFile("b.txt", "bb\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const a_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "a.txt" });
    defer allocator.free(a_path);
    const b_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "b.txt" });
    defer allocator.free(b_path);

    var f0_content: std.ArrayList(u8) = .empty;
    defer f0_content.deinit(allocator);
    try f0_content.appendSlice(allocator, a_path);
    try f0_content.append(allocator, 0);
    try f0_content.appendSlice(allocator, b_path);
    try f0_content.append(allocator, 0);

    try ctx.writeFile("list.f0", f0_content.items);
    const f0_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "list.f0" });
    defer allocator.free(f0_path);

    const f0_arg = try std.fmt.allocPrint(allocator, "--files0-from={s}", .{f0_path});
    defer allocator.free(f0_arg);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l", f0_arg }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "a.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "b.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "2 total"));
}
