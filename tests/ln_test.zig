const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "ln creates hard link" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ln");
    defer allocator.free(binary_path);

    try ctx.writeFile("target.txt", "hard link content");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "target.txt", "hardlink" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const linked_content = try ctx.readFile("hardlink");
    defer allocator.free(linked_content);
    try testing.expectEqualStrings("hard link content", linked_content);
}

test "ln -s creates symbolic link" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ln");
    defer allocator.free(binary_path);

    try ctx.writeFile("target.txt", "symlink content");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "target.txt", "symlink" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const linked_content = try ctx.readFile("symlink");
    defer allocator.free(linked_content);
    try testing.expectEqualStrings("symlink content", linked_content);
}

test "ln -s creates dangling symlink" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ln");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "nonexistent.txt", "dangling" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const tmp = try ctx.tmpPath(".");
    defer allocator.free(tmp);
    const link_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp, "dangling" });
    defer allocator.free(link_path);

    var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const len = try std.Io.Dir.cwd().readLink(std.Options.debug_io, link_path, &buf);
    const link_target = buf[0..len];
    try testing.expectEqualStrings("nonexistent.txt", link_target);
}

test "ln -f force overwrites existing file" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ln");
    defer allocator.free(binary_path);

    try ctx.writeFile("target.txt", "new content");
    try ctx.writeFile("existing.txt", "old content");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-f", "target.txt", "existing.txt" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const content = try ctx.readFile("existing.txt");
    defer allocator.free(content);
    try testing.expectEqualStrings("new content", content);
}

test "ln fails when destination exists without force" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ln");
    defer allocator.free(binary_path);

    try ctx.writeFile("target.txt", "target content");
    try ctx.writeFile("existing.txt", "existing content");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "target.txt", "existing.txt" }, null);
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
}

test "ln -v verbose output" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ln");
    defer allocator.free(binary_path);

    try ctx.writeFile("src.txt", "x\n");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-v", "src.txt", "dst.txt" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "dst.txt") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "src.txt") != null);
}

test "ln -sf symbolic force" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ln");
    defer allocator.free(binary_path);

    try ctx.writeFile("a.txt", "a");
    try ctx.writeFile("b.txt", "b");
    try ctx.makeSymlink("a.txt", "link");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-sf", "b.txt", "link" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const content = try ctx.readFile("link");
    defer allocator.free(content);
    try testing.expectEqualStrings("b", content);
}

test "ln without link_name uses basename of target" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ln");
    defer allocator.free(binary_path);

    const tmp = try ctx.tmpPath(".");
    defer allocator.free(tmp);

    try ctx.makeDir("srcdir");
    try ctx.writeFile("srcdir/base.txt", "content\n");

    const src_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp, "srcdir", "base.txt" });
    defer allocator.free(src_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, src_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(ctx.pathExists("base.txt"));
}

test "ln hard link fails with non-existent target" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ln");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "nonexistent.txt", "link" }, null);
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
}

test "ln missing operand exits 1" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ln");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{binary_path}, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expect(result.stderr.len > 0);
}

test "ln invalid option exits 1" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ln");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-Z" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "ln --help exits 0" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ln");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(result.stdout.len > 0);
}

test "ln --version exits 0" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ln");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(result.stdout.len > 0);
}
