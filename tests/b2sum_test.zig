const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "b2sum stdin default" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "b2sum");
    defer allocator.free(bin);

    // Empty input: 512-bit hex digest (128 hex chars) followed by "  -\n"
    var res1 = try ctx.runCommand(&[_][]const u8{bin}, "");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqual(@as(usize, 128 + 4), res1.stdout.len);
    try testing.expect(std.mem.endsWith(u8, res1.stdout, "  -\n"));

    // Digest of ""
    const empty_digest = "786a02f742015903c6c6fd852552d272912f4740e15847618a86e217f71f5419d25e1031afee585313896444934eb04b903a685b1448b755d56f701afe9be2ce";
    try testing.expect(std.mem.startsWith(u8, res1.stdout, empty_digest));
}

test "b2sum length flag" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "b2sum");
    defer allocator.free(bin);

    // -l 128: 16 bytes = 32 hex chars
    var res = try ctx.runCommand(&[_][]const u8{ bin, "-l", "128" }, "");
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqual(@as(usize, 32 + 4), res.stdout.len);
}

test "b2sum check and tag mode" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "b2sum");
    defer allocator.free(bin);

    try ctx.writeFile("hello.txt", "hello world\n");

    // Standard format
    var res_std = try ctx.runCommand(&[_][]const u8{ bin, "hello.txt" }, null);
    defer res_std.deinit();
    try testing.expectEqual(@as(u8, 0), res_std.exit_code);
    try ctx.writeFile("hello.b2", res_std.stdout);

    // Verify standard
    var res_chk = try ctx.runCommand(&[_][]const u8{ bin, "-c", "hello.b2" }, null);
    defer res_chk.deinit();
    try testing.expectEqual(@as(u8, 0), res_chk.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_chk.stdout, 1, "hello.txt: OK\n"));

    // Tag mode
    var res_tag = try ctx.runCommand(&[_][]const u8{ bin, "--tag", "hello.txt" }, null);
    defer res_tag.deinit();
    try testing.expectEqual(@as(u8, 0), res_tag.exit_code);
    try testing.expect(std.mem.startsWith(u8, res_tag.stdout, "BLAKE2b (hello.txt) = "));
}

test "b2sum quiet and status flags" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "b2sum");
    defer allocator.free(bin);

    try ctx.writeFile("f.txt", "abc");
    var res_gen = try ctx.runCommand(&[_][]const u8{ bin, "f.txt" }, null);
    defer res_gen.deinit();
    try ctx.writeFile("f.b2", res_gen.stdout);

    // --status suppresses all output
    var res_stat = try ctx.runCommand(&[_][]const u8{ bin, "--status", "-c", "f.b2" }, null);
    defer res_stat.deinit();
    try testing.expectEqual(@as(u8, 0), res_stat.exit_code);
    try testing.expectEqualStrings("", res_stat.stdout);
}

test "b2sum nonexistent file error" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "b2sum");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "not-found.bin" }, null);
    defer res.deinit();
    try testing.expect(res.exit_code != 0);
    try testing.expect(res.stderr.len > 0);
}
