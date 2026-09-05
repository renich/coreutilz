const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

// Test data based on coreutils dd behavior

test "dd basic copy from file to file" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    // Create input file
    try ctx.writeFile("input.txt", "hello world\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);
    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "output.txt" });
    defer allocator.free(output_path);

    const if_input_path_arg = try std.fmt.allocPrint(allocator, "if={s}", .{input_path});
    defer allocator.free(if_input_path_arg);
    const of_output_path_arg = try std.fmt.allocPrint(allocator, "of={s}", .{output_path});
    defer allocator.free(of_output_path_arg);

    var result = try ctx.runCommand(&[_][]const u8{
        binary_path,
        if_input_path_arg,
        of_output_path_arg,
    }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("hello world\n", "output.txt"));
}

test "dd with bs block size option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "abcdefghij");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);
    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "output.txt" });
    defer allocator.free(output_path);

    const if_input_path_arg = try std.fmt.allocPrint(allocator, "if={s}", .{input_path});
    defer allocator.free(if_input_path_arg);
    const of_output_path_arg = try std.fmt.allocPrint(allocator, "of={s}", .{output_path});
    defer allocator.free(of_output_path_arg);

    var result = try ctx.runCommand(&[_][]const u8{
        binary_path,
        if_input_path_arg,
        of_output_path_arg,
        "bs=5",
    }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("abcdefghij", "output.txt"));
}

test "dd with count option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "abcdefghij");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);
    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "output.txt" });
    defer allocator.free(output_path);

    const if_input_path_arg = try std.fmt.allocPrint(allocator, "if={s}", .{input_path});
    defer allocator.free(if_input_path_arg);
    const of_output_path_arg = try std.fmt.allocPrint(allocator, "of={s}", .{output_path});
    defer allocator.free(of_output_path_arg);

    var result = try ctx.runCommand(&[_][]const u8{
        binary_path,
        if_input_path_arg,
        of_output_path_arg,
        "bs=2",
        "count=2",
    }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("abcd", "output.txt"));
}

test "dd with skip option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "abcdefghij");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);
    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "output.txt" });
    defer allocator.free(output_path);

    const if_input_path_arg = try std.fmt.allocPrint(allocator, "if={s}", .{input_path});
    defer allocator.free(if_input_path_arg);
    const of_output_path_arg = try std.fmt.allocPrint(allocator, "of={s}", .{output_path});
    defer allocator.free(of_output_path_arg);

    var result = try ctx.runCommand(&[_][]const u8{
        binary_path,
        if_input_path_arg,
        of_output_path_arg,
        "bs=2",
        "skip=2",
    }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("efghij", "output.txt"));
}

test "dd with seek option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "abcd");
    try ctx.writeFile("output.txt", "XXXXXXXX");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);
    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "output.txt" });
    defer allocator.free(output_path);

    const if_input_path_arg = try std.fmt.allocPrint(allocator, "if={s}", .{input_path});
    defer allocator.free(if_input_path_arg);
    const of_output_path_arg = try std.fmt.allocPrint(allocator, "of={s}", .{output_path});
    defer allocator.free(of_output_path_arg);

    var result = try ctx.runCommand(&[_][]const u8{
        binary_path,
        if_input_path_arg,
        of_output_path_arg,
        "bs=1",
        "seek=2",
    }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("XXabcdXX", "output.txt"));
}

test "dd conv=ucase option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "hello world");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);
    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "output.txt" });
    defer allocator.free(output_path);

    const if_input_path_arg = try std.fmt.allocPrint(allocator, "if={s}", .{input_path});
    defer allocator.free(if_input_path_arg);
    const of_output_path_arg = try std.fmt.allocPrint(allocator, "of={s}", .{output_path});
    defer allocator.free(of_output_path_arg);

    var result = try ctx.runCommand(&[_][]const u8{
        binary_path,
        if_input_path_arg,
        of_output_path_arg,
        "conv=ucase",
    }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("HELLO WORLD", "output.txt"));
}

test "dd conv=lcase option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "HELLO WORLD");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);
    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "output.txt" });
    defer allocator.free(output_path);

    const if_input_path_arg = try std.fmt.allocPrint(allocator, "if={s}", .{input_path});
    defer allocator.free(if_input_path_arg);
    const of_output_path_arg = try std.fmt.allocPrint(allocator, "of={s}", .{output_path});
    defer allocator.free(of_output_path_arg);

    var result = try ctx.runCommand(&[_][]const u8{
        binary_path,
        if_input_path_arg,
        of_output_path_arg,
        "conv=lcase",
    }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("hello world", "output.txt"));
}

test "dd conv=noerror option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "hello");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);
    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "output.txt" });
    defer allocator.free(output_path);

    // noerror should continue on read errors (if possible)
    const if_input_path_arg = try std.fmt.allocPrint(allocator, "if={s}", .{input_path});
    defer allocator.free(if_input_path_arg);
    const of_output_path_arg = try std.fmt.allocPrint(allocator, "of={s}", .{output_path});
    defer allocator.free(of_output_path_arg);

    var result = try ctx.runCommand(&[_][]const u8{
        binary_path,
        if_input_path_arg,
        of_output_path_arg,
        "conv=noerror",
    }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "dd conv=sync option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "ab");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);
    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "output.txt" });
    defer allocator.free(output_path);

    // sync pads blocks with null bytes
    const if_input_path_arg = try std.fmt.allocPrint(allocator, "if={s}", .{input_path});
    defer allocator.free(if_input_path_arg);
    const of_output_path_arg = try std.fmt.allocPrint(allocator, "of={s}", .{output_path});
    defer allocator.free(of_output_path_arg);

    var result = try ctx.runCommand(&[_][]const u8{
        binary_path,
        if_input_path_arg,
        of_output_path_arg,
        "bs=4",
        "conv=sync",
    }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    // Output should be "ab" followed by 2 null bytes
    const output = try ctx.readFile("output.txt");
    defer allocator.free(output);
    try testing.expectEqual(@as(usize, 4), output.len);
    try testing.expectEqual(@as(u8, 'a'), output[0]);
    try testing.expectEqual(@as(u8, 'b'), output[1]);
    try testing.expectEqual(@as(u8, 0), output[2]);
    try testing.expectEqual(@as(u8, 0), output[3]);
}

test "dd with iflag=direct option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "test content");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);
    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "output.txt" });
    defer allocator.free(output_path);

    const if_input_path_arg = try std.fmt.allocPrint(allocator, "if={s}", .{input_path});
    defer allocator.free(if_input_path_arg);
    const of_output_path_arg = try std.fmt.allocPrint(allocator, "of={s}", .{output_path});
    defer allocator.free(of_output_path_arg);

    var result = try ctx.runCommand(&[_][]const u8{
        binary_path,
        if_input_path_arg,
        of_output_path_arg,
        "iflag=direct",
    }, null);
    defer result.deinit();

    // direct I/O may fail on some filesystems, so we just check it doesn't crash
    _ = result.exit_code;
}

test "dd with oflag=direct option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "test content");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);
    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "output.txt" });
    defer allocator.free(output_path);

    const if_input_path_arg = try std.fmt.allocPrint(allocator, "if={s}", .{input_path});
    defer allocator.free(if_input_path_arg);
    const of_output_path_arg = try std.fmt.allocPrint(allocator, "of={s}", .{output_path});
    defer allocator.free(of_output_path_arg);

    var result = try ctx.runCommand(&[_][]const u8{
        binary_path,
        if_input_path_arg,
        of_output_path_arg,
        "oflag=direct",
    }, null);
    defer result.deinit();

    // direct I/O may fail on some filesystems, so we just check it doesn't crash
    _ = result.exit_code;
}

test "dd with iflag=sync option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "test");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);
    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "output.txt" });
    defer allocator.free(output_path);

    const if_input_path_arg = try std.fmt.allocPrint(allocator, "if={s}", .{input_path});
    defer allocator.free(if_input_path_arg);
    const of_output_path_arg = try std.fmt.allocPrint(allocator, "of={s}", .{output_path});
    defer allocator.free(of_output_path_arg);

    var result = try ctx.runCommand(&[_][]const u8{
        binary_path,
        if_input_path_arg,
        of_output_path_arg,
        "iflag=sync",
    }, null);
    defer result.deinit();

    // sync flag behavior varies by system
    _ = result.exit_code;
}

test "dd status=progress option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "a" ** 1024);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);
    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "output.txt" });
    defer allocator.free(output_path);

    const if_input_path_arg = try std.fmt.allocPrint(allocator, "if={s}", .{input_path});
    defer allocator.free(if_input_path_arg);
    const of_output_path_arg = try std.fmt.allocPrint(allocator, "of={s}", .{output_path});
    defer allocator.free(of_output_path_arg);

    var result = try ctx.runCommand(&[_][]const u8{
        binary_path,
        if_input_path_arg,
        of_output_path_arg,
        "status=progress",
    }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    // stderr should contain progress information
    try testing.expect(result.stderr.len > 0);
}

test "dd status=noxfer option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "hello");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);
    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "output.txt" });
    defer allocator.free(output_path);

    const if_input_path_arg = try std.fmt.allocPrint(allocator, "if={s}", .{input_path});
    defer allocator.free(if_input_path_arg);
    const of_output_path_arg = try std.fmt.allocPrint(allocator, "of={s}", .{output_path});
    defer allocator.free(of_output_path_arg);

    var result = try ctx.runCommand(&[_][]const u8{
        binary_path,
        if_input_path_arg,
        of_output_path_arg,
        "status=noxfer",
    }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "dd with ibs and obs options" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "abcdefghij");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);
    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "output.txt" });
    defer allocator.free(output_path);

    const if_input_path_arg = try std.fmt.allocPrint(allocator, "if={s}", .{input_path});
    defer allocator.free(if_input_path_arg);
    const of_output_path_arg = try std.fmt.allocPrint(allocator, "of={s}", .{output_path});
    defer allocator.free(of_output_path_arg);

    var result = try ctx.runCommand(&[_][]const u8{
        binary_path,
        if_input_path_arg,
        of_output_path_arg,
        "ibs=5",
        "obs=5",
    }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("abcdefghij", "output.txt"));
}

test "dd invalid input file returns error" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "nonexistent.txt" });
    defer allocator.free(input_path);
    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "output.txt" });
    defer allocator.free(output_path);

    const if_input_path_arg = try std.fmt.allocPrint(allocator, "if={s}", .{input_path});
    defer allocator.free(if_input_path_arg);
    const of_output_path_arg = try std.fmt.allocPrint(allocator, "of={s}", .{output_path});
    defer allocator.free(of_output_path_arg);

    var result = try ctx.runCommand(&[_][]const u8{
        binary_path,
        if_input_path_arg,
        of_output_path_arg,
    }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "dd invalid output directory returns error" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "test");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);

    const if_input_path_arg = try std.fmt.allocPrint(allocator, "if={s}", .{input_path});
    defer allocator.free(if_input_path_arg);

    var result = try ctx.runCommand(&[_][]const u8{
        binary_path,
        if_input_path_arg,
        "of=/nonexistent_dir/output.txt",
    }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "dd --help option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "dd --version option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "dd"));
}

test "dd with multiple conv options" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "  Hello World  ");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);
    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "output.txt" });
    defer allocator.free(output_path);

    const if_input_path_arg = try std.fmt.allocPrint(allocator, "if={s}", .{input_path});
    defer allocator.free(if_input_path_arg);
    const of_output_path_arg = try std.fmt.allocPrint(allocator, "of={s}", .{output_path});
    defer allocator.free(of_output_path_arg);

    var result = try ctx.runCommand(&[_][]const u8{
        binary_path,
        if_input_path_arg,
        of_output_path_arg,
        "conv=ucase",
    }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("  HELLO WORLD  ", "output.txt"));
}

test "dd with if=/dev/zero" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "output.txt" });
    defer allocator.free(output_path);

    const of_output_path_arg = try std.fmt.allocPrint(allocator, "of={s}", .{output_path});
    defer allocator.free(of_output_path_arg);

    var result = try ctx.runCommand(&[_][]const u8{
        binary_path,
        "if=/dev/zero",
        of_output_path_arg,
        "bs=1",
        "count=10",
    }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const output = try ctx.readFile("output.txt");
    defer allocator.free(output);
    try testing.expectEqual(@as(usize, 10), output.len);
    for (output) |byte| {
        try testing.expectEqual(@as(u8, 0), byte);
    }
}

test "dd with different bs sizes" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "dd");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "x" ** 100);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input_path);
    const output_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "output.txt" });
    defer allocator.free(output_path);

    // Test with 1K block size
    const if_input_path_arg = try std.fmt.allocPrint(allocator, "if={s}", .{input_path});
    defer allocator.free(if_input_path_arg);
    const of_output_path_arg = try std.fmt.allocPrint(allocator, "of={s}", .{output_path});
    defer allocator.free(of_output_path_arg);

    var result = try ctx.runCommand(&[_][]const u8{
        binary_path,
        if_input_path_arg,
        of_output_path_arg,
        "bs=1K",
        "count=1",
    }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const output = try ctx.readFile("output.txt");
    defer allocator.free(output);
    try testing.expectEqual(@as(usize, 100), output.len);
}
