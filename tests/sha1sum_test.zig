const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "sha1sum stdin and vectors" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "sha1sum");
    defer allocator.free(bin);

    // Empty input: da39a3ee5e6b4b0d3255bfef95601890afd80709  -
    var res1 = try ctx.runCommand(&[_][]const u8{bin}, "");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("da39a3ee5e6b4b0d3255bfef95601890afd80709  -\n", res1.stdout);

    // "abc": a9993e364706816aba3e25717850c26c9cd0d89d  -
    var res2 = try ctx.runCommand(&[_][]const u8{bin}, "abc");
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("a9993e364706816aba3e25717850c26c9cd0d89d  -\n", res2.stdout);
}

test "sha1sum check and tag modes" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "sha1sum");
    defer allocator.free(bin);

    try ctx.writeFile("data.bin", "quick brown fox");

    var res_gen = try ctx.runCommand(&[_][]const u8{ bin, "data.bin" }, null);
    defer res_gen.deinit();
    try testing.expectEqual(@as(u8, 0), res_gen.exit_code);
    try ctx.writeFile("data.sha1", res_gen.stdout);

    var res_chk = try ctx.runCommand(&[_][]const u8{ bin, "-c", "data.sha1" }, null);
    defer res_chk.deinit();
    try testing.expectEqual(@as(u8, 0), res_chk.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_chk.stdout, 1, "data.bin: OK\n"));

    var res_tag = try ctx.runCommand(&[_][]const u8{ bin, "--tag", "data.bin" }, null);
    defer res_tag.deinit();
    try testing.expectEqual(@as(u8, 0), res_tag.exit_code);
    try testing.expect(std.mem.startsWith(u8, res_tag.stdout, "SHA1 (data.bin) = "));
}

test "sha1sum error on missing file" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "sha1sum");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "missing-file-xyz" }, null);
    defer res.deinit();
    try testing.expect(res.exit_code != 0);
}
