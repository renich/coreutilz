const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "who basic run" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "who");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{bin}, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
}

test "who -q count option" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "who");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-q" }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, "users="));
}

test "who am i shorthand" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "who");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "am", "i" }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
}
