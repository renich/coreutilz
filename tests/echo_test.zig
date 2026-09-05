const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

// Ported from tests/misc/echo.sh

fn runEcho(allocator: std.mem.Allocator, ctx: *TestContext, args: []const []const u8, env: ?*const framework.EnvMap) !framework.CommandResult {
    const bin = try getBinaryPath(allocator, "echo");
    defer allocator.free(bin);
    const argv = try allocator.alloc([]const u8, 1 + args.len);
    defer allocator.free(argv);
    argv[0] = bin;
    for (args, 1..) |a, i| argv[i] = a;
    const cwd = try ctx.tmpPath(".");
    defer allocator.free(cwd);
    return ctx.runCommandInDir(argv, null, cwd, env);
}

test "echo: basic output with newline" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{"hello"}, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("hello\n", result.stdout);
}

test "echo -n: no trailing newline" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{ "-n", "hello" }, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("hello", result.stdout);
}

test "echo -e: \\x1b is ESC" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{ "-e", "\\x1b" }, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("\x1b\n", result.stdout);
}

test "echo -e: \\e is ESC" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{ "-e", "\\e" }, null);
    defer result.deinit();
    try testing.expectEqualStrings("\x1b\n", result.stdout);
}

test "echo -e: \\33 octal is ESC" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{ "-e", "\\33" }, null);
    defer result.deinit();
    try testing.expectEqualStrings("\x1b\n", result.stdout);
}

test "echo -e: \\033 octal is ESC" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{ "-e", "\\033" }, null);
    defer result.deinit();
    try testing.expectEqualStrings("\x1b\n", result.stdout);
}

test "echo -e: \\0033 four-digit octal is ESC" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{ "-e", "\\0033" }, null);
    defer result.deinit();
    try testing.expectEqualStrings("\x1b\n", result.stdout);
}

test "echo -e: incomplete \\x outputs literal \\x" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{ "-e", "\\x" }, null);
    defer result.deinit();
    try testing.expectEqualStrings("\\x\n", result.stdout);
}

test "echo: -- is always output literally" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{ "--", "foo" }, null);
    defer result.deinit();
    try testing.expectEqualStrings("-- foo\n", result.stdout);
}

test "echo -e: \\c stops processing at control-c escape" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{ "-e", "foo\n\\cbar" }, null);
    defer result.deinit();
    try testing.expectEqualStrings("foo\n", result.stdout);
}

test "echo: literal - is output" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{"-"}, null);
    defer result.deinit();
    try testing.expectEqualStrings("-\n", result.stdout);
}

test "echo -e: hex \\x4a..\\x4f are JKLMNO" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{ "-e", "\\x4a\\x4b\\x4c\\x4d\\x4e\\x4f" }, null);
    defer result.deinit();
    try testing.expectEqualStrings("JKLMNO\n", result.stdout);
}

test "echo -e: uppercase hex \\x4A..\\x4F are JKLMNO" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{ "-e", "\\x4A\\x4B\\x4C\\x4D\\x4E\\x4F" }, null);
    defer result.deinit();
    try testing.expectEqualStrings("JKLMNO\n", result.stdout);
}

test "echo -e: \\t is horizontal tab" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{ "-e", "a\\tb" }, null);
    defer result.deinit();
    try testing.expectEqualStrings("a\tb\n", result.stdout);
}

test "echo -e: \\n is newline" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{ "-e", "a\\nb" }, null);
    defer result.deinit();
    try testing.expectEqualStrings("a\nb\n", result.stdout);
}

test "echo -e: \\a is BEL (0x07)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{ "-e", "\\a" }, null);
    defer result.deinit();
    try testing.expectEqualStrings("\x07\n", result.stdout);
}

test "echo -e: \\b is backspace (0x08)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{ "-e", "\\b" }, null);
    defer result.deinit();
    try testing.expectEqualStrings("\x08\n", result.stdout);
}

test "echo -e: \\f is form feed (0x0c)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{ "-e", "\\f" }, null);
    defer result.deinit();
    try testing.expectEqualStrings("\x0c\n", result.stdout);
}

test "echo -e: \\r is carriage return (0x0d)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{ "-e", "\\r" }, null);
    defer result.deinit();
    try testing.expectEqualStrings("\r\n", result.stdout);
}

test "echo -e: \\v is vertical tab (0x0b)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{ "-e", "\\v" }, null);
    defer result.deinit();
    try testing.expectEqualStrings("\x0b\n", result.stdout);
}

test "echo --help exits 0 and prints usage" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{"--help"}, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "echo --version exits 0 and mentions echo" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();
    var result = try runEcho(allocator, &ctx, &.{"--version"}, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "echo"));
}
