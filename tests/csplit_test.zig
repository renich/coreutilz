const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "csplit basic split by pattern" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "line1\nPATTERN\nline2\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, input_path, "/PATTERN/" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Check if files xx00 and xx01 are created
    const xx00_content = try ctx.readFile("xx00");
    defer allocator.free(xx00_content);
    try testing.expectEqualStrings("line1\n", xx00_content);

    const xx01_content = try ctx.readFile("xx01");
    defer allocator.free(xx01_content);
    try testing.expectEqualStrings("PATTERN\nline2\n", xx01_content);
}

test "csplit -n option (suffix digits)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "line1\nPATTERN\nline2\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-n", "3", input_path, "/PATTERN/" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const xx000_content = try ctx.readFile("xx000");
    defer allocator.free(xx000_content);
    try testing.expectEqualStrings("line1\n", xx000_content);
}

test "csplit -f option (prefix)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "line1\nPATTERN\nline2\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-f", "prefix", input_path, "/PATTERN/" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const prefix00_content = try ctx.readFile("prefix00");
    defer allocator.free(prefix00_content);
    try testing.expectEqualStrings("line1\n", prefix00_content);
}

test "csplit -b option (suffix format)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "line1\nPATTERN\nline2\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);

    // Using a format like %d.txt
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-b", "%d.txt", input_path, "/PATTERN/" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const xx0_txt_content = try ctx.readFile("xx0.txt");
    defer allocator.free(xx0_txt_content);
    try testing.expectEqualStrings("line1\n", xx0_txt_content);
}

test "csplit -k option (keep files)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "line1\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);

    // This should fail because the pattern is not found, but -k should keep xx00
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-k", input_path, "/NONEXISTENT/" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);

    // Check if xx00 exists
    const xx00_content = try ctx.readFile("xx00");
    defer allocator.free(xx00_content);
    try testing.expectEqualStrings("line1\n", xx00_content);
}

test "csplit --help option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "csplit --version option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "csplit"));
}
