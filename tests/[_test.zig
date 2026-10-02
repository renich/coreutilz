const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "[ bracket basic execution" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "[");
    defer allocator.free(bin);

    var res1 = try ctx.runCommand(&[_][]const u8{ bin, "1", "-eq", "1", "]" }, null);
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);

    var res2 = try ctx.runCommand(&[_][]const u8{ bin, "1", "-eq", "2", "]" }, null);
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 1), res2.exit_code);
}
