const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

fn isRoot() bool {
    return std.os.linux.getuid() == 0;
}

test "mknod create FIFO" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mknod");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const fifo_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "myfifo" });
    defer allocator.free(fifo_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, fifo_path, "p" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify it's a FIFO
    const stat = try std.fs.cwd().statFile(fifo_path);
    // In Zig 0.13.0, kind is std.fs.File.Kind
    try testing.expect(stat.kind == .named_pipe);
}

test "mknod with mode" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mknod");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const fifo_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "myfifo2" });
    defer allocator.free(fifo_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-m", "600", fifo_path, "p" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const stat = try std.fs.cwd().statFile(fifo_path);
    // Check mode (permissions)
    try testing.expectEqual(@as(u32, 0o600), @as(u32, @intCast(stat.mode & 0o777)));
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

    // Create a block device with major 1, minor 2
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, dev_path, "b", "1", "2" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const stat = try std.fs.cwd().statFile(dev_path);
    try testing.expect(stat.kind == .block_device);
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

    // Create a char device with major 1, minor 3 (usually /dev/null)
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, dev_path, "c", "1", "3" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const stat = try std.fs.cwd().statFile(dev_path);
    try testing.expect(stat.kind == .character_device);
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
