const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "cut basic fields" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "cut");
    defer allocator.free(bin);

    // -d: -f1,3-
    var res1 = try ctx.runCommand(&[_][]const u8{ bin, "-d:", "-f1,3-" }, "a:b:c\n");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("a:c\n", res1.stdout);

    // -d: -f2-
    var res2 = try ctx.runCommand(&[_][]const u8{ bin, "-d:", "-f2-" }, "a:b:c\n");
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("b:c\n", res2.stdout);

    // -d: -f4
    var res3 = try ctx.runCommand(&[_][]const u8{ bin, "-d:", "-f4" }, "a:b:c\n");
    defer res3.deinit();
    try testing.expectEqual(@as(u8, 0), res3.exit_code);
    try testing.expectEqualStrings("\n", res3.stdout);

    // empty input
    var res4 = try ctx.runCommand(&[_][]const u8{ bin, "-d:", "-f4" }, "");
    defer res4.deinit();
    try testing.expectEqual(@as(u8, 0), res4.exit_code);
    try testing.expectEqualStrings("", res4.stdout);
}

test "cut bytes and characters" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "cut");
    defer allocator.free(bin);

    // -c4
    var res1 = try ctx.runCommand(&[_][]const u8{ bin, "-c4" }, "123\n");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("\n", res1.stdout);

    // -c4 without trailing newline
    var res2 = try ctx.runCommand(&[_][]const u8{ bin, "-c4" }, "123");
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("\n", res2.stdout);

    // -c4 multi-line
    var res3 = try ctx.runCommand(&[_][]const u8{ bin, "-c4" }, "123\n1");
    defer res3.deinit();
    try testing.expectEqual(@as(u8, 0), res3.exit_code);
    try testing.expectEqualStrings("\n\n", res3.stdout);

    // -b1-3
    var res4 = try ctx.runCommand(&[_][]const u8{ bin, "-b1-3" }, "abcdef\n");
    defer res4.deinit();
    try testing.expectEqual(@as(u8, 0), res4.exit_code);
    try testing.expectEqualStrings("abc\n", res4.stdout);

    // empty input with -b1
    var res5 = try ctx.runCommand(&[_][]const u8{ bin, "-b1" }, "");
    defer res5.deinit();
    try testing.expectEqual(@as(u8, 0), res5.exit_code);
    try testing.expectEqualStrings("", res5.stdout);
}

test "cut suppress non-delimited (-s)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "cut");
    defer allocator.free(bin);

    // -s -d: -f3-
    var res1 = try ctx.runCommand(&[_][]const u8{ bin, "-s", "-d:", "-f3-" }, "a:b:c\n");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("c\n", res1.stdout);

    // -s -d: -f2,3 on non-delimited line
    var res2 = try ctx.runCommand(&[_][]const u8{ bin, "-s", "-d:", "-f2,3" }, "abc\n");
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("", res2.stdout);

    // without -s on non-delimited line
    var res3 = try ctx.runCommand(&[_][]const u8{ bin, "-d:", "-f2,3" }, "abc\n");
    defer res3.deinit();
    try testing.expectEqual(@as(u8, 0), res3.exit_code);
    try testing.expectEqualStrings("abc\n", res3.stdout);

    // empty input with -s
    var res4 = try ctx.runCommand(&[_][]const u8{ bin, "-s", "-f3-" }, "");
    defer res4.deinit();
    try testing.expectEqual(@as(u8, 0), res4.exit_code);
    try testing.expectEqualStrings("", res4.stdout);
}

test "cut consecutive delimiters" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "cut");
    defer allocator.free(bin);

    // -d: -f1-3 on :::\n
    var res1 = try ctx.runCommand(&[_][]const u8{ bin, "-d:", "-f1-3" }, ":::\n");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("::\n", res1.stdout);

    // -d: -f1-4 on :::\n
    var res2 = try ctx.runCommand(&[_][]const u8{ bin, "-d:", "-f1-4" }, ":::\n");
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings(":::\n", res2.stdout);

    // -s -d: -f2-4 on :::\n:1\n
    var res3 = try ctx.runCommand(&[_][]const u8{ bin, "-s", "-d:", "-f2-4" }, ":::\n:1\n");
    defer res3.deinit();
    try testing.expectEqual(@as(u8, 0), res3.exit_code);
    try testing.expectEqualStrings("::\n1\n", res3.stdout);
}

test "cut output delimiter" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "cut");
    defer allocator.free(bin);

    // -d: --output-delimiter=_ -f2,3
    var res1 = try ctx.runCommand(&[_][]const u8{ bin, "-d:", "--output-delimiter=_", "-f2,3" }, "a:b:c\n");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("b_c\n", res1.stdout);

    // multi-char output delimiter
    var res2 = try ctx.runCommand(&[_][]const u8{ bin, "-d:", "--output-delimiter=_._", "-f2,3" }, "a:b:c\n");
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("b_._c\n", res2.stdout);

    // output delimiter in byte mode with separated ranges
    var res3 = try ctx.runCommand(&[_][]const u8{ bin, "-c1-3,5-", "--output-delimiter=:" }, "abcdefg\n");
    defer res3.deinit();
    try testing.expectEqual(@as(u8, 0), res3.exit_code);
    try testing.expectEqualStrings("abc:efg\n", res3.stdout);

    // abutting ranges in byte mode
    var res4 = try ctx.runCommand(&[_][]const u8{ bin, "-b1-2,3-4", "--output-delimiter=:" }, "abcd\n");
    defer res4.deinit();
    try testing.expectEqual(@as(u8, 0), res4.exit_code);
    try testing.expectEqualStrings("ab:cd\n", res4.stdout);

    // overlapping ranges in byte mode
    var res5 = try ctx.runCommand(&[_][]const u8{ bin, "-b1-2,2", "--output-delimiter=:" }, "abc\n");
    defer res5.deinit();
    try testing.expectEqual(@as(u8, 0), res5.exit_code);
    try testing.expectEqualStrings("ab\n", res5.stdout);
}

test "cut complement option" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "cut");
    defer allocator.free(bin);

    // --complement -b2
    var res1 = try ctx.runCommand(&[_][]const u8{ bin, "--complement", "-b2" }, "abcdef\n");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("acdef\n", res1.stdout);

    // --complement -b3,4-4,5,2- (EOL subsumed)
    var res2 = try ctx.runCommand(&[_][]const u8{ bin, "--complement", "-b3,4-4,5,2-" }, "123456\n");
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("1\n", res2.stdout);

    // --complement -f1 -d:
    var res3 = try ctx.runCommand(&[_][]const u8{ bin, "--complement", "-f1", "-d:" }, "a:b:c\n");
    defer res3.deinit();
    try testing.expectEqual(@as(u8, 0), res3.exit_code);
    try testing.expectEqualStrings("b:c\n", res3.stdout);
}

test "cut NUL delimiter and zero-terminated" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "cut");
    defer allocator.free(bin);

    // -d '' (NUL input delimiter)
    var res1 = try ctx.runCommand(&[_][]const u8{ bin, "-d", "", "--output-delimiter=_", "-f2,3" }, "a\x00b\x00c\n");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("b_c\n", res1.stdout);

    // --output-delimiter='' (NUL output delimiter)
    var res2 = try ctx.runCommand(&[_][]const u8{ bin, "-d:", "--output-delimiter=", "-f2,3" }, "a:b:c\n");
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("b\x00c\n", res2.stdout);

    // -z (zero-terminated lines)
    var res3 = try ctx.runCommand(&[_][]const u8{ bin, "-z", "-c1" }, "ab\x00cd\x00");
    defer res3.deinit();
    try testing.expectEqual(@as(u8, 0), res3.exit_code);
    try testing.expectEqualStrings("a\x00c\x00", res3.stdout);
}

test "cut newline delimiter (-d $'\\n')" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "cut");
    defer allocator.free(bin);

    // -d "\n" -f1
    var res1 = try ctx.runCommand(&[_][]const u8{ bin, "-d\n", "-f1" }, "a:1\nb:");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("a:1\n", res1.stdout);

    // -d "\n" -f2
    var res2 = try ctx.runCommand(&[_][]const u8{ bin, "-d\n", "-f2" }, "\nb");
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("b\n", res2.stdout);
}

test "cut errors and diagnostics" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "cut");
    defer allocator.free(bin);

    // No list specified
    var res1 = try ctx.runCommand(&[_][]const u8{bin}, ":\n");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 1), res1.exit_code);
    try testing.expect(std.mem.indexOf(u8, res1.stderr, "you must specify a list of bytes, characters, or fields") != null);

    // -b0
    var res2 = try ctx.runCommand(&[_][]const u8{ bin, "-b0" }, null);
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 1), res2.exit_code);
    try testing.expect(std.mem.indexOf(u8, res2.stderr, "byte/character positions are numbered from 1") != null);

    // -f0-2
    var res3 = try ctx.runCommand(&[_][]const u8{ bin, "-f0-2" }, null);
    defer res3.deinit();
    try testing.expectEqual(@as(u8, 1), res3.exit_code);
    try testing.expect(std.mem.indexOf(u8, res3.stderr, "fields are numbered from 1") != null);

    // Decreasing range -f 2-0
    var res4 = try ctx.runCommand(&[_][]const u8{ bin, "-f", "2-0" }, null);
    defer res4.deinit();
    try testing.expectEqual(@as(u8, 1), res4.exit_code);
    try testing.expect(std.mem.indexOf(u8, res4.stderr, "invalid decreasing range") != null);

    // Lone dash -f -
    var res5 = try ctx.runCommand(&[_][]const u8{ bin, "-f", "-" }, null);
    defer res5.deinit();
    try testing.expectEqual(@as(u8, 1), res5.exit_code);
    try testing.expect(std.mem.indexOf(u8, res5.stderr, "invalid range with no endpoint: -") != null);

    // -s with -b4
    var res6 = try ctx.runCommand(&[_][]const u8{ bin, "-s", "-b4" }, ":\n");
    defer res6.deinit();
    try testing.expectEqual(@as(u8, 1), res6.exit_code);
    try testing.expect(std.mem.indexOf(u8, res6.stderr, "suppressing non-delimited lines makes sense") != null);

    // -d with -b1
    var res7 = try ctx.runCommand(&[_][]const u8{ bin, "-d:", "-b1" }, null);
    defer res7.deinit();
    try testing.expectEqual(@as(u8, 1), res7.exit_code);
    try testing.expect(std.mem.indexOf(u8, res7.stderr, "an input delimiter may be specified only when operating on fields") != null);

    // Multiple lists: -b1 -f1
    var res8 = try ctx.runCommand(&[_][]const u8{ bin, "-b1", "-f1" }, null);
    defer res8.deinit();
    try testing.expectEqual(@as(u8, 1), res8.exit_code);
    try testing.expect(std.mem.indexOf(u8, res8.stderr, "only one list may be specified") != null);

    // Delimiter longer than 1 character
    var res9 = try ctx.runCommand(&[_][]const u8{ bin, "-d", "foo", "-f1" }, null);
    defer res9.deinit();
    try testing.expectEqual(@as(u8, 1), res9.exit_code);
    try testing.expect(std.mem.indexOf(u8, res9.stderr, "the delimiter must be a single character") != null);
}

test "cut multiple files and non-existent file" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "cut");
    defer allocator.free(bin);

    try ctx.writeFile("file1.txt", "a:1\nb:2\n");
    try ctx.writeFile("file2.txt", "c:3\nd:4\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const f1 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    defer allocator.free(f1);
    const f2 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2.txt" });
    defer allocator.free(f2);
    const nofile = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "nofile.txt" });
    defer allocator.free(nofile);

    // Multiple existing files
    var res1 = try ctx.runCommand(&[_][]const u8{ bin, "-d:", "-f1", f1, f2 }, null);
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("a\nb\nc\nd\n", res1.stdout);

    // Nonexistent file
    var res2 = try ctx.runCommand(&[_][]const u8{ bin, "-d:", "-f1", nofile }, null);
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 1), res2.exit_code);
    try testing.expect(std.mem.indexOf(u8, res2.stderr, "No such file or directory") != null);
}

test "cut multicall execution" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "coreutilz");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "cut", "-d:", "-f1,2", "--output-delimiter=_" }, "a:b:c\n");
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("a_b\n", res.stdout);
}
