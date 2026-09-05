const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "paste basic merge" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "paste");
    defer allocator.free(binary_path);

    try ctx.writeFile("file1.txt", "1\n2\n");
    try ctx.writeFile("file2.txt", "a\nb\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const f1 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    defer allocator.free(f1);
    const f2 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2.txt" });
    defer allocator.free(f2);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, f1, f2 }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("1\ta\n2\tb\n", result.stdout);
}

test "paste -s (serial)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "paste");
    defer allocator.free(binary_path);

    try ctx.writeFile("file1.txt", "1\n2\n3\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const f1 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    defer allocator.free(f1);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", f1 }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("1\t2\t3\n", result.stdout);
}

test "paste -d (delimiters)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "paste");
    defer allocator.free(binary_path);

    try ctx.writeFile("file1.txt", "1\n2\n");
    try ctx.writeFile("file2.txt", "a\nb\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const f1 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    defer allocator.free(f1);
    const f2 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2.txt" });
    defer allocator.free(f2);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-d", ",", f1, f2 }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("1,a\n2,b\n", result.stdout);
}

test "paste multiple files" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "paste");
    defer allocator.free(binary_path);

    try ctx.writeFile("f1", "1\n");
    try ctx.writeFile("f2", "2\n");
    try ctx.writeFile("f3", "3\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const f1 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f1" });
    defer allocator.free(f1);
    const f2 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f2" });
    defer allocator.free(f2);
    const f3 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f3" });
    defer allocator.free(f3);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, f1, f2, f3 }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("1\t2\t3\n", result.stdout);
}

test "paste --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "paste");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "paste --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "paste");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "paste"));
}
