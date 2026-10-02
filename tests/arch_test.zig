const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "arch basic output matches uname -m" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin_arch = try getBinaryPath(allocator, "arch");
    defer allocator.free(bin_arch);

    const bin_uname = try getBinaryPath(allocator, "uname");
    defer allocator.free(bin_uname);

    var res_arch = try ctx.runCommand(&[_][]const u8{bin_arch}, null);
    defer res_arch.deinit();

    var res_uname = try ctx.runCommand(&[_][]const u8{ bin_uname, "-m" }, null);
    defer res_uname.deinit();

    try testing.expectEqual(@as(u8, 0), res_arch.exit_code);
    try testing.expectEqualStrings(res_uname.stdout, res_arch.stdout);
}

test "arch --help option" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "arch");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, "Usage:"));
}
