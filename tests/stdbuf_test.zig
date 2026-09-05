const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "stdbuf basic command execution" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "stdbuf");
    defer allocator.free(binary_path);

    // Run stdbuf -o0 echo hello
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-o0", "echo", "hello" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "hello"));
}

test "stdbuf -i (input buffering)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "stdbuf");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-iL", "cat" }, "input data\n");
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("input data\n", result.stdout);
}

test "stdbuf -e (error buffering)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "stdbuf");
    defer allocator.free(binary_path);

    // Using sh to produce stderr
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-e0", "sh", "-c", "echo error >&2" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "error"));
}

test "stdbuf modes (L, 0, size)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "stdbuf");
    defer allocator.free(binary_path);

    const modes = [_][]const u8{ "L", "0", "1024", "1M" };
    for (modes) |mode| {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-o", mode, "true" }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }
}

test "stdbuf invalid option" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "stdbuf");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-ox", "true" }, null);
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
}

test "stdbuf --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "stdbuf");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}
