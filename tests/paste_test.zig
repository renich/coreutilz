const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "paste parallel basic" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "paste");
    defer allocator.free(bin);

    try ctx.writeFile("f1", "1\n2\n");
    try ctx.writeFile("f2", "a\nb\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const f1 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f1" });
    defer allocator.free(f1);
    const f2 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f2" });
    defer allocator.free(f2);

    var res = try ctx.runCommand(&[_][]const u8{ bin, f1, f2 }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("1\ta\n2\tb\n", res.stdout);
}

test "paste parallel with no trailing newline" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "paste");
    defer allocator.free(bin);

    try ctx.writeFile("f1", "a");
    try ctx.writeFile("f2", "b");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const f1 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f1" });
    defer allocator.free(f1);
    const f2 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f2" });
    defer allocator.free(f2);

    var res = try ctx.runCommand(&[_][]const u8{ bin, f1, f2 }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("a\tb\n", res.stdout);
}

test "paste serial (-s)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "paste");
    defer allocator.free(bin);

    try ctx.writeFile("f1", "1\n2\n3\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const f1 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f1" });
    defer allocator.free(f1);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-s", f1 }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("1\t2\t3\n", res.stdout);
}

test "paste custom delimiter (-d)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "paste");
    defer allocator.free(bin);

    try ctx.writeFile("f1", "1\na\n");
    try ctx.writeFile("f2", "2\nb\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const f1 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f1" });
    defer allocator.free(f1);
    const f2 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f2" });
    defer allocator.free(f2);

    // space delimiter
    var res1 = try ctx.runCommand(&[_][]const u8{ bin, "-d ", f1, f2 }, null);
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("1 2\na b\n", res1.stdout);

    // empty delimiter -d ""
    var res2 = try ctx.runCommand(&[_][]const u8{ bin, "-d", "", f1, f2 }, null);
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("12\nab\n", res2.stdout);
}

test "paste delimiter escapes" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "paste");
    defer allocator.free(bin);

    // -s -d '\0,'
    var res1 = try ctx.runCommand(&[_][]const u8{ bin, "-s", "-d", "\\0,", "-" }, "1\n2\n3\n");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("12,3\n", res1.stdout);

    // -s -d '\0'
    var res2 = try ctx.runCommand(&[_][]const u8{ bin, "-s", "-d", "\\0", "-" }, "1\n2\n");
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("12\n", res2.stdout);

    // -s -d '\\'
    var res3 = try ctx.runCommand(&[_][]const u8{ bin, "-s", "-d", "\\\\", "-" }, "1\n2\n");
    defer res3.deinit();
    try testing.expectEqual(@as(u8, 0), res3.exit_code);
    try testing.expectEqualStrings("1\\2\n", res3.stdout);

    // trailing backslash error
    var res4 = try ctx.runCommand(&[_][]const u8{ bin, "-d", "\\" }, null);
    defer res4.deinit();
    try testing.expectEqual(@as(u8, 1), res4.exit_code);
    try testing.expect(std.mem.indexOf(u8, res4.stderr, "delimiter list ends with an unescaped backslash") != null);
}

test "paste multi-byte delimiters" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "paste");
    defer allocator.free(bin);

    try ctx.writeFile("f1", "1\n2\n");
    try ctx.writeFile("f2", "a\nb\n");
    try ctx.writeFile("f3", "x\ny\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const f1 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f1" });
    defer allocator.free(f1);
    const f2 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f2" });
    defer allocator.free(f2);
    const f3 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f3" });
    defer allocator.free(f3);

    // Euro sign (€ = \xe2\x82\xac)
    var res1 = try ctx.runCommand(&[_][]const u8{ bin, "-d", "€", f1, f2 }, null);
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("1€a\n2€b\n", res1.stdout);

    // Multiple multi-byte delimiters cycling: ¢ (€)
    var res2 = try ctx.runCommand(&[_][]const u8{ bin, "-d", "¢€", f1, f2, f3 }, null);
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("1¢a€x\n2¢b€y\n", res2.stdout);
}

test "paste zero-terminated (-z)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "paste");
    defer allocator.free(bin);

    try ctx.writeFile("f1", "1\x00a\x00");
    try ctx.writeFile("f2", "2\x00b\x00");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const f1 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f1" });
    defer allocator.free(f1);
    const f2 = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f2" });
    defer allocator.free(f2);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-zd ", f1, f2 }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("1 2\x00a b\x00", res.stdout);
}

test "paste multiple stdin (- -)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "paste");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-", "-" }, "1\n2\n3\n4\n");
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("1\t2\n3\t4\n", res.stdout);
}

test "paste multicall execution" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "coreutilz");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "paste", "-s", "-d,", "-" }, "1\n2\n3\n");
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("1,2,3\n", res.stdout);
}
