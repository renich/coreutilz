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

    const content1 = try ctx.readFile("test.txt");
    defer allocator.free(content1);
    try testing.expectEqual(@as(usize, 5), content1.len);

    // Extend
    var result2 = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "10", file_path }, null);
    defer result2.deinit();
    try testing.expectEqual(@as(u8, 0), result2.exit_code);

    const content2 = try ctx.readFile("test.txt");
    defer allocator.free(content2);
    try testing.expectEqual(@as(usize, 10), content2.len);
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

test "truncate relative size modifiers" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "truncate");
    defer allocator.free(binary_path);

    try ctx.writeFile("rel.txt", "12345");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "rel.txt" });
    defer allocator.free(file_path);

    // + extend by
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "+3", file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
        const content = try ctx.readFile("rel.txt");
        defer allocator.free(content);
        try testing.expectEqual(@as(usize, 8), content.len);
    }

    // - reduce by
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "-4", file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
        const content = try ctx.readFile("rel.txt");
        defer allocator.free(content);
        try testing.expectEqual(@as(usize, 4), content.len);
    }

    // < at most: size 4 with <10 should stay 4
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "<10", file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
        const content = try ctx.readFile("rel.txt");
        defer allocator.free(content);
        try testing.expectEqual(@as(usize, 4), content.len);
    }

    // < at most: size 4 with <2 should become 2
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "<2", file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
        const content = try ctx.readFile("rel.txt");
        defer allocator.free(content);
        try testing.expectEqual(@as(usize, 2), content.len);
    }

    // > at least: size 2 with >1 should stay 2
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", ">1", file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
        const content = try ctx.readFile("rel.txt");
        defer allocator.free(content);
        try testing.expectEqual(@as(usize, 2), content.len);
    }

    // > at least: size 2 with >7 should become 7
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", ">7", file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
        const content = try ctx.readFile("rel.txt");
        defer allocator.free(content);
        try testing.expectEqual(@as(usize, 7), content.len);
    }

    // / round down: size 7 with /3 should become 6
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "/3", file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
        const content = try ctx.readFile("rel.txt");
        defer allocator.free(content);
        try testing.expectEqual(@as(usize, 6), content.len);
    }

    // % round up: size 6 with %5 should become 10
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "%5", file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
        const content = try ctx.readFile("rel.txt");
        defer allocator.free(content);
        try testing.expectEqual(@as(usize, 10), content.len);
    }
}

test "truncate relative size with whitespace" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "truncate");
    defer allocator.free(binary_path);

    try ctx.writeFile("sp.txt", "abc");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "sp.txt" });
    defer allocator.free(file_path);

    // " +2" with leading whitespace
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--size= +2", file_path }, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const content = try ctx.readFile("sp.txt");
    defer allocator.free(content);
    try testing.expectEqual(@as(usize, 5), content.len);
}

test "truncate multiplier suffixes" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "truncate");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "mult.txt" });
    defer allocator.free(file_path);

    // 1K = 1024
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "1K", file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
        const content = try ctx.readFile("mult.txt");
        defer allocator.free(content);
        try testing.expectEqual(@as(usize, 1024), content.len);
    }

    // 1kB = 1000
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "1kB", file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
        const content = try ctx.readFile("mult.txt");
        defer allocator.free(content);
        try testing.expectEqual(@as(usize, 1000), content.len);
    }

    // 2KiB = 2048
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "2KiB", file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
        const content = try ctx.readFile("mult.txt");
        defer allocator.free(content);
        try testing.expectEqual(@as(usize, 2048), content.len);
    }
}

test "truncate error conditions" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "truncate");
    defer allocator.free(binary_path);

    try ctx.writeFile("file.txt", "abc");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file.txt" });
    defer allocator.free(file_path);

    // Missing operand
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "0" }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 1), result.exit_code);
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "missing file operand"));
    }

    // Neither size nor reference specified
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 1), result.exit_code);
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "you must specify either '--size' or '--reference'"));
    }

    // Reference and absolute size not allowed together
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-r", file_path, "-s", "0", file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 1), result.exit_code);
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "you must specify a relative '--size' with '--reference'"));
    }

    // io-blocks without size
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--io-blocks", "-r", file_path, file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 1), result.exit_code);
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "'--io-blocks' was specified but '--size' was not"));
    }

    // Multiple modifiers: > -1
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "> -1", file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 1), result.exit_code);
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "multiple relative modifiers specified"));
    }

    // Division by zero: /0
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "/0", file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 1), result.exit_code);
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "division by zero"));
    }

    // Division by zero: %0
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "%0", file_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 1), result.exit_code);
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "division by zero"));
    }

    // Directory operand fails
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "0", tmp_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 1), result.exit_code);
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "cannot open"));
    }
}

test "truncate creates file through dangling symlink" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "truncate");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const symlink_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "symlink" });
    defer allocator.free(symlink_path);

    // Create dangling symlink pointing to non-existent target_file
    try ctx.makeSymlink("target_file", "symlink");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "10", symlink_path }, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const content = try ctx.readFile("target_file");
    defer allocator.free(content);
    try testing.expectEqual(@as(usize, 10), content.len);
}
