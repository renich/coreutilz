const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "factor --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "factor");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, "Usage: factor"));
}

test "factor primes and composites" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "factor");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "1", "2", "7", "12", "100" }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, "1:\n"));
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, "2: 2\n"));
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, "7: 7\n"));
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, "12: 2 2 3\n"));
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, "100: 2 2 5 5\n"));
}

test "factor invalid number exits 1" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "factor");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "abc" }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 1), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stderr, 1, "not a valid positive integer"));
}
