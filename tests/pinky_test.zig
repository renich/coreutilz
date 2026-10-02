const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "pinky basic run" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "pinky");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{bin}, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
}

test "pinky -l root" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "pinky");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-l", "root" }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, "Login name: root"));
}

test "pinky invalid option diagnostics" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "pinky");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "--invalid-option" }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 1), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stderr, 1, "unrecognized option '--invalid-option'"));
}
