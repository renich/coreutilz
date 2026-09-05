const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "dircolors print defaults" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dircolors");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-p" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should contain common keys like DIR, FILE, LINK
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "DIR"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "FILE"));
}

test "dircolors bourne shell output" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dircolors");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-b" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "LS_COLORS="));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "export LS_COLORS"));
}

test "dircolors csh output" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dircolors");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-c" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "setenv LS_COLORS"));
}

test "dircolors from file" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dircolors");
    defer allocator.free(binary_path);

    // Create a simple database file
    try ctx.writeFile("colors.db", "DIR 01;34\nFILE 00\n.txt 01;32\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const db_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "colors.db" });
    defer allocator.free(db_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, db_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "di=01;34"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "fi=00"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "*.txt=01;32"));
}

test "dircolors --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dircolors");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "dircolors --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dircolors");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "dircolors"));
}
