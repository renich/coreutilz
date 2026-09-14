const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

fn setMtime(path: []const u8, mtime_sec: i64) !void {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;
    const path_z: [*:0]const u8 = @ptrCast(&path_buf);

    const times = [2]std.os.linux.timespec{
        .{ .sec = mtime_sec, .nsec = 0 },
        .{ .sec = mtime_sec, .nsec = 0 },
    };
    const rc = std.os.linux.utimensat(std.posix.AT.FDCWD, path_z, @ptrCast(&times), 0);
    const err = std.os.linux.errno(rc);
    if (err != .SUCCESS) return error.UtimensatFailed;
}

// [FUNC-LS-001] Operand Ingestion & Default Target
test "ls [FUNC-LS-001] basic directory listing with target directory" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("file1.txt", "content1\n");
    try ctx.writeFile("file2.txt", "content2\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "file1.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "file2.txt"));
}

test "ls [FUNC-LS-001] default target current working directory" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("alpha.txt", "alpha\n");
    try ctx.writeFile("beta.txt", "beta\n");

    var result = try ctx.runCommand(&[_][]const u8{binary_path}, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "alpha.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "beta.txt"));
}

test "ls [FUNC-LS-001] multiple operands in command-line argument order" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.makeDir("dir_a");
    try ctx.writeFile("dir_a/item_a.txt", "a\n");
    try ctx.makeDir("dir_b");
    try ctx.writeFile("dir_b/item_b.txt", "b\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const path_a = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "dir_a" });
    defer allocator.free(path_a);
    const path_b = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "dir_b" });
    defer allocator.free(path_b);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, path_a, path_b }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const idx_a = std.mem.indexOf(u8, result.stdout, "dir_a") orelse return error.TestExpectedEqual;
    const idx_b = std.mem.indexOf(u8, result.stdout, "dir_b") orelse return error.TestExpectedEqual;
    try testing.expect(idx_a < idx_b);
}

test "ls [FUNC-LS-001] file operands displayed before directory contents" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.makeDir("sub");
    try ctx.writeFile("sub/nested.txt", "sub\n");
    try ctx.writeFile("first.txt", "first\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const sub_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "sub" });
    defer allocator.free(sub_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "first.txt" });
    defer allocator.free(file_path);

    // Pass directory operand first, file operand second
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, sub_path, file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const idx_file = std.mem.indexOf(u8, result.stdout, "first.txt") orelse return error.TestExpectedEqual;
    const idx_header = std.mem.indexOf(u8, result.stdout, "sub:") orelse return error.TestExpectedEqual;
    try testing.expect(idx_file < idx_header);
}

// [FUNC-LS-002] Entry Filtering & Hidden Files
test "ls [FUNC-LS-002] default omits hidden dotfiles" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("visible.txt", "visible\n");
    try ctx.writeFile(".hidden", "hidden\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-1", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "visible.txt"));
    try testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, ".hidden"));
}

test "ls [FUNC-LS-002a] -a / --all includes dotfiles, dot and dotdot" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("regular.txt", "regular\n");
    try ctx.writeFile(".dotfile", "dot\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-a", "-1", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "regular.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, ".dotfile"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, ".\n"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "..\n"));
}

test "ls [FUNC-LS-002b] -A / --almost-all includes dotfiles but excludes dot and dotdot" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("norm.txt", "norm\n");
    try ctx.writeFile(".secret", "secret\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-A", "-1", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "norm.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, ".secret"));
    try testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, ".\n"));
    try testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, "..\n"));
}

test "ls [FUNC-LS-002c] -d / --directory lists directory itself not contents" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.makeDir("mydir");
    try ctx.writeFile("mydir/inner.txt", "inner\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "mydir" });
    defer allocator.free(dir_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-d", dir_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "mydir"));
    try testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, "inner.txt"));
}

// [FUNC-LS-003] Detailed Long Listing (-l)
test "ls [FUNC-LS-003] -l detailed long listing columns" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("sample.txt", "sample content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    // Regular file mode starts with '-'
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "-"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "sample.txt"));
    // Long listing contains total line
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "total"));
}

test "ls [FUNC-LS-003] -l symlink displays target arrow" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("target.txt", "target\n");
    try ctx.makeSymlink("target.txt", "link.lnk");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "link.lnk -> target.txt"));
}

test "ls [FUNC-LS-003] -n numeric uid and gid" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("num.txt", "data\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-n", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "num.txt"));
}

test "ls [FUNC-LS-003] -h human-readable size scaling" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    const big_buf = try allocator.alloc(u8, 2048);
    defer allocator.free(big_buf);
    @memset(big_buf, 'Z');
    try ctx.writeFile("big.bin", big_buf);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-lh", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "2.0K") or std.mem.containsAtLeast(u8, result.stdout, 1, "2K"));
}

test "ls [FUNC-LS-003] -g and -o omit owner or group" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("file.txt", "test\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var res_g = try ctx.runCommand(&[_][]const u8{ binary_path, "-g", tmp_path }, null);
    defer res_g.deinit();
    try testing.expectEqual(@as(u8, 0), res_g.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_g.stdout, 1, "file.txt"));

    var res_o = try ctx.runCommand(&[_][]const u8{ binary_path, "-o", tmp_path }, null);
    defer res_o.deinit();
    try testing.expectEqual(@as(u8, 0), res_o.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_o.stdout, 1, "file.txt"));
}

test "ls [FUNC-LS-003] --full-time outputs ISO timestamp" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("iso.txt", "iso\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--full-time", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    // Should match date like YYYY-MM-DD
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "-"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "iso.txt"));
}

// [FUNC-LS-004] Output Layout & Formatting Modes
test "ls [FUNC-LS-004a] -1 outputs single column one per line" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("one.txt", "1\n");
    try ctx.writeFile("two.txt", "2\n");
    try ctx.writeFile("three.txt", "3\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-1", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "one.txt\n"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "two.txt\n"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "three.txt\n"));
}

test "ls [FUNC-LS-004b] -C multi-column vertical layout" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("c1.txt", "1\n");
    try ctx.writeFile("c2.txt", "2\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-C", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "c1.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "c2.txt"));
}

test "ls [FUNC-LS-004c] -x multi-column horizontal layout across rows" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("x1.txt", "1\n");
    try ctx.writeFile("x2.txt", "2\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-x", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "x1.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "x2.txt"));
}

test "ls [FUNC-LS-004d] -m comma-separated stream" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("a.txt", "a\n");
    try ctx.writeFile("b.txt", "b\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-m", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "a.txt, b.txt"));
}

test "ls [FUNC-LS-004e] -Q double quotes entry names" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("quote_me.txt", "q\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-Q", "-1", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "\"quote_me.txt\""));
}

// [FUNC-LS-005] Sorting Disciplines
test "ls [FUNC-LS-005] default alphabetical sort order" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("zoo.txt", "z\n");
    try ctx.writeFile("ant.txt", "a\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-1", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const ant_idx = std.mem.indexOf(u8, result.stdout, "ant.txt") orelse return error.TestExpectedEqual;
    const zoo_idx = std.mem.indexOf(u8, result.stdout, "zoo.txt") orelse return error.TestExpectedEqual;
    try testing.expect(ant_idx < zoo_idx);
}

test "ls [FUNC-LS-005a] -t sorts by modification time newest first" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("old.txt", "old\n");
    try ctx.writeFile("new.txt", "new\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const old_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "old.txt" });
    defer allocator.free(old_path);
    const new_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "new.txt" });
    defer allocator.free(new_path);

    try setMtime(old_path, 1_000_000);
    try setMtime(new_path, 2_000_000);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-1t", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const new_idx = std.mem.indexOf(u8, result.stdout, "new.txt") orelse return error.TestExpectedEqual;
    const old_idx = std.mem.indexOf(u8, result.stdout, "old.txt") orelse return error.TestExpectedEqual;
    try testing.expect(new_idx < old_idx);
}

test "ls [FUNC-LS-005b] -S sorts by file size largest first" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("small.txt", "x\n");
    try ctx.writeFile("huge.txt", "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-1S", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const huge_idx = std.mem.indexOf(u8, result.stdout, "huge.txt") orelse return error.TestExpectedEqual;
    const small_idx = std.mem.indexOf(u8, result.stdout, "small.txt") orelse return error.TestExpectedEqual;
    try testing.expect(huge_idx < small_idx);
}

test "ls [FUNC-LS-005c] -X sorts by file extension" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("file.zzz", "z\n");
    try ctx.writeFile("file.aaa", "a\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-1X", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const aaa_idx = std.mem.indexOf(u8, result.stdout, "file.aaa") orelse return error.TestExpectedEqual;
    const zzz_idx = std.mem.indexOf(u8, result.stdout, "file.zzz") orelse return error.TestExpectedEqual;
    try testing.expect(aaa_idx < zzz_idx);
}

test "ls [FUNC-LS-005d] -v natural version sorting" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("v1.10.txt", "10\n");
    try ctx.writeFile("v1.2.txt", "2\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-1v", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const v2_idx = std.mem.indexOf(u8, result.stdout, "v1.2.txt") orelse return error.TestExpectedEqual;
    const v10_idx = std.mem.indexOf(u8, result.stdout, "v1.10.txt") orelse return error.TestExpectedEqual;
    try testing.expect(v2_idx < v10_idx);
}

test "ls [FUNC-LS-005e] -r reverses sorting order" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("aaa.txt", "a\n");
    try ctx.writeFile("zzz.txt", "z\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-1r", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const zzz_idx = std.mem.indexOf(u8, result.stdout, "zzz.txt") orelse return error.TestExpectedEqual;
    const aaa_idx = std.mem.indexOf(u8, result.stdout, "aaa.txt") orelse return error.TestExpectedEqual;
    try testing.expect(zzz_idx < aaa_idx);
}

// [FUNC-LS-006] Recursive Traversal
test "ls [FUNC-LS-006] -R recursively traverses subdirectories" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("root.txt", "root\n");
    try ctx.makeDir("subdir");
    try ctx.writeFile("subdir/nested.txt", "nested\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-R", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "root.txt"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "subdir"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "nested.txt"));
}

// [FUNC-LS-007] File Metadata Indicators
test "ls [FUNC-LS-007a] -i prints inode numbers" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("inode_test.txt", "inode\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-i", "-1", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "inode_test.txt"));
}

test "ls [FUNC-LS-007b] -s prints allocated block size" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.writeFile("block_test.txt", "blocks\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "-1", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "block_test.txt"));
}

test "ls [FUNC-LS-007c] -F classifies directory, executable, symlink" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.makeDir("test_dir");
    try ctx.writeFile("test_exec", "#!/bin/sh\n");
    try ctx.writeFile("test_file.txt", "regular\n");
    try ctx.makeSymlink("test_file.txt", "test_sym");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const exec_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test_exec" });
    defer allocator.free(exec_path);

    {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        @memcpy(path_buf[0..exec_path.len], exec_path);
        path_buf[exec_path.len] = 0;
        const path_z: [*:0]const u8 = @ptrCast(&path_buf);
        _ = std.os.linux.chmod(path_z, 0o755);
    }

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-F", "-1", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "test_dir/"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "test_exec*"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "test_sym@"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "test_file.txt"));
}

test "ls [FUNC-LS-007d] -p appends slash only to directories" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    try ctx.makeDir("dir_only");
    try ctx.writeFile("file_only.txt", "content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-p", "-1", tmp_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "dir_only/"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "file_only.txt"));
    try testing.expect(!std.mem.containsAtLeast(u8, result.stdout, 1, "file_only.txt/"));
}

// [FUNC-LS-008] Exit Codes & Diagnostics
test "ls [FUNC-LS-008] exit code 0 on successful listing" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{binary_path}, null);
    defer result.deinit();
    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "ls [FUNC-LS-008] exit code 2 and diagnostic for nonexistent file" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const missing = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "does_not_exist" });
    defer allocator.free(missing);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, missing }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 2), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "ls: cannot access '"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "No such file or directory"));
}

test "ls [FUNC-LS-008] exit code 2 on invalid CLI flag" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--definitely-invalid-option" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 2), result.exit_code);
    try testing.expect(result.stderr.len > 0);
}

test "ls [FUNC-LS-008] --help outputs usage" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "ls"));
}

test "ls [FUNC-LS-008] --version outputs version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "ls");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "ls"));
}
