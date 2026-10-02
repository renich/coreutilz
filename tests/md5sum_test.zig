const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "md5sum stdin and vectors" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "md5sum");
    defer allocator.free(bin);

    // Empty input: d41d8cd98f00b204e9800998ecf8427e  -
    var res1 = try ctx.runCommand(&[_][]const u8{bin}, "");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("d41d8cd98f00b204e9800998ecf8427e  -\n", res1.stdout);

    // "abc": 900150983cd24fb0d6963f7d28e17f72  -
    var res2 = try ctx.runCommand(&[_][]const u8{bin}, "abc");
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("900150983cd24fb0d6963f7d28e17f72  -\n", res2.stdout);
}

test "md5sum check and tag modes" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "md5sum");
    defer allocator.free(bin);

    try ctx.writeFile("input.txt", "testing md5 checksum verification\n");

    var res_gen = try ctx.runCommand(&[_][]const u8{ bin, "input.txt" }, null);
    defer res_gen.deinit();
    try testing.expectEqual(@as(u8, 0), res_gen.exit_code);
    try ctx.writeFile("input.md5", res_gen.stdout);

    var res_chk = try ctx.runCommand(&[_][]const u8{ bin, "-c", "input.md5" }, null);
    defer res_chk.deinit();
    try testing.expectEqual(@as(u8, 0), res_chk.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_chk.stdout, 1, "input.txt: OK\n"));

    var res_tag = try ctx.runCommand(&[_][]const u8{ bin, "--tag", "input.txt" }, null);
    defer res_tag.deinit();
    try testing.expectEqual(@as(u8, 0), res_tag.exit_code);
    try testing.expect(std.mem.startsWith(u8, res_tag.stdout, "MD5 (input.txt) = "));
}

test "md5sum zero-delimiter and binary flag" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "md5sum");
    defer allocator.free(bin);

    try ctx.writeFile("sample.txt", "abc");

    var res_b = try ctx.runCommand(&[_][]const u8{ bin, "-b", "sample.txt" }, null);
    defer res_b.deinit();
    try testing.expectEqual(@as(u8, 0), res_b.exit_code);
    try testing.expect(std.mem.endsWith(u8, res_b.stdout, " *sample.txt\n"));

    var res_z = try ctx.runCommand(&[_][]const u8{ bin, "-z", "sample.txt" }, null);
    defer res_z.deinit();
    try testing.expectEqual(@as(u8, 0), res_z.exit_code);
    try testing.expect(std.mem.endsWith(u8, res_z.stdout, "\x00"));
}

test "md5sum error paths" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "md5sum");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "no-file-here" }, null);
    defer res.deinit();
    try testing.expect(res.exit_code != 0);
}
