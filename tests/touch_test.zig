const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "touch creates new empty file" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "newfile.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, file_path }, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const content = try ctx.readFile("newfile.txt");
    defer allocator.free(content);
    try testing.expectEqual(@as(usize, 0), content.len);
}

test "touch -c does not create nonexistent file" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "nonexistent.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-c", file_path }, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);

    _ = ctx.readFile("nonexistent.txt") catch |err| {
        try testing.expectEqual(error.FileNotFound, err);
        return;
    };
    try testing.expect(false);
}

test "touch -r reference file" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    try ctx.writeFile("ref.txt", "reference content");
    try ctx.writeFile("target.txt", "target content");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const ref_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "ref.txt" });
    defer allocator.free(ref_path);
    const target_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "target.txt" });
    defer allocator.free(target_path);

    // Set ref to 2005-05-05 05:05:05
    var res1 = try ctx.runCommand(&[_][]const u8{ binary_path, "-d", "2005-05-05 05:05:05", ref_path }, null);
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);

    // Touch target with -r ref
    var res2 = try ctx.runCommand(&[_][]const u8{ binary_path, "-r", ref_path, target_path }, null);
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);

    var stx_ref = std.mem.zeroes(std.os.linux.Statx);
    var ref_buf: [std.fs.max_path_bytes]u8 = undefined;
    @memcpy(ref_buf[0..ref_path.len], ref_path);
    ref_buf[ref_path.len] = 0;
    _ = std.os.linux.statx(std.posix.AT.FDCWD, @ptrCast(&ref_buf), 0, .{ .MTIME = true }, &stx_ref);

    var stx_tgt = std.mem.zeroes(std.os.linux.Statx);
    var tgt_buf: [std.fs.max_path_bytes]u8 = undefined;
    @memcpy(tgt_buf[0..target_path.len], target_path);
    tgt_buf[target_path.len] = 0;
    _ = std.os.linux.statx(std.posix.AT.FDCWD, @ptrCast(&tgt_buf), 0, .{ .MTIME = true }, &stx_tgt);

    try testing.expectEqual(stx_ref.mtime.sec, stx_tgt.mtime.sec);
}

test "touch -d explicit date" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    try ctx.writeFile("date.txt", "test");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "date.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-d", "2010-10-10 10:10:10", file_path }, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);

    var stx = std.mem.zeroes(std.os.linux.Statx);
    var f_buf: [std.fs.max_path_bytes]u8 = undefined;
    @memcpy(f_buf[0..file_path.len], file_path);
    f_buf[file_path.len] = 0;
    _ = std.os.linux.statx(std.posix.AT.FDCWD, @ptrCast(&f_buf), 0, .{ .MTIME = true }, &stx);

    // Verify mtime matches 2010-10-10
    try testing.expect(stx.mtime.sec > 1200000000);
}

test "touch -t POSIX format with 60 seconds" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    try ctx.writeFile("sec60.txt", "test");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "sec60.txt" });
    defer allocator.free(file_path);

    var env_map = framework.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("TZ", "UTC0");

    var result = try ctx.runCommandInDir(&[_][]const u8{ binary_path, "-t", "197001010000.60", file_path }, null, tmp_path, &env_map);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);

    var stx = std.mem.zeroes(std.os.linux.Statx);
    var f_buf: [std.fs.max_path_bytes]u8 = undefined;
    @memcpy(f_buf[0..file_path.len], file_path);
    f_buf[file_path.len] = 0;
    _ = std.os.linux.statx(std.posix.AT.FDCWD, @ptrCast(&f_buf), 0, .{ .MTIME = true }, &stx);

    try testing.expectEqual(@as(i64, 60), stx.mtime.sec);
}

test "touch -r and -d relative date" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    try ctx.writeFile("rel.txt", "test");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "rel.txt" });
    defer allocator.free(file_path);

    // Initial date 2004-01-16 12:00:00 UTC
    var env_map = framework.EnvMap.init(allocator);
    defer env_map.deinit();
    try env_map.put("TZ", "UTC0");

    var res1 = try ctx.runCommandInDir(&[_][]const u8{ binary_path, "-d", "2004-01-16 12:00:00", file_path }, null, tmp_path, &env_map);
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);

    // Subtract 5 days
    var res2 = try ctx.runCommandInDir(&[_][]const u8{ binary_path, "-r", file_path, "-d", "-5 days", file_path }, null, tmp_path, &env_map);
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);

    var stx = std.mem.zeroes(std.os.linux.Statx);
    var f_buf: [std.fs.max_path_bytes]u8 = undefined;
    @memcpy(f_buf[0..file_path.len], file_path);
    f_buf[file_path.len] = 0;
    _ = std.os.linux.statx(std.posix.AT.FDCWD, @ptrCast(&f_buf), 0, .{ .MTIME = true }, &stx);

    // 2004-01-16 minus 5 days = 2004-01-11
    // Difference between 16th and 11th is 5 * 86400 = 432000 seconds
    const expected_sec = 1074254400 - 5 * 86400;
    try testing.expectEqual(expected_sec, stx.mtime.sec);
}

test "touch creates file through dangling symlink" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const symlink_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "symlink" });
    defer allocator.free(symlink_path);

    try ctx.makeSymlink("target_file", "symlink");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, symlink_path }, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);

    const content = try ctx.readFile("target_file");
    defer allocator.free(content);
    try testing.expectEqual(@as(usize, 0), content.len);
}

test "touch -h modifies symlink and does not create target" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const symlink_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "symlink" });
    defer allocator.free(symlink_path);

    try ctx.makeSymlink("nonexistent_target", "symlink");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-h", symlink_path }, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Target must NOT exist
    _ = ctx.readFile("nonexistent_target") catch |err| {
        try testing.expectEqual(error.FileNotFound, err);
        return;
    };
    try testing.expect(false);
}

test "touch error conditions and diagnostics" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    // Missing file operand
    {
        var result = try ctx.runCommand(&[_][]const u8{binary_path}, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 1), result.exit_code);
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "missing file operand"));
    }

    // Unwritable parent directory / non-existent dir
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "/no-such-dir/file" }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 1), result.exit_code);
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "cannot touch '/no-such-dir/file': No such file or directory"));
    }

    // -h on nonexistent file fails
    {
        const tmp_path = try ctx.tmpPath(".");
        defer allocator.free(tmp_path);
        const bad_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "no_file" });
        defer allocator.free(bad_path);

        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-h", bad_path }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 1), result.exit_code);
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "setting times of"));
    }

    // Multiple time sources (-t and -d)
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-t", "202001010000", "-d", "2020-01-01", "file.txt" }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 1), result.exit_code);
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "cannot specify times from more than one source"));
    }

    // Invalid date format
    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-d", "invalid date", "file.txt" }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 1), result.exit_code);
        try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "invalid date format"));
    }
}

test "touch on directory with trailing slash" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "testdir/" });
    defer allocator.free(dir_path);

    try ctx.makeDir("testdir");

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, dir_path }, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "touch --help and --version" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
    }

    {
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
        try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "touch"));
    }
}

test "touch -a updates only atime" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    try ctx.writeFile("atime.txt", "abc");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "atime.txt" });
    defer allocator.free(file_path);

    // Set initial times to 2000-01-01
    var res1 = try ctx.runCommand(&[_][]const u8{ binary_path, "-d", "2000-01-01 00:00:00", file_path }, null);
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);

    // Update only atime to 2010-01-01
    var res2 = try ctx.runCommand(&[_][]const u8{ binary_path, "-a", "-d", "2010-01-01 00:00:00", file_path }, null);
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);

    var stx = std.mem.zeroes(std.os.linux.Statx);
    var f_buf: [std.fs.max_path_bytes]u8 = undefined;
    @memcpy(f_buf[0..file_path.len], file_path);
    f_buf[file_path.len] = 0;
    _ = std.os.linux.statx(std.posix.AT.FDCWD, @ptrCast(&f_buf), 0, .{ .ATIME = true, .MTIME = true }, &stx);

    // atime was updated to 2010 (> 1200000000), mtime remains 2000 (< 1000000000)
    try testing.expect(stx.atime.sec > 1200000000);
    try testing.expect(stx.mtime.sec < 1000000000);
}

test "touch -m updates only mtime" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    try ctx.writeFile("mtime.txt", "abc");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "mtime.txt" });
    defer allocator.free(file_path);

    // Set initial times to 2000-01-01
    var res1 = try ctx.runCommand(&[_][]const u8{ binary_path, "-d", "2000-01-01 00:00:00", file_path }, null);
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);

    // Update only mtime to 2010-01-01
    var res2 = try ctx.runCommand(&[_][]const u8{ binary_path, "-m", "-d", "2010-01-01 00:00:00", file_path }, null);
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);

    var stx = std.mem.zeroes(std.os.linux.Statx);
    var f_buf: [std.fs.max_path_bytes]u8 = undefined;
    @memcpy(f_buf[0..file_path.len], file_path);
    f_buf[file_path.len] = 0;
    _ = std.os.linux.statx(std.posix.AT.FDCWD, @ptrCast(&f_buf), 0, .{ .ATIME = true, .MTIME = true }, &stx);

    // mtime was updated to 2010 (> 1200000000), atime remains 2000 (< 1000000000)
    try testing.expect(stx.mtime.sec > 1200000000);
    try testing.expect(stx.atime.sec < 1000000000);
}

test "touch works on fifo without hanging" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "touch");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const fifo_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "testfifo" });
    defer allocator.free(fifo_path);

    var f_buf: [std.fs.max_path_bytes]u8 = undefined;
    @memcpy(f_buf[0..fifo_path.len], fifo_path);
    f_buf[fifo_path.len] = 0;
    const rc = std.os.linux.mknodat(std.posix.AT.FDCWD, @ptrCast(&f_buf), std.posix.S.IFIFO | 0o666, 0);
    if (std.os.linux.errno(rc) != .SUCCESS) return; // skip if cannot mkfifo

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, fifo_path }, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);
}
