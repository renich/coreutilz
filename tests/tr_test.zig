const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

// [FUNC-TR-001] Operand Validation & Set Specifications
test "tr [FUNC-TR-001] missing operand error" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tr");
    defer allocator.free(binary_path);

    var res = try ctx.runCommand(&[_][]const u8{binary_path}, "test\n");
    defer res.deinit();

    try testing.expectEqual(@as(u8, 1), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stderr, 1, "missing operand"));
}

test "tr [FUNC-TR-001] translation requires two operands" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tr");
    defer allocator.free(binary_path);

    var res = try ctx.runCommand(&[_][]const u8{ binary_path, "a" }, "test\n");
    defer res.deinit();

    try testing.expectEqual(@as(u8, 1), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stderr, 1, "missing operand after 'a'"));
}

test "tr [FUNC-TR-001] character ranges and classes" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tr");
    defer allocator.free(binary_path);

    var res = try ctx.runCommand(&[_][]const u8{ binary_path, "[:lower:]", "[:upper:]" }, "hello world 123\n");
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("HELLO WORLD 123\n", res.stdout);
}

test "tr [FUNC-TR-001] octal and standard escapes" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tr");
    defer allocator.free(binary_path);

    var res = try ctx.runCommand(&[_][]const u8{ binary_path, "\\n", "\\t" }, "a\nb\n");
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("a\tb\t", res.stdout);
}

test "tr [FUNC-TR-001] file operands rejection error" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tr");
    defer allocator.free(binary_path);

    var res = try ctx.runCommand(&[_][]const u8{ binary_path, "a", "b", "file.txt" }, "input\n");
    defer res.deinit();

    try testing.expectEqual(@as(u8, 1), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stderr, 1, "extra operand"));
}

test "tr [FUNC-TR-001] -d with two operands extra operand error" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tr");
    defer allocator.free(binary_path);

    var res = try ctx.runCommand(&[_][]const u8{ binary_path, "-d", "a", "b" }, "input\n");
    defer res.deinit();

    try testing.expectEqual(@as(u8, 1), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stderr, 1, "extra operand"));
}

test "tr [FUNC-TR-001] repeat syntax and padding in SET2" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tr");
    defer allocator.free(binary_path);

    var res1 = try ctx.runCommand(&[_][]const u8{ binary_path, "abc", "[x*3]" }, "a b c\n");
    defer res1.deinit();

    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("x x x\n", res1.stdout);

    var res2 = try ctx.runCommand(&[_][]const u8{ binary_path, "abc", "x[y*]" }, "a b c\n");
    defer res2.deinit();

    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("x y y\n", res2.stdout);
}

// [FUNC-TR-002] Translation, Deletion & Squeezing Modes
test "tr [FUNC-TR-002a] basic translation" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tr");
    defer allocator.free(binary_path);

    var res = try ctx.runCommand(&[_][]const u8{ binary_path, "abc", "xyz" }, "cab badge\n");
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("zxy yxdge\n", res.stdout);
}

test "tr [FUNC-TR-002a] shorter SET2 extension repeats last char" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tr");
    defer allocator.free(binary_path);

    var res = try ctx.runCommand(&[_][]const u8{ binary_path, "abc", "x" }, "a b c\n");
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("x x x\n", res.stdout);
}

test "tr [FUNC-TR-002b] -d delete characters" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tr");
    defer allocator.free(binary_path);

    var res = try ctx.runCommand(&[_][]const u8{ binary_path, "-d", "aeiou" }, "the quick brown fox\n");
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("th qck brwn fx\n", res.stdout);
}

test "tr [FUNC-TR-002c] -s squeeze repeated characters" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tr");
    defer allocator.free(binary_path);

    var res = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", " " }, "hello    world   again\n");
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("hello world again\n", res.stdout);
}

test "tr [FUNC-TR-002d] -d -s delete and squeeze" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tr");
    defer allocator.free(binary_path);

    var res = try ctx.runCommand(&[_][]const u8{ binary_path, "-d", "-s", "a-z", " " }, "123  abc   456   def 789\n");
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("123 456 789\n", res.stdout);
}

test "tr [FUNC-TR-002e] -c complement" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tr");
    defer allocator.free(binary_path);

    var res = try ctx.runCommand(&[_][]const u8{ binary_path, "-c", "[:alnum:]\n", "#" }, "user@example.com (42)!\n");
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("user#example#com##42##\n", res.stdout);
}

test "tr [FUNC-TR-002f] -t truncate set1" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tr");
    defer allocator.free(binary_path);

    var res = try ctx.runCommand(&[_][]const u8{ binary_path, "-t", "abc", "x" }, "abc def\n");
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("xbc def\n", res.stdout);
}

// [FUNC-TEXT-DIAG-001] Diagnostics
test "tr [FUNC-TEXT-DIAG-001] --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tr");
    defer allocator.free(binary_path);

    var h_res = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer h_res.deinit();
    try testing.expectEqual(@as(u8, 0), h_res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, h_res.stdout, 1, "Usage:"));

    var v_res = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer v_res.deinit();
    try testing.expectEqual(@as(u8, 0), v_res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, v_res.stdout, 1, "tr"));
}
