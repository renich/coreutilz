const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "nl default numbering non-empty lines" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "nl");
    defer allocator.free(bin);

    try ctx.writeFile("input.txt", "line1\n\nline2\n");
    const p = try ctx.tmpPath("input.txt");
    defer allocator.free(p);

    var res = try ctx.runCommand(&[_][]const u8{ bin, p }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("     1\tline1\n       \n     2\tline2\n", res.stdout);
}

test "nl -ba numbers all lines" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "nl");
    defer allocator.free(bin);

    try ctx.writeFile("input.txt", "a\n\nb\n");
    const p = try ctx.tmpPath("input.txt");
    defer allocator.free(p);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-ba", p }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("     1\ta\n     2\t\n     3\tb\n", res.stdout);
}

test "nl formats -n ln, rn, rz and custom separator" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "nl");
    defer allocator.free(bin);

    try ctx.writeFile("input.txt", "hello\n");
    const p = try ctx.tmpPath("input.txt");
    defer allocator.free(p);

    var res_ln = try ctx.runCommand(&[_][]const u8{ bin, "-n", "ln", p }, null);
    defer res_ln.deinit();
    try testing.expectEqualStrings("1     \thello\n", res_ln.stdout);

    var res_rz = try ctx.runCommand(&[_][]const u8{ bin, "-n", "rz", "-s: ", p }, null);
    defer res_rz.deinit();
    try testing.expectEqualStrings("000001: hello\n", res_rz.stdout);
}

test "nl start number and increment" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "nl");
    defer allocator.free(bin);

    try ctx.writeFile("input.txt", "first\nsecond\nthird\n");
    const p = try ctx.tmpPath("input.txt");
    defer allocator.free(p);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-v", "10", "-i", "5", p }, null);
    defer res.deinit();

    try testing.expectEqualStrings("    10\tfirst\n    15\tsecond\n    20\tthird\n", res.stdout);
}

test "nl --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "nl");
    defer allocator.free(bin);

    var res_h = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res_h.deinit();
    try testing.expectEqual(@as(u8, 0), res_h.exit_code);

    var res_v = try ctx.runCommand(&[_][]const u8{ bin, "--version" }, null);
    defer res_v.deinit();
    try testing.expectEqual(@as(u8, 0), res_v.exit_code);
}
