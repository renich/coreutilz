const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

fn expectExpr(ctx: *TestContext, binary_path: []const u8, args: []const []const u8, expected_stdout: []const u8, expected_exit_code: u8) !void {
    var full_args: std.ArrayList([]const u8) = .{};
    defer full_args.deinit(ctx.allocator);
    try full_args.append(ctx.allocator, binary_path);
    try full_args.appendSlice(ctx.allocator, args);

    var result = try ctx.runCommand(full_args.items, null);
    defer result.deinit();

    try testing.expectEqual(expected_exit_code, result.exit_code);
    try testing.expectEqualStrings(expected_stdout, result.stdout);
}

test "expr arithmetic" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const binary_path = try getBinaryPath(allocator, "expr");
    defer allocator.free(binary_path);

    try expectExpr(&ctx, binary_path, &[_][]const u8{ "1", "+", "1" }, "2\n", 0);
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "5", "-", "3" }, "2\n", 0);
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "3", "*", "4" }, "12\n", 0);
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "10", "/", "2" }, "5\n", 0);
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "10", "%", "3" }, "1\n", 0);

    // Result is 0, exit code should be 1
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "1", "-", "1" }, "0\n", 1);
}

test "expr comparisons" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const binary_path = try getBinaryPath(allocator, "expr");
    defer allocator.free(binary_path);

    try expectExpr(&ctx, binary_path, &[_][]const u8{ "1", "=", "1" }, "1\n", 0);
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "1", "=", "2" }, "0\n", 1);
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "1", "!=", "2" }, "1\n", 0);
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "2", "!=", "2" }, "0\n", 1);
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "1", "<", "2" }, "1\n", 0);
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "2", "<", "1" }, "0\n", 1);
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "2", ">", "1" }, "1\n", 0);
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "1", ">", "2" }, "0\n", 1);
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "1", "<=", "1" }, "1\n", 0);
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "2", "<=", "1" }, "0\n", 1);
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "1", ">=", "1" }, "1\n", 0);
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "1", ">=", "2" }, "0\n", 1);
}

test "expr regex match" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const binary_path = try getBinaryPath(allocator, "expr");
    defer allocator.free(binary_path);

    try expectExpr(&ctx, binary_path, &[_][]const u8{ "hello", ":", "he" }, "2\n", 0);
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "hello", ":", ".*" }, "5\n", 0);
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "hello", ":", "h\\(e\\)llo" }, "e\n", 0);

    // No match
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "hello", ":", "x" }, "0\n", 1);
}

test "expr length" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const binary_path = try getBinaryPath(allocator, "expr");
    defer allocator.free(binary_path);

    try expectExpr(&ctx, binary_path, &[_][]const u8{ "length", "hello" }, "5\n", 0);
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "length", "" }, "0\n", 1);
}

test "expr index" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const binary_path = try getBinaryPath(allocator, "expr");
    defer allocator.free(binary_path);

    try expectExpr(&ctx, binary_path, &[_][]const u8{ "index", "hello", "e" }, "2\n", 0);
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "index", "hello", "o" }, "5\n", 0);
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "index", "hello", "x" }, "0\n", 1);
}

test "expr substr" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const binary_path = try getBinaryPath(allocator, "expr");
    defer allocator.free(binary_path);

    try expectExpr(&ctx, binary_path, &[_][]const u8{ "substr", "hello", "2", "3" }, "ell\n", 0);
    try expectExpr(&ctx, binary_path, &[_][]const u8{ "substr", "hello", "6", "1" }, "\n", 1);
}

test "expr --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    const binary_path = try getBinaryPath(allocator, "expr");
    defer allocator.free(binary_path);

    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
    }

    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "expr"));
    }
}
