const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "expr --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "expr");
    defer allocator.free(bin);

    var res_h = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res_h.deinit();
    try testing.expectEqual(@as(u8, 0), res_h.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_h.stdout, 1, "Usage: expr"));

    var res_v = try ctx.runCommand(&[_][]const u8{ bin, "--version" }, null);
    defer res_v.deinit();
    try testing.expectEqual(@as(u8, 0), res_v.exit_code);
}

test "expr arithmetic operations" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "expr");
    defer allocator.free(bin);

    // 2 + 3 = 5
    var res1 = try ctx.runCommand(&[_][]const u8{ bin, "2", "+", "3" }, null);
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("5\n", res1.stdout);

    // 10 - 4 = 6
    var res2 = try ctx.runCommand(&[_][]const u8{ bin, "10", "-", "4" }, null);
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("6\n", res2.stdout);

    // 5 - 5 = 0 (exit 1 because 0)
    var res3 = try ctx.runCommand(&[_][]const u8{ bin, "5", "-", "5" }, null);
    defer res3.deinit();
    try testing.expectEqual(@as(u8, 1), res3.exit_code);
    try testing.expectEqualStrings("0\n", res3.stdout);
}

test "expr string functions length and substr" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "expr");
    defer allocator.free(bin);

    // length "foobar" = 6
    var res1 = try ctx.runCommand(&[_][]const u8{ bin, "length", "foobar" }, null);
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("6\n", res1.stdout);

    // substr "foobar" 4 3 = "bar"
    var res2 = try ctx.runCommand(&[_][]const u8{ bin, "substr", "foobar", "4", "3" }, null);
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("bar\n", res2.stdout);
}

test "expr division by zero exits 2" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "expr");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "5", "/", "0" }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 2), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stderr, 1, "division by zero"));
}
