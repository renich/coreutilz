const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "realpath basic resolution" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "realpath");
    defer allocator.free(binary_path);

    try ctx.writeFile("testfile", "content");
    const tmp_path = try ctx.tmpPath("testfile");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Trim newline from stdout
    const stdout = std.mem.trim(u8, result.stdout, " \n\r\t");
    try testing.expectEqualStrings(tmp_path, stdout);
}

test "realpath -e (ensure exists)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "realpath");
    defer allocator.free(binary_path);

    const nonexistent = try ctx.tmpPath("nonexistent");
    defer allocator.free(nonexistent);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-e", nonexistent }, null);
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
}

test "realpath -m (missing ok)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "realpath");
    defer allocator.free(binary_path);

    const nonexistent = try ctx.tmpPath("nonexistent");
    defer allocator.free(nonexistent);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-m", nonexistent }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const stdout = std.mem.trim(u8, result.stdout, " \n\r\t");
    try testing.expectEqualStrings(nonexistent, stdout);
}

test "realpath symlink expansion" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "realpath");
    defer allocator.free(binary_path);

    try ctx.writeFile("target", "content");
    const target_path = try ctx.tmpPath("target");
    defer allocator.free(target_path);

    const link_path = try ctx.tmpPath("link");
    defer allocator.free(link_path);

    try std.fs.cwd().symLink(target_path, link_path, .{});

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, link_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const stdout = std.mem.trim(u8, result.stdout, " \n\r\t");
    try testing.expectEqualStrings(target_path, stdout);
}

test "realpath -s (no symlink expansion)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "realpath");
    defer allocator.free(binary_path);

    try ctx.writeFile("target", "content");
    const target_path = try ctx.tmpPath("target");
    defer allocator.free(target_path);

    const link_path = try ctx.tmpPath("link");
    defer allocator.free(link_path);

    try std.fs.cwd().symLink(target_path, link_path, .{});

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", link_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const stdout = std.mem.trim(u8, result.stdout, " \n\r\t");
    try testing.expectEqualStrings(link_path, stdout);
}

test "realpath --relative-to" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "realpath");
    defer allocator.free(binary_path);

    const base_dir = try ctx.tmpPath("base");
    defer allocator.free(base_dir);
    try std.fs.cwd().makeDir(base_dir);

    const target_file = try ctx.tmpPath("base/file");
    defer allocator.free(target_file);
    try ctx.writeFile("base/file", "content");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--relative-to", base_dir, target_file }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const stdout = std.mem.trim(u8, result.stdout, " \n\r\t");
    try testing.expectEqualStrings("file", stdout);
}

test "realpath --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "realpath");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "realpath -q (quiet)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "realpath");
    defer allocator.free(binary_path);

    const nonexistent = try ctx.tmpPath("nonexistent");
    defer allocator.free(nonexistent);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-q", nonexistent }, null);
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
    // Quiet should suppress error messages on stderr
    try testing.expectEqual(@as(usize, 0), result.stderr.len);
}

test "realpath --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "realpath");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "realpath"));
}
