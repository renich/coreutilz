const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "uname default output is Linux" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "uname");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{bin}, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("Linux\n", res.stdout);
}

test "uname -s, -m, -o, -a options" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "uname");
    defer allocator.free(bin);

    var res_s = try ctx.runCommand(&[_][]const u8{ bin, "-s" }, null);
    defer res_s.deinit();
    try testing.expectEqualStrings("Linux\n", res_s.stdout);

    var res_o = try ctx.runCommand(&[_][]const u8{ bin, "-o" }, null);
    defer res_o.deinit();
    try testing.expectEqualStrings("GNU/Linux\n", res_o.stdout);

    var res_m = try ctx.runCommand(&[_][]const u8{ bin, "-m" }, null);
    defer res_m.deinit();
    try testing.expect(res_m.stdout.len > 0);

    var res_a = try ctx.runCommand(&[_][]const u8{ bin, "-a" }, null);
    defer res_a.deinit();
    try testing.expect(std.mem.containsAtLeast(u8, res_a.stdout, 1, "Linux"));
    try testing.expect(std.mem.containsAtLeast(u8, res_a.stdout, 1, "GNU/Linux"));
}
