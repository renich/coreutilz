const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "readlink on symlink prints target" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "readlink");
    defer allocator.free(binary_path);

    try ctx.writeFile("target.txt", "content");
    try ctx.makeSymlink("target.txt", "link");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "link" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("target.txt\n", result.stdout);
}

test "readlink on regular file exits 1" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "readlink");
    defer allocator.free(binary_path);

    try ctx.writeFile("regular.txt", "content");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "regular.txt" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "readlink on nonexistent file exits 1" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "readlink");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "nonexistent" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "readlink -f canonicalizes path" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "readlink");
    defer allocator.free(binary_path);

    const tmp = try ctx.tmpPath(".");
    defer allocator.free(tmp);

    try ctx.writeFile("target.txt", "content");
    try ctx.makeSymlink("target.txt", "link");

    const link_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp, "link" });
    defer allocator.free(link_path);
    const expected = try std.fmt.allocPrint(allocator, "{s}/target.txt\n", .{tmp});
    defer allocator.free(expected);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-f", link_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings(expected, result.stdout);
}

test "readlink -e requires all components to exist" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "readlink");
    defer allocator.free(binary_path);

    const tmp = try ctx.tmpPath(".");
    defer allocator.free(tmp);
    const nonexistent = try std.fs.path.join(allocator, &[_][]const u8{ tmp, "nonexistent" });
    defer allocator.free(nonexistent);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-e", nonexistent }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "readlink -e on existing file succeeds" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "readlink");
    defer allocator.free(binary_path);

    const tmp = try ctx.tmpPath(".");
    defer allocator.free(tmp);

    try ctx.writeFile("real.txt", "content");
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp, "real.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-e", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.startsWith(u8, result.stdout, "/"));
}

test "readlink -m allows nonexistent path" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "readlink");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-m", "/nonexistent/path/file" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("/nonexistent/path/file\n", result.stdout);
}

test "readlink -n suppresses trailing newline" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "readlink");
    defer allocator.free(binary_path);

    const tmp = try ctx.tmpPath(".");
    defer allocator.free(tmp);

    try ctx.writeFile("target.txt", "content");
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp, "target.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-fn", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(!std.mem.endsWith(u8, result.stdout, "\n"));
}

test "readlink -q suppresses error on non-symlink" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "readlink");
    defer allocator.free(binary_path);

    try ctx.writeFile("regular.txt", "content");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-q", "regular.txt" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expectEqualStrings("", result.stderr);
}

test "readlink missing operand exits 1" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "readlink");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{binary_path}, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "readlink --help exits 0" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "readlink");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(result.stdout.len > 0);
}

test "readlink --version exits 0" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "readlink");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(result.stdout.len > 0);
}

test "readlink multiple files prints each target" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "readlink");
    defer allocator.free(binary_path);

    try ctx.writeFile("target1.txt", "1");
    try ctx.writeFile("target2.txt", "2");
    try ctx.makeSymlink("target1.txt", "link1");
    try ctx.makeSymlink("target2.txt", "link2");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "link1", "link2" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("target1.txt\ntarget2.txt\n", result.stdout);
}

test "readlink -z prints NUL delimited output" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "readlink");
    defer allocator.free(binary_path);

    try ctx.writeFile("target.txt", "content");
    try ctx.makeSymlink("target.txt", "link");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-z", "link" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("target.txt\x00", result.stdout);
}

test "readlink multiple files warns about -n" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "readlink");
    defer allocator.free(binary_path);

    try ctx.writeFile("target1.txt", "1");
    try ctx.writeFile("target2.txt", "2");
    try ctx.makeSymlink("target1.txt", "link1");
    try ctx.makeSymlink("target2.txt", "link2");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-n", "link1", "link2" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "ignoring --no-newline with multiple arguments"));
    try testing.expectEqualStrings("target1.txt\ntarget2.txt\n", result.stdout);
}
