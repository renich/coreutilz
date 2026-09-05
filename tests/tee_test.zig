const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "tee basic output to file and stdout" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tee");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const output_file = "out.txt";
    const full_output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, output_file });
    defer allocator.free(full_output_path);

    const input = "test data\n";
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, full_output_path }, input);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings(input, result.stdout);

    const file_content = try ctx.readFile(output_file);
    defer allocator.free(file_content);
    try testing.expectEqualStrings(input, file_content);
}

test "tee -a (append)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tee");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const output_file = "append.txt";
    const full_output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, output_file });
    defer allocator.free(full_output_path);

    try ctx.writeFile(output_file, "initial\n");

    const input = "appended\n";
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-a", full_output_path }, input);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const file_content = try ctx.readFile(output_file);
    defer allocator.free(file_content);
    try testing.expectEqualStrings("initial\nappended\n", file_content);
}

test "tee multiple files" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tee");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    const file1 = "f1.txt";
    const file2 = "f2.txt";
    const p1 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, file1 });
    defer allocator.free(p1);
    const p2 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, file2 });
    defer allocator.free(p2);

    const input = "multi file output\n";
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, p1, p2 }, input);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const c1 = try ctx.readFile(file1);
    defer allocator.free(c1);
    const c2 = try ctx.readFile(file2);
    defer allocator.free(c2);

    try testing.expectEqualStrings(input, c1);
    try testing.expectEqualStrings(input, c2);
}

test "tee -i (ignore interrupts)" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tee");
    defer allocator.free(binary_path);

    const input = "ignore interrupts\n";
    // We can't easily test the actual interruption, but we can test the flag is accepted
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-i" }, input);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings(input, result.stdout);
}

test "tee --help" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tee");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "tee --version" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "tee");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "tee"));
}
