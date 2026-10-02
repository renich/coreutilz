const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "od -c -An character dump" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "od");
    defer allocator.free(bin);

    try ctx.writeFile("input.txt", "abc\n");
    const p = try ctx.tmpPath("input.txt");
    defer allocator.free(p);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-c", "-An", p }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("   a   b   c  \\n\n", res.stdout);
}

test "od -x hex dump" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "od");
    defer allocator.free(bin);

    try ctx.writeFile("input.txt", "ab");
    const p = try ctx.tmpPath("input.txt");
    defer allocator.free(p);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-x", p }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expect(res.stdout.len > 0);
}

test "od --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "od");
    defer allocator.free(bin);

    var res_h = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res_h.deinit();
    try testing.expectEqual(@as(u8, 0), res_h.exit_code);

    var res_v = try ctx.runCommand(&[_][]const u8{ bin, "--version" }, null);
    defer res_v.deinit();
    try testing.expectEqual(@as(u8, 0), res_v.exit_code);
}
