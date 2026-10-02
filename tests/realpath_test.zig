const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "realpath --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "realpath");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, "Usage: realpath"));
}

test "realpath existing directory" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "realpath");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "." }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expect(res.stdout.len > 0);
    try testing.expect(res.stdout[0] == '/');
}

test "realpath -m canonicalize missing" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "realpath");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-m", "/tmp/nonexistent_xyz_123/foo/bar" }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, "/tmp/nonexistent_xyz_123/foo/bar"));
}

test "realpath nonexistent without -m fails" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "realpath");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "/tmp/nonexistent_xyz_123/foo/bar" }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 1), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stderr, 1, "No such file or directory"));
}
