const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "uptime --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "uptime");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, "Usage: uptime"));

    var res_ver = try ctx.runCommand(&[_][]const u8{ bin, "--version" }, null);
    defer res_ver.deinit();
    try testing.expectEqual(@as(u8, 0), res_ver.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_ver.stdout, 1, "uptime (coreutilz)"));
}

test "uptime basic output" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "uptime");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{bin}, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, "up"));
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, "load average:"));
}

test "uptime -s since output" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "uptime");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-s" }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, "-"));
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, ":"));
}
