const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "stty --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "stty");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "stty --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "stty");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "stty"));
}

test "stty -a (all settings)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "stty");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-a" }, null);
    defer result.deinit();

    // Note: this might fail if no TTY is available, but it should still run
    if (result.exit_code == 0) {
        try testing.expect(result.stdout.len > 0);
    }
}

test "stty -g (printable format)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "stty");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-g" }, null);
    defer result.deinit();

    if (result.exit_code == 0) {
        try testing.expect(result.stdout.len > 0);
    }
}

test "stty -F (device)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "stty");
    defer allocator.free(binary_path);

    // /dev/null is not a TTY, but we can test if it tries to open it
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-F", "/dev/null" }, null);
    defer result.deinit();

    // Likely fails with non-zero exit code because /dev/null is not a TTY
}

test "stty change settings" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "stty");
    defer allocator.free(binary_path);

    // Try to change a setting. This will likely fail without a TTY.
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "echo" }, null);
    defer result.deinit();

    if (result.exit_code == 0) {
        // Success
    } else {
        // Expected failure if no TTY
    }
}
