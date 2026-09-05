const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "unexpand basic" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "unexpand");
    defer allocator.free(binary_path);

    // Default tab stop is 8, unexpand only initial blanks
    var result = try ctx.runCommand(&[_][]const u8{binary_path}, "        a\n");
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("\ta\n", result.stdout);
}

test "unexpand -t (tab stops)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "unexpand");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-t", "4" }, "    a\n");
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("\ta\n", result.stdout);
}

test "unexpand -a (all)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "unexpand");
    defer allocator.free(binary_path);

    // Unexpand all blanks, not just initial
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-a", "-t", "4" }, "    a   b\n");
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    // "   b" becomes "\tb" because "a" (1) + "   " (3) = 4 (tab stop)
    try testing.expectEqualStrings("\ta\tb\n", result.stdout);
}

test "unexpand --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "unexpand");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "unexpand --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "unexpand");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "unexpand"));
}
