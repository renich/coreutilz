const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

// [FUNC-FOLD-001] Column & Byte Wrapping
test "fold [FUNC-FOLD-001] default width 80" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "fold");
    defer allocator.free(binary_path);

    const line = "a" ** 90 ++ "\n";
    try ctx.writeFile("input.txt", line);
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var res = try ctx.runCommand(&[_][]const u8{ binary_path, input }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    const expected = "a" ** 80 ++ "\n" ++ "a" ** 10 ++ "\n";
    try testing.expectEqualStrings(expected, res.stdout);
}

test "fold [FUNC-FOLD-001] custom width -w 10 and legacy -10" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "fold");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "1234567890abcdefghij\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var res1 = try ctx.runCommand(&[_][]const u8{ binary_path, "-w", "10", input }, null);
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("1234567890\nabcdefghij\n", res1.stdout);

    var res2 = try ctx.runCommand(&[_][]const u8{ binary_path, "-10", input }, null);
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("1234567890\nabcdefghij\n", res2.stdout);
}

test "fold [FUNC-FOLD-001] tab stop calculation" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "fold");
    defer allocator.free(binary_path);

    // "a\t" takes 8 columns, plus "bc" makes 10 columns
    try ctx.writeFile("input.txt", "a\tbcdef\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var res = try ctx.runCommand(&[_][]const u8{ binary_path, "-w", "8", input }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("a\t\nbcdef\n", res.stdout);
}

test "fold [FUNC-FOLD-001] -b byte counting mode" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "fold");
    defer allocator.free(binary_path);

    // In byte mode, '\t' is exactly 1 byte
    try ctx.writeFile("input.txt", "a\tb\tc\td\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var res = try ctx.runCommand(&[_][]const u8{ binary_path, "-b", "-w", "4", input }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("a\tb\t\nc\td\n", res.stdout);
}

test "fold [FUNC-FOLD-001] backspace decrements column position" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "fold");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "abc\x08\x08def\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var res = try ctx.runCommand(&[_][]const u8{ binary_path, "-w", "3", input }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("abc\x08\x08de\nf\n", res.stdout);
}

test "fold [FUNC-FOLD-001] carriage return resets column position" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "fold");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "12345\rabc\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var res = try ctx.runCommand(&[_][]const u8{ binary_path, "-w", "5", input }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("12345\rabc\n", res.stdout);
}

// [FUNC-FOLD-002] Space-Aware Word Breaking
test "fold [FUNC-FOLD-002] -s break at spaces" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "fold");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "the quick brown fox jumps\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var res = try ctx.runCommand(&[_][]const u8{ binary_path, "-w", "10", "-s", input }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("the quick \nbrown fox \njumps\n", res.stdout);
}

test "fold [FUNC-FOLD-002] -s word exceeds width breaks hard" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "fold");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "supercalifragilistic\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var res = try ctx.runCommand(&[_][]const u8{ binary_path, "-w", "10", "-s", input }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("supercalif\nragilistic\n", res.stdout);
}

test "fold [FUNC-FOLD-002] -s horizontal tab blank breaking" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "fold");
    defer allocator.free(binary_path);

    // "abc\tdefgh\n" with width 10 and -s:
    // "abc\t" takes 8 columns. "defgh" would take 8 + 5 = 13 > 10.
    // Since \t is a blank, break occurs after \t.
    try ctx.writeFile("input.txt", "abc\tdefgh\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var res = try ctx.runCommand(&[_][]const u8{ binary_path, "-w", "10", "-s", input }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("abc\t\ndefgh\n", res.stdout);
}

// [FUNC-TEXT-DIAG-001] Diagnostics
test "fold [FUNC-TEXT-DIAG-001] missing file diagnostic" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "fold");
    defer allocator.free(binary_path);

    var res = try ctx.runCommand(&[_][]const u8{ binary_path, "nonexistent_file" }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 1), res.exit_code);
    try testing.expect(res.stderr.len > 0);
}

test "fold [FUNC-TEXT-DIAG-001] --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "fold");
    defer allocator.free(binary_path);

    var h_res = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer h_res.deinit();
    try testing.expectEqual(@as(u8, 0), h_res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, h_res.stdout, 1, "Usage:"));

    var v_res = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer v_res.deinit();
    try testing.expectEqual(@as(u8, 0), v_res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, v_res.stdout, 1, "fold"));
}
