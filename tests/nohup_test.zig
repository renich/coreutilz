const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "nohup basic command execution" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nohup");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "echo", "hello" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("hello\n", result.stdout);
}

test "nohup ignores SIGHUP" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nohup");
    defer allocator.free(binary_path);

    // Run a command that waits
    var child = try std.process.spawn(std.testing.io, .{
        .argv = &[_][]const u8{ binary_path, "sleep", "60" },
    });
    defer child.kill(std.testing.io);

    // Send SIGHUP to the nohup process
    std.posix.kill(child.id.?, std.posix.SIG.HUP) catch {};

    // Give it a moment
    _ = std.posix.poll(&.{}, 100) catch {};

    // Check if it's still running (kill with 0 signal)
    const alive = std.os.linux.syscall2(.kill, @bitCast(@as(isize, child.id.?)), 0) == 0;
    try testing.expect(alive);
}

fn openPtyPair() ?struct { ptmx: std.posix.fd_t, pts: std.posix.fd_t } {
    const ptmx = std.posix.openat(std.posix.AT.FDCWD, "/dev/ptmx", .{ .ACCMODE = .RDWR }, 0) catch return null;
    _ = std.os.linux.ioctl(ptmx, std.os.linux.T.IOCSPTLCK, @intFromPtr(&@as(c_int, 0)));
    var pty_num: c_int = 0;
    _ = std.os.linux.ioctl(ptmx, std.os.linux.T.IOCGPTN, @intFromPtr(&pty_num));
    var pts_buf: [64]u8 = undefined;
    const pts_name = std.fmt.bufPrintZ(&pts_buf, "/dev/pts/{d}", .{pty_num}) catch {
        _ = std.os.linux.close(ptmx);
        return null;
    };
    const pts = std.posix.openat(std.posix.AT.FDCWD, pts_name, .{ .ACCMODE = .RDWR }, 0) catch {
        _ = std.os.linux.close(ptmx);
        return null;
    };
    return .{ .ptmx = ptmx, .pts = pts };
}

test "nohup redirects to nohup.out" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nohup");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    const pty = openPtyPair() orelse return;
    defer {
        _ = std.os.linux.close(pty.ptmx);
        _ = std.os.linux.close(pty.pts);
    }

    var child = try std.process.spawn(std.testing.io, .{
        .argv = &[_][]const u8{ binary_path, "echo", "test-nohup-out" },
        .cwd = .{ .path = tmp_path },
        .stdout = .{ .file = .{ .handle = pty.pts, .flags = .{ .nonblocking = false } } },
        .stderr = .ignore,
    });
    _ = try child.wait(std.testing.io);

    const content = try ctx.readFile("nohup.out");
    defer allocator.free(content);

    try testing.expect(std.mem.containsAtLeast(u8, content, 1, "test-nohup-out"));
}

test "nohup with existing output file" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nohup");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    try ctx.writeFile("nohup.out", "existing\n");

    const pty = openPtyPair() orelse return;
    defer {
        _ = std.os.linux.close(pty.ptmx);
        _ = std.os.linux.close(pty.pts);
    }

    var child = try std.process.spawn(std.testing.io, .{
        .argv = &[_][]const u8{ binary_path, "echo", "appended" },
        .cwd = .{ .path = tmp_path },
        .stdout = .{ .file = .{ .handle = pty.pts, .flags = .{ .nonblocking = false } } },
        .stderr = .ignore,
    });
    _ = try child.wait(std.testing.io);

    const content = try ctx.readFile("nohup.out");
    defer allocator.free(content);

    try testing.expect(std.mem.containsAtLeast(u8, content, 1, "existing"));
    try testing.expect(std.mem.containsAtLeast(u8, content, 1, "appended"));
}

test "nohup --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nohup");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "nohup --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nohup");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "nohup"));
}
