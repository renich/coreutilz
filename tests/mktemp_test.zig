const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "mktemp --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "mktemp");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, "Usage: mktemp"));
}

test "mktemp -u dry run" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "mktemp");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-u" }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expect(std.mem.startsWith(u8, res.stdout, "/tmp/tmp."));
}

test "mktemp creates actual file and deletes" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "mktemp");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{bin}, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);

    const path = std.mem.trim(u8, res.stdout, " \t\r\n");
    // Verify file exists
    const f = try std.Io.Dir.openFileAbsolute(std.testing.io, path, .{});
    f.close(std.testing.io);

    // Clean up
    var p_z: [std.fs.max_path_bytes]u8 = undefined;
    const pz = try std.fmt.bufPrintZ(&p_z, "{s}", .{path});
    _ = std.c.unlink(pz.ptr);
}

test "mktemp too few X's" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "mktemp");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "foo.XX" }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 1), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stderr, 1, "too few X's"));
}
