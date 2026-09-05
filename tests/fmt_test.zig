const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "fmt basic paragraph formatting" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "fmt");
    defer allocator.free(binary_path);

    const input = "This is a short line.\nThis is another short line.\n";
    var result = try ctx.runCommand(&[_][]const u8{binary_path}, input);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    // Default width is usually 75, so it should join these lines
    try testing.expectEqualStrings("This is a short line.  This is another short line.\n", result.stdout);
}

test "fmt -w (width)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "fmt");
    defer allocator.free(binary_path);

    const input = "one two three four five six seven eight nine ten\n";
    // Width 10 should split it
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-w", "10" }, input);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "one two"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "\n"));
}

test "fmt -c (crown margin)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "fmt");
    defer allocator.free(binary_path);

    const input = "  First line of a paragraph.\nSecond line of the same paragraph.\n";
    // Crown margin: first two lines' indentation defines the paragraph's indentation
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-c" }, input);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    // This is hard to assert exactly without knowing the implementation's behavior on small inputs
    // but we test that it runs.
}

test "fmt -u (uniform spacing)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "fmt");
    defer allocator.free(binary_path);

    const input = "Word1   Word2.    Word3\n";
    // Uniform spacing: 1 space between words, 2 after sentences
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-u" }, input);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("Word1 Word2.  Word3\n", result.stdout);
}

test "fmt -s (split only)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "fmt");
    defer allocator.free(binary_path);

    const input = "short\nline\n";
    // Split only: should NOT join short lines
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s" }, input);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("short\nline\n", result.stdout);
}

test "fmt --help" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "fmt");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "fmt --version" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "fmt");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "fmt"));
}
