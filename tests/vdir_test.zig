const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "vdir basic directory listing" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "vdir");
    defer allocator.free(binary_path);

    try ctx.writeFile("file1.txt", "content1\n");
    try ctx.writeFile("file2.txt", "content2\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    // vdir is like ls -l, so it should have permissions and filenames
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "file1.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "file2.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "-")); // Permission bit
}

test "vdir -a (all files)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "vdir");
    defer allocator.free(binary_path);

    try ctx.writeFile(".hidden", "hidden\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-a", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, ".hidden"));
}

test "vdir -C (columns)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "vdir");
    defer allocator.free(binary_path);

    try ctx.writeFile("a", "");
    try ctx.writeFile("b", "");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-C", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "vdir -x (across)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "vdir");
    defer allocator.free(binary_path);

    try ctx.writeFile("a", "");
    try ctx.writeFile("b", "");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-x", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "vdir --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "vdir");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "vdir"));
}

test "vdir --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "vdir");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}
