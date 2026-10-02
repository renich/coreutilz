const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "unexpand basic 8 spaces to tab" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "unexpand");
    defer allocator.free(bin);

    try ctx.writeFile("input.txt", "        hello\n");
    const p = try ctx.tmpPath("input.txt");
    defer allocator.free(p);

    var res = try ctx.runCommand(&[_][]const u8{ bin, p }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("\thello\n", res.stdout);
}

test "unexpand -a all spaces" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "unexpand");
    defer allocator.free(bin);

    try ctx.writeFile("input.txt", "w       y\n");
    const p = try ctx.tmpPath("input.txt");
    defer allocator.free(p);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-a", p }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("w\ty\n", res.stdout);
}

test "unexpand --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "unexpand");
    defer allocator.free(bin);

    var res_h = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res_h.deinit();
    try testing.expectEqual(@as(u8, 0), res_h.exit_code);

    var res_v = try ctx.runCommand(&[_][]const u8{ bin, "--version" }, null);
    defer res_v.deinit();
    try testing.expectEqual(@as(u8, 0), res_v.exit_code);
}
