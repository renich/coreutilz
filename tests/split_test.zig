const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "split basic (by lines)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "line1\nline2\nline3\nline4\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    // Default is 1000 lines, so we use -l 2 to see it work
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l", "2", input, "out" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    try testing.expect(try ctx.compareContent("line1\nline2\n", "outaa"));
    try testing.expect(try ctx.compareContent("line3\nline4\n", "outab"));
}

test "split -b (bytes)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "12345678");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-b", "3", input, "out" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    try testing.expect(try ctx.compareContent("123", "outaa"));
    try testing.expect(try ctx.compareContent("456", "outab"));
    try testing.expect(try ctx.compareContent("78", "outac"));
}

test "split -C (line bytes)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "line1\nline2\nline3\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    // Each line is 6 bytes. -C 10 should put one line per file if it doesn't want to break lines
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-C", "10", input, "out" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    try testing.expect(try ctx.compareContent("line1\n", "outaa"));
    try testing.expect(try ctx.compareContent("line2\n", "outab"));
    try testing.expect(try ctx.compareContent("line3\n", "outac"));
}

test "split -n (chunks)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "123456");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-n", "2", input, "out" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    try testing.expect(try ctx.compareContent("123", "outaa"));
    try testing.expect(try ctx.compareContent("456", "outab"));
}

test "split --numeric-suffixes" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "line1\nline2\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l", "1", "-d", input, "out" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    try testing.expect(try ctx.compareContent("line1\n", "out00"));
    try testing.expect(try ctx.compareContent("line2\n", "out01"));
}

test "split --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "split --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "split"));
}
