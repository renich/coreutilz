const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "expand default 8-column tabs" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "expand");
    defer allocator.free(bin);

    try ctx.writeFile("input.txt", "a\tb\n");
    const p = try ctx.tmpPath("input.txt");
    defer allocator.free(p);

    var res = try ctx.runCommand(&[_][]const u8{ bin, p }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("a       b\n", res.stdout);
}

test "expand custom tabs and initial only" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "expand");
    defer allocator.free(bin);

    try ctx.writeFile("input.txt", "\ta\tb\n");
    const p = try ctx.tmpPath("input.txt");
    defer allocator.free(p);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-t", "3", "-i", p }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("   a\tb\n", res.stdout);
}

test "expand --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "expand");
    defer allocator.free(bin);

    var res_h = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res_h.deinit();
    try testing.expectEqual(@as(u8, 0), res_h.exit_code);

    var res_v = try ctx.runCommand(&[_][]const u8{ bin, "--version" }, null);
    defer res_v.deinit();
    try testing.expectEqual(@as(u8, 0), res_v.exit_code);
}
