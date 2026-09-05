const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "test file expressions" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "test");
    defer allocator.free(binary_path);

    try ctx.writeFile("file.txt", "content");
    try ctx.tmp_dir.dir.makeDir("dir");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file.txt" });
    defer allocator.free(file_path);
    const dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "dir" });
    defer allocator.free(dir_path);

    // -e (exists)
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-e", file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // -f (is file)
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-f", file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // -d (is directory)
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-d", dir_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // -s (non-empty)
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // -r (readable)
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-r", file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // -w (writable)
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-w", file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // -x (executable)
    {
        {
            const xf = try std.fs.cwd().openFile(file_path, .{});
            defer xf.close();
            try xf.chmod(0o755);
        }

        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-x", file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }
}

test "test string expressions" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "test");
    defer allocator.free(binary_path);

    // = (equal)
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "abc", "=", "abc" }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // != (not equal)
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "abc", "!=", "def" }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // -z (zero length)
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-z", "" }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // -n (non-zero length)
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-n", "abc" }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }
}

test "test numeric expressions" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "test");
    defer allocator.free(binary_path);

    // -eq (equal)
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "10", "-eq", "10" }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // -ne (not equal)
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "10", "-ne", "20" }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // -lt (less than)
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "10", "-lt", "20" }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // -le (less than or equal)
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "10", "-le", "10" }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // -gt (greater than)
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "20", "-gt", "10" }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }

    // -ge (greater than or equal)
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "20", "-ge", "20" }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }
}

test "test --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "test");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "test --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "test");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "test"));
}
