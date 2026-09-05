const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "install basic copy" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "install");
    defer allocator.free(binary_path);

    try ctx.writeFile("source.txt", "hello");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const src = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "source.txt" });
    defer allocator.free(src);
    const dest = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "dest.txt" });
    defer allocator.free(dest);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, src, dest }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("hello", "dest.txt"));
}

test "install -d (create directories)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "install");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "new_dir/sub_dir" });
    defer allocator.free(dir_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-d", dir_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    var dir = try std.fs.openDirAbsolute(dir_path, .{});
    dir.close();
}

test "install -m (mode)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "install");
    defer allocator.free(binary_path);

    try ctx.writeFile("source.txt", "hello");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const src = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "source.txt" });
    defer allocator.free(src);
    const dest = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "dest.txt" });
    defer allocator.free(dest);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-m", "644", src, dest }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const stat = try std.fs.cwd().statFile(dest);
    try testing.expectEqual(@as(u32, 0o644), @as(u32, @truncate(stat.mode)) & 0o777);
}

test "install -o (owner)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "install");
    defer allocator.free(binary_path);

    try ctx.writeFile("source.txt", "hello");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const src = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "source.txt" });
    defer allocator.free(src);
    const dest = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "dest.txt" });
    defer allocator.free(dest);

    // Get current user to avoid failure if not root
    var whoami = try ctx.runCommand(&[_][]const u8{"whoami"}, null);
    defer whoami.deinit();
    const user = std.mem.trim(u8, whoami.stdout, " \n\r\t");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-o", user, src, dest }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "install -g (group)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "install");
    defer allocator.free(binary_path);

    try ctx.writeFile("source.txt", "hello");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const src = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "source.txt" });
    defer allocator.free(src);
    const dest = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "dest.txt" });
    defer allocator.free(dest);

    // Get current group
    var id_g = try ctx.runCommand(&[_][]const u8{ "id", "-gn" }, null);
    defer id_g.deinit();
    const group = std.mem.trim(u8, id_g.stdout, " \n\r\t");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-g", group, src, dest }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "install -p (preserve timestamps)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "install");
    defer allocator.free(binary_path);

    try ctx.writeFile("source.txt", "hello");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const src = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "source.txt" });
    defer allocator.free(src);
    const dest = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "dest.txt" });
    defer allocator.free(dest);

    const src_stat = try std.fs.cwd().statFile(src);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-p", src, dest }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const dest_stat = try std.fs.cwd().statFile(dest);
    try testing.expectEqual(src_stat.mtime, dest_stat.mtime);
}

test "install --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "install");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "install --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "install");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "install"));
}
