const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

// [FUNC-TAIL-001] Line & Byte Window Extraction
test "tail [FUNC-TAIL-001a] default last 10 lines" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tail");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, input }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n", result.stdout);
}

test "tail [FUNC-TAIL-001a] -n 3 last 3 lines" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tail");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "line1\nline2\nline3\nline4\nline5\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-n", "3", input }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("line3\nline4\nline5\n", result.stdout);
}

test "tail [FUNC-TAIL-001a] -n +3 starting from line 3" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tail");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "1\n2\n3\n4\n5\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-n", "+3", input }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("3\n4\n5\n", result.stdout);
}

test "tail [FUNC-TAIL-001b] -c 4 last 4 bytes" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tail");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "abcdefgh");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-c", "4", input }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("efgh", result.stdout);
}

test "tail [FUNC-TAIL-001b] -c +4 starting from byte 4" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tail");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "abcdefgh");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-c", "+4", input }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("defgh", result.stdout);
}

test "tail [FUNC-TAIL-001b] -c with multiplier suffixes" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tail");
    defer allocator.free(binary_path);

    const input_data = "x" ** 2048;
    try ctx.writeFile("input.bin", input_data);
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.bin" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-c", "1K", input }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqual(@as(usize, 1024), result.stdout.len);
}

test "tail [FUNC-TAIL-001c] -z zero-terminated records" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tail");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "rec1\x00rec2\x00rec3\x00");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-z", "-n", "2", input }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("rec2\x00rec3\x00", result.stdout);
}

// [FUNC-TAIL-002] Multi-File Headers
test "tail [FUNC-TAIL-002] multiple files banner headers" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tail");
    defer allocator.free(binary_path);

    try ctx.writeFile("f1.txt", "hello\n");
    try ctx.writeFile("f2.txt", "world\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const f1 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f1.txt" });
    defer allocator.free(f1);
    const f2 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f2.txt" });
    defer allocator.free(f2);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, f1, f2 }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "==>"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "f1.txt <=="));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "f2.txt <=="));
}

test "tail [FUNC-TAIL-002] -q quiet suppresses headers" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tail");
    defer allocator.free(binary_path);

    try ctx.writeFile("f1.txt", "hello\n");
    try ctx.writeFile("f2.txt", "world\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const f1 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f1.txt" });
    defer allocator.free(f1);
    const f2 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f2.txt" });
    defer allocator.free(f2);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-q", f1, f2 }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, "==>"));
    try testing.expectEqualStrings("hello\nworld\n", result.stdout);
}

test "tail [FUNC-TAIL-002] -v verbose single-file banner header" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tail");
    defer allocator.free(binary_path);

    try ctx.writeFile("single.txt", "hello\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "single.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-v", input }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "==>"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "single.txt <=="));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "hello\n"));
}

// [FUNC-TAIL-003] Live Follow Mode
test "tail [FUNC-TAIL-003] live follow --pid terminates on dead PID" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tail");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "line1\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    // PID 99999999 is dead/non-existent, so tail -f --pid=99999999 should terminate promptly
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-f", "-s", "0.01", "--pid=99999999", input }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("line1\n", result.stdout);
}

// [FUNC-TEXT-DIAG-001] Diagnostics
test "tail [FUNC-TEXT-DIAG-001] non-existent file error" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tail");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "nonexistent_file_xyz" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expect(result.stderr.len > 0);
}

test "tail [FUNC-TEXT-DIAG-001] --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tail");
    defer allocator.free(binary_path);

    var h_res = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer h_res.deinit();
    try testing.expectEqual(@as(u8, 0), h_res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, h_res.stdout, 1, "Usage:"));

    var v_res = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer v_res.deinit();
    try testing.expectEqual(@as(u8, 0), v_res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, v_res.stdout, 1, "tail"));
}
