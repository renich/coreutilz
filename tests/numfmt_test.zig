const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "numfmt --to=si scaling" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "numfmt");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "--to=si", "2000" }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("2.0k\n", res.stdout);
}

test "numfmt --to=iec and --from=iec" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "numfmt");
    defer allocator.free(bin);

    var res_to = try ctx.runCommand(&[_][]const u8{ bin, "--to=iec", "1024" }, null);
    defer res_to.deinit();
    try testing.expectEqual(@as(u8, 0), res_to.exit_code);
    try testing.expectEqualStrings("1.0K\n", res_to.stdout);

    var res_from = try ctx.runCommand(&[_][]const u8{ bin, "--from=iec", "1K" }, null);
    defer res_from.deinit();
    try testing.expectEqual(@as(u8, 0), res_from.exit_code);
    try testing.expectEqualStrings("1024\n", res_from.stdout);
}

test "numfmt --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "numfmt");
    defer allocator.free(bin);

    var res_h = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res_h.deinit();
    try testing.expectEqual(@as(u8, 0), res_h.exit_code);

    var res_v = try ctx.runCommand(&[_][]const u8{ bin, "--version" }, null);
    defer res_v.deinit();
    try testing.expectEqual(@as(u8, 0), res_v.exit_code);
}
