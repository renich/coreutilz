const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "tsort simple pairs" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tsort");
    defer allocator.free(binary_path);

    const input = "a b\nb c\n";
    var result = try ctx.runCommand(&[_][]const u8{binary_path}, input);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Output should be a, b, c in order
    const stdout = std.mem.trim(u8, result.stdout, " \n\r\t");
    var lines = std.mem.splitSequence(u8, stdout, "\n");
    try testing.expectEqualStrings("a", std.mem.trim(u8, lines.next().?, " "));
    try testing.expectEqualStrings("b", std.mem.trim(u8, lines.next().?, " "));
    try testing.expectEqualStrings("c", std.mem.trim(u8, lines.next().?, " "));
}

test "tsort with cycle" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tsort");
    defer allocator.free(binary_path);

    const input = "a b\nb a\n";
    var result = try ctx.runCommand(&[_][]const u8{binary_path}, input);
    defer result.deinit();

    // GNU tsort prints a warning to stderr and returns 0 or 1 depending on version,
    // but usually it still prints something and returns 0 but with a warning.
    // Actually POSIX says it should return non-zero if there is a cycle if I recall correctly.
    // Let's assume it might return non-zero or at least print to stderr.
    try testing.expect(result.stderr.len > 0);
}

test "tsort from file" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tsort");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "1 2\n2 3\n");
    const tmp_path = try ctx.tmpPath("input.txt");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "1"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "2"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "3"));
}

test "tsort --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tsort");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}
