const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "truncate -s option (size)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "truncate");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "1234567890");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    // Shrink
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "5", file_path }, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);

    var content = try ctx.readFile("test.txt");
    defer allocator.free(content);
    try testing.expectEqual(@as(usize, 5), content.len);

    // Extend
    result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "10", file_path }, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);

    content = try ctx.readFile("test.txt");
    defer allocator.free(content);
    try testing.expectEqual(@as(usize, 10), content.len);
}

test "truncate -r option (reference)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "truncate");
    defer allocator.free(binary_path);

    try ctx.writeFile("ref.txt", "12345");
    try ctx.writeFile("test.txt", "1234567890");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const ref_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "ref.txt" });
    defer allocator.free(ref_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-r", ref_path, file_path }, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const content = try ctx.readFile("test.txt");
    defer allocator.free(content);
    try testing.expectEqual(@as(usize, 5), content.len);
}

test "truncate -c option (no create)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "truncate");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "nonexistent.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-c", "-s", "10", file_path }, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);

    _ = ctx.readFile("nonexistent.txt") catch |err| {
        try testing.expectEqual(error.FileNotFound, err);
        return;
    };
    try testing.expect(false);
}

test "truncate -o option (no fallocate)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "truncate");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "1234567890");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-o", "-s", "5", file_path }, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "truncate multiple files" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "truncate");
    defer allocator.free(binary_path);

    try ctx.writeFile("file1.txt", "1234567890");
    try ctx.writeFile("file2.txt", "1234567890");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file1_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file1.txt" });
    defer allocator.free(file1_path);
    const file2_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file2.txt" });
    defer allocator.free(file2_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "3", file1_path, file2_path }, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const content1 = try ctx.readFile("file1.txt");
    defer allocator.free(content1);
    try testing.expectEqual(@as(usize, 3), content1.len);

    const content2 = try ctx.readFile("file2.txt");
    defer allocator.free(content2);
    try testing.expectEqual(@as(usize, 3), content2.len);
}

test "truncate --help option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "truncate");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "truncate --version option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "truncate");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "truncate"));
}
