const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "kill -l lists signals" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "kill");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain common signal names
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "HUP") or std.mem.containsAtLeast(u8, result.stdout, 1, "1"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "KILL") or std.mem.containsAtLeast(u8, result.stdout, 1, "9"));
}

test "kill process with default signal (TERM)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "kill");
    defer allocator.free(binary_path);

    // Start a process that will wait
    var child = std.process.Child.init(&[_][]const u8{ "sleep", "60" }, allocator);
    try child.spawn();

    const pid = child.id;
    var pid_buf: [16]u8 = undefined;
    const pid_str = try std.fmt.bufPrint(&pid_buf, "{}", .{pid});

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, pid_str }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Wait for the child to be killed
    const term = try child.wait();
    switch (term) {
        .Signal => |sig| try testing.expectEqual(@as(u32, std.os.linux.SIG.TERM), @as(u32, @intCast(sig))),
        else => {}, // Some platforms might return differently
    }
}

test "kill process with -s SIGNAL" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "kill");
    defer allocator.free(binary_path);

    var child = std.process.Child.init(&[_][]const u8{ "sleep", "60" }, allocator);
    try child.spawn();

    const pid = child.id;
    var pid_buf: [16]u8 = undefined;
    const pid_str = try std.fmt.bufPrint(&pid_buf, "{}", .{pid});

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "KILL", pid_str }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const term = try child.wait();
    switch (term) {
        .Signal => |sig| try testing.expectEqual(@as(u32, std.os.linux.SIG.KILL), @as(u32, @intCast(sig))),
        else => {},
    }
}

test "kill process with -n SIG_NUM" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "kill");
    defer allocator.free(binary_path);

    var child = std.process.Child.init(&[_][]const u8{ "sleep", "60" }, allocator);
    try child.spawn();

    const pid = child.id;
    var pid_buf: [16]u8 = undefined;
    const pid_str = try std.fmt.bufPrint(&pid_buf, "{}", .{pid});

    // 9 is SIGKILL
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-n", "9", pid_str }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const term = try child.wait();
    switch (term) {
        .Signal => |sig| try testing.expectEqual(@as(u32, 9), @as(u32, @intCast(sig))),
        else => {},
    }
}

test "kill process with --signal" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "kill");
    defer allocator.free(binary_path);

    var child = std.process.Child.init(&[_][]const u8{ "sleep", "60" }, allocator);
    try child.spawn();

    const pid = child.id;
    var pid_buf: [16]u8 = undefined;
    const pid_str = try std.fmt.bufPrint(&pid_buf, "{}", .{pid});

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--signal", "INT", pid_str }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const term = try child.wait();
    switch (term) {
        .Signal => |sig| try testing.expectEqual(@as(u32, std.os.linux.SIG.INT), @as(u32, @intCast(sig))),
        else => {},
    }
}

test "kill --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "kill");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "kill --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "kill");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "kill"));
}
