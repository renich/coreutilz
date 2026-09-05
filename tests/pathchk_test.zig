const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "pathchk basic usage" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "pathchk");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "valid_path" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "pathchk -p (POSIX portability)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "pathchk");
    defer allocator.free(binary_path);

    // Test a very long path (POSIX limit is 255 for name, 4096 for path usually)
    // Here we just test something that should pass
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-p", "a/b/c" }, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Test with invalid POSIX character (e.g. space is allowed in some but discouraged in -p)
    // Actually -p checks against the POSIX portable filename character set: [A-Za-z0-9._-]
    var result_invalid = try ctx.runCommand(&[_][]const u8{ binary_path, "-p", "path with spaces" }, null);
    defer result_invalid.deinit();
    try testing.expect(result_invalid.exit_code != 0);
}

test "pathchk -P (POSIX strict - empty names)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "pathchk");
    defer allocator.free(binary_path);

    // -P checks for empty names and leading hyphens
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-P", "a//b" }, null);
    defer result.deinit();
    try testing.expect(result.exit_code != 0);
}

test "pathchk multiple paths" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "pathchk");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "path1", "path2", "path3" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "pathchk with invalid characters" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "pathchk");
    defer allocator.free(binary_path);

    // NUL character is definitely invalid
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "path\x00with_nul" }, null);
    defer result.deinit();
    try testing.expect(result.exit_code != 0);
}

test "pathchk --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "pathchk");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "pathchk --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "pathchk");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "pathchk"));
}
