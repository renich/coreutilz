const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

// Ported from tests/cat/cat-E.sh
test "cat -E: CR+LF displays as ^M$" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const bin = try getBinaryPath(allocator, "cat");
    defer allocator.free(bin);

    try ctx.writeFile("in", "a\rb\r\nc\n\r\nd\r");
    const in_path = try ctx.tmpPath("in");
    defer allocator.free(in_path);

    var result = try ctx.runCommand(&.{ bin, "-E", in_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("a\rb^M$\nc$\n^M$\nd\r", result.stdout);
}

test "cat -E: CR+LF spanning two files" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const bin = try getBinaryPath(allocator, "cat");
    defer allocator.free(bin);

    try ctx.writeFile("in2", "1\r");
    try ctx.writeFile("in2b", "\n2\r\n");
    const p2 = try ctx.tmpPath("in2");
    defer allocator.free(p2);
    const p2b = try ctx.tmpPath("in2b");
    defer allocator.free(p2b);

    var result = try ctx.runCommand(&.{ bin, "-E", p2, p2b }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("1^M$\n2^M$\n", result.stdout);
}

test "cat -E: lone CR at file boundary is not treated as CR+LF" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const bin = try getBinaryPath(allocator, "cat");
    defer allocator.free(bin);

    try ctx.writeFile("in2", "1\r");
    try ctx.writeFile("in2b", "2\r\n");
    const p2 = try ctx.tmpPath("in2");
    defer allocator.free(p2);
    const p2b = try ctx.tmpPath("in2b");
    defer allocator.free(p2b);

    var result = try ctx.runCommand(&.{ bin, "-E", p2, p2b }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("1\r2^M$\n", result.stdout);
}

// Ported from tests/cat/cat-self.sh
test "cat: appending file to itself fails" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const bin = try getBinaryPath(allocator, "cat");
    defer allocator.free(bin);

    try ctx.writeFile("out", "x\n");
    try ctx.writeFile("out1", "x\n");
    const out_path = try ctx.tmpPath("out");
    defer allocator.free(out_path);

    // cat out >> out must fail
    var result = try ctx.runCommandWithStdoutFile(&.{ bin, out_path }, out_path, true);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);

    // File must be unchanged
    const content = try ctx.readFile("out");
    defer allocator.free(content);
    try testing.expectEqualStrings("x\n", content);
}

// Ported from tests/cat/ — basic functionality used by many upstream tests
test "cat: basic file output" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const bin = try getBinaryPath(allocator, "cat");
    defer allocator.free(bin);

    try ctx.writeFile("test.txt", "hello world\n");
    const file_path = try ctx.tmpPath("test.txt");
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&.{ bin, file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("hello world\n", result.stdout);
}

test "cat: concatenate multiple files" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const bin = try getBinaryPath(allocator, "cat");
    defer allocator.free(bin);

    try ctx.writeFile("f1.txt", "line1\n");
    try ctx.writeFile("f2.txt", "line2\n");
    const p1 = try ctx.tmpPath("f1.txt");
    defer allocator.free(p1);
    const p2 = try ctx.tmpPath("f2.txt");
    defer allocator.free(p2);

    var result = try ctx.runCommand(&.{ bin, p1, p2 }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("line1\nline2\n", result.stdout);
}

test "cat: read from stdin when no file given" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const bin = try getBinaryPath(allocator, "cat");
    defer allocator.free(bin);

    var result = try ctx.runCommand(&.{bin}, "stdin input\n");
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("stdin input\n", result.stdout);
}

test "cat -n: number all lines" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const bin = try getBinaryPath(allocator, "cat");
    defer allocator.free(bin);

    try ctx.writeFile("t.txt", "line1\nline2\n");
    const fp = try ctx.tmpPath("t.txt");
    defer allocator.free(fp);

    var result = try ctx.runCommand(&.{ bin, "-n", fp }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("     1\tline1\n     2\tline2\n", result.stdout);
}

test "cat -b: number non-blank lines only" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const bin = try getBinaryPath(allocator, "cat");
    defer allocator.free(bin);

    try ctx.writeFile("t.txt", "line1\n\nline2\n");
    const fp = try ctx.tmpPath("t.txt");
    defer allocator.free(fp);

    var result = try ctx.runCommand(&.{ bin, "-b", fp }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("     1\tline1\n\n     2\tline2\n", result.stdout);
}

test "cat -T: show tabs as ^I" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const bin = try getBinaryPath(allocator, "cat");
    defer allocator.free(bin);

    try ctx.writeFile("t.txt", "col1\tcol2\n");
    const fp = try ctx.tmpPath("t.txt");
    defer allocator.free(fp);

    var result = try ctx.runCommand(&.{ bin, "-T", fp }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("col1^Icol2\n", result.stdout);
}

test "cat -s: squeeze repeated blank lines" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const bin = try getBinaryPath(allocator, "cat");
    defer allocator.free(bin);

    try ctx.writeFile("t.txt", "line1\n\n\nline2\n");
    const fp = try ctx.tmpPath("t.txt");
    defer allocator.free(fp);

    var result = try ctx.runCommand(&.{ bin, "-s", fp }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("line1\n\nline2\n", result.stdout);
}

test "cat -A: show all (-v -E -T combined)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const bin = try getBinaryPath(allocator, "cat");
    defer allocator.free(bin);

    try ctx.writeFile("t.txt", "col1\tcol2\n");
    const fp = try ctx.tmpPath("t.txt");
    defer allocator.free(fp);

    var result = try ctx.runCommand(&.{ bin, "-A", fp }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("col1^Icol2$\n", result.stdout);
}

test "cat: nonexistent file exits 1" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const bin = try getBinaryPath(allocator, "cat");
    defer allocator.free(bin);

    const fp = try ctx.tmpPathRaw("nonexistent.txt");
    defer allocator.free(fp);

    var result = try ctx.runCommand(&.{ bin, fp }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "cat --help exits 0 and prints usage" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const bin = try getBinaryPath(allocator, "cat");
    defer allocator.free(bin);

    var result = try ctx.runCommand(&.{ bin, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "cat --version exits 0 and prints version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const bin = try getBinaryPath(allocator, "cat");
    defer allocator.free(bin);

    var result = try ctx.runCommand(&.{ bin, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "cat"));
}
