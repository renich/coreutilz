const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

fn isRoot() bool {
    return std.os.linux.getuid() == 0;
}

test "mknod creates FIFO with type p" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mknod");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const fifo_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "mknod_fifo" });
    defer allocator.free(fifo_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, fifo_path, "p" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const fifo_z = try allocator.dupeZ(u8, fifo_path);
    defer allocator.free(fifo_z);
    var stx: std.os.linux.Statx = undefined;
    _ = std.os.linux.statx(std.posix.AT.FDCWD, fifo_z.ptr, 0, .{ .MODE = true }, &stx);
    try testing.expect((stx.mode & std.posix.S.IFMT) == std.posix.S.IFIFO);
}

test "mknod creates FIFO with -m mode" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mknod");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const fifo_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "mknod_mode_fifo" });
    defer allocator.free(fifo_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-m", "734", fifo_path, "p" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const fifo_z = try allocator.dupeZ(u8, fifo_path);
    defer allocator.free(fifo_z);
    var stx: std.os.linux.Statx = undefined;
    _ = std.os.linux.statx(std.posix.AT.FDCWD, fifo_z.ptr, 0, .{ .MODE = true }, &stx);
    try testing.expectEqual(@as(u32, 0o734), @as(u32, stx.mode) & 0o777);
}

test "mknod rejects type p with extra major minor operands" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mknod");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "dummy", "p", "1", "2" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "Fifos do not have major and minor device numbers") != null);
}

test "mknod rejects block device without major minor" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mknod");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "dummy", "b" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "Special files require major and minor device numbers") != null);
}

test "mknod rejects invalid device type" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mknod");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "dummy", "z" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "invalid device type") != null);
}

test "mknod rejects invalid major device number" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mknod");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "dummy", "c", "xyz", "1" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "invalid major device number") != null);
}

test "mknod create block device (root only)" {
    if (!isRoot()) return error.SkipZigTest;

    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mknod");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const dev_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "myblock" });
    defer allocator.free(dev_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, dev_path, "b", "1", "2" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const dev_z = try allocator.dupeZ(u8, dev_path);
    defer allocator.free(dev_z);
    var stx: std.os.linux.Statx = undefined;
    _ = std.os.linux.statx(std.posix.AT.FDCWD, dev_z.ptr, 0, .{ .MODE = true }, &stx);
    try testing.expect((stx.mode & std.posix.S.IFMT) == std.posix.S.IFBLK);
}

test "mknod create char device (root only)" {
    if (!isRoot()) return error.SkipZigTest;

    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mknod");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const dev_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "mychar" });
    defer allocator.free(dev_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, dev_path, "c", "1", "3" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const dev_char_z = try allocator.dupeZ(u8, dev_path);
    defer allocator.free(dev_char_z);
    var stx_char: std.os.linux.Statx = undefined;
    _ = std.os.linux.statx(std.posix.AT.FDCWD, dev_char_z.ptr, 0, .{ .MODE = true }, &stx_char);
    try testing.expect((stx_char.mode & std.posix.S.IFMT) == std.posix.S.IFCHR);
}

test "mknod --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mknod");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "mknod --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mknod");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "mknod"));
}
