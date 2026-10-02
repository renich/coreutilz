const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "mkfifo creates named pipe successfully" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mkfifo");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const fifo_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "my_fifo" });
    defer allocator.free(fifo_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, fifo_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const fifo_z = try allocator.dupeZ(u8, fifo_path);
    defer allocator.free(fifo_z);
    var stx: std.os.linux.Statx = undefined;
    _ = std.os.linux.statx(std.posix.AT.FDCWD, fifo_z.ptr, 0, .{ .MODE = true }, &stx);
    try testing.expect((stx.mode & std.posix.S.IFMT) == std.posix.S.IFIFO);
}

test "mkfifo with -m mode" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mkfifo");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const fifo_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "mode_fifo" });
    defer allocator.free(fifo_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-m", "0640", fifo_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const fifo_z = try allocator.dupeZ(u8, fifo_path);
    defer allocator.free(fifo_z);
    var stx: std.os.linux.Statx = undefined;
    _ = std.os.linux.statx(std.posix.AT.FDCWD, fifo_z.ptr, 0, .{ .MODE = true }, &stx);
    try testing.expectEqual(@as(u32, 0o640), @as(u32, stx.mode) & 0o777);
}

test "mkfifo rejects invalid permission bits like setuid" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mkfifo");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const fifo_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "bad_fifo" });
    defer allocator.free(fifo_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-m", "4755", fifo_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "mode must specify only file permission bits") != null);
}

test "mkfifo missing operand exits 1" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mkfifo");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{binary_path}, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "missing operand") != null);
}

test "mkfifo already existing file exits 1" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "mkfifo");
    defer allocator.free(binary_path);

    try ctx.writeFile("exists.txt", "hello");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "exists.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "cannot create fifo") != null);
}
