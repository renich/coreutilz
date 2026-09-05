const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "timeout basic duration" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "timeout");
    defer allocator.free(binary_path);

    // timeout 0.1 sleep 1 should exit with 124
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "0.1", "sleep", "1" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 124), result.exit_code);
}

test "timeout -s signal" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "timeout");
    defer allocator.free(binary_path);

    // timeout -s SIGINT 0.1 sleep 1 should exit with 124
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "INT", "0.1", "sleep", "1" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 124), result.exit_code);
}

test "timeout -k kill-after" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "timeout");
    defer allocator.free(binary_path);

    // timeout -k 0.1 0.1 sleep 1
    // This is hard to test exactly without more complex logic,
    // but we can at least check if it accepts the arguments.
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-k", "0.2", "0.1", "sleep", "1" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 124), result.exit_code);
}

test "timeout --foreground" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "timeout");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--foreground", "0.1", "sleep", "1" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 124), result.exit_code);
}

test "timeout --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "timeout");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "timeout --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "timeout");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "timeout"));
}
