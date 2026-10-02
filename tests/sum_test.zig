const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "sum --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "sum");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, "Usage: sum"));

    var res_ver = try ctx.runCommand(&[_][]const u8{ bin, "--version" }, null);
    defer res_ver.deinit();
    try testing.expectEqual(@as(u8, 0), res_ver.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_ver.stdout, 1, "sum (coreutilz)"));
}

test "sum basic bsd and sysv output" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "sum");
    defer allocator.free(bin);

    try ctx.writeFile("test.txt", "abc");

    var res_bsd = try ctx.runCommand(&[_][]const u8{ bin, "test.txt" }, null);
    defer res_bsd.deinit();
    try testing.expectEqual(@as(u8, 0), res_bsd.exit_code);
    try testing.expectEqualStrings("16556     1 test.txt\n", res_bsd.stdout);

    var res_sysv = try ctx.runCommand(&[_][]const u8{ bin, "-s", "test.txt" }, null);
    defer res_sysv.deinit();
    try testing.expectEqual(@as(u8, 0), res_sysv.exit_code);
    try testing.expectEqualStrings("294 1 test.txt\n", res_sysv.stdout);
}

test "sum stdin bsd and sysv output" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "sum");
    defer allocator.free(bin);

    var res_bsd = try ctx.runCommand(&[_][]const u8{bin}, "message digest");
    defer res_bsd.deinit();
    try testing.expectEqual(@as(u8, 0), res_bsd.exit_code);
    try testing.expectEqualStrings("26423     1\n", res_bsd.stdout);

    var res_sysv = try ctx.runCommand(&[_][]const u8{ bin, "--sysv" }, "message digest");
    defer res_sysv.deinit();
    try testing.expectEqual(@as(u8, 0), res_sysv.exit_code);
    try testing.expectEqualStrings("1413 1\n", res_sysv.stdout);
}
