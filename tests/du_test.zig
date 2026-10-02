const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "du basic directory usage" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    try ctx.makeDir("a");
    try ctx.makeDir("a/b");
    try ctx.makeDir("a/b/c");
    try ctx.writeFile("a/b/f1.txt", "hello");
    try ctx.writeFile("a/f2.txt", "world");

    const binary_path = try getBinaryPath(allocator, "du");
    defer allocator.free(binary_path);

    const a_path = try ctx.tmpPath("a");
    defer allocator.free(a_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, a_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "a/b/c") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "a/b") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, a_path) != null);
}

test "du -s summarize only" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    try ctx.makeDir("dir1");
    try ctx.makeDir("dir1/sub");
    try ctx.writeFile("dir1/sub/f.txt", "content");

    const binary_path = try getBinaryPath(allocator, "du");
    defer allocator.free(binary_path);

    const dir1_path = try ctx.tmpPath("dir1");
    defer allocator.free(dir1_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", dir1_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "dir1/sub") == null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, dir1_path) != null);
}

test "du -a all files" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    try ctx.makeDir("d");
    try ctx.makeDir("d/sub");
    try ctx.writeFile("d/sub/f1.txt", "file1");
    try ctx.writeFile("d/f2.txt", "file2");

    const binary_path = try getBinaryPath(allocator, "du");
    defer allocator.free(binary_path);

    const d_path = try ctx.tmpPath("d");
    defer allocator.free(d_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-a", d_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "f1.txt") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "f2.txt") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "d/sub") != null);
}

test "du -c grand total" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    try ctx.writeFile("f1", "12345");
    try ctx.writeFile("f2", "67890");

    const binary_path = try getBinaryPath(allocator, "du");
    defer allocator.free(binary_path);

    const f1_path = try ctx.tmpPath("f1");
    defer allocator.free(f1_path);
    const f2_path = try ctx.tmpPath("f2");
    defer allocator.free(f2_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-c", f1_path, f2_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "\ttotal\n") != null);
}

test "du -b and --apparent-size" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    try ctx.writeFile("app.txt", "1234567890");

    const binary_path = try getBinaryPath(allocator, "du");
    defer allocator.free(binary_path);

    const app_path = try ctx.tmpPath("app.txt");
    defer allocator.free(app_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-b", app_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.startsWith(u8, result.stdout, "10\t"));
}

test "du -d max depth" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    try ctx.makeDir("top");
    try ctx.makeDir("top/l1");
    try ctx.makeDir("top/l1/l2");

    const binary_path = try getBinaryPath(allocator, "du");
    defer allocator.free(binary_path);

    const top_path = try ctx.tmpPath("top");
    defer allocator.free(top_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-d", "1", top_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "top/l1") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "l2") == null);
}

test "du --exclude" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    try ctx.makeDir("root");
    try ctx.makeDir("root/sub");
    try ctx.makeDir("root/ignore_me");
    try ctx.writeFile("root/sub/f.txt", "hi");
    try ctx.writeFile("root/ignore_me/bad.txt", "no");

    const binary_path = try getBinaryPath(allocator, "du");
    defer allocator.free(binary_path);

    const root_path = try ctx.tmpPath("root");
    defer allocator.free(root_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-a", "--exclude=ignore_me", root_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "sub") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "ignore_me") == null);
}

test "du --inodes" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    try ctx.makeDir("inodir");
    try ctx.writeFile("inodir/f1", "a");
    try ctx.writeFile("inodir/f2", "b");

    const binary_path = try getBinaryPath(allocator, "du");
    defer allocator.free(binary_path);

    const inodir_path = try ctx.tmpPath("inodir");
    defer allocator.free(inodir_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--inodes", inodir_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.startsWith(u8, result.stdout, "3\t"));
}

test "du --files0-from" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    try ctx.writeFile("f0_1", "foo");
    try ctx.writeFile("f0_2", "bar");

    const f1_path = try ctx.tmpPath("f0_1");
    defer allocator.free(f1_path);
    const f2_path = try ctx.tmpPath("f0_2");
    defer allocator.free(f2_path);

    var f0_content = std.ArrayList(u8).empty;
    defer f0_content.deinit(allocator);
    try f0_content.appendSlice(allocator, f1_path);
    try f0_content.append(allocator, 0);
    try f0_content.appendSlice(allocator, f2_path);
    try f0_content.append(allocator, 0);

    try ctx.writeFile("list0", f0_content.items);
    const list0_path = try ctx.tmpPath("list0");
    defer allocator.free(list0_path);

    const f0_arg = try std.fmt.allocPrint(allocator, "--files0-from={s}", .{list0_path});
    defer allocator.free(f0_arg);

    const binary_path = try getBinaryPath(allocator, "du");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, f0_arg }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, f1_path) != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, f2_path) != null);
}

test "du -0 null termination" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    try ctx.writeFile("null_test", "xyz");

    const binary_path = try getBinaryPath(allocator, "du");
    defer allocator.free(binary_path);

    const p = try ctx.tmpPath("null_test");
    defer allocator.free(p);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-0", p }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.endsWith(u8, result.stdout, "\x00"));
}

test "du --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "du");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "du --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "du");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "du"));
}
