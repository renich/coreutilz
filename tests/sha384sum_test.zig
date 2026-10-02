const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "sha384sum stdin and vectors" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "sha384sum");
    defer allocator.free(bin);

    // Empty input: 384 bits = 96 hex chars
    const empty_384 = "38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b  -\n";
    var res1 = try ctx.runCommand(&[_][]const u8{bin}, "");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings(empty_384, res1.stdout);

    // "abc"
    const abc_384 = "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7  -\n";
    var res2 = try ctx.runCommand(&[_][]const u8{bin}, "abc");
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings(abc_384, res2.stdout);
}

test "sha384sum check and tag modes" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "sha384sum");
    defer allocator.free(bin);

    try ctx.writeFile("data384.bin", "coreutils 384 test");

    var res_gen = try ctx.runCommand(&[_][]const u8{ bin, "data384.bin" }, null);
    defer res_gen.deinit();
    try testing.expectEqual(@as(u8, 0), res_gen.exit_code);
    try ctx.writeFile("data384.sha384", res_gen.stdout);

    var res_chk = try ctx.runCommand(&[_][]const u8{ bin, "-c", "data384.sha384" }, null);
    defer res_chk.deinit();
    try testing.expectEqual(@as(u8, 0), res_chk.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_chk.stdout, 1, "data384.bin: OK\n"));

    var res_tag = try ctx.runCommand(&[_][]const u8{ bin, "--tag", "data384.bin" }, null);
    defer res_tag.deinit();
    try testing.expectEqual(@as(u8, 0), res_tag.exit_code);
    try testing.expect(std.mem.startsWith(u8, res_tag.stdout, "SHA384 (data384.bin) = "));
}

test "sha384sum nonexistent file error" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "sha384sum");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "missing-384-file" }, null);
    defer res.deinit();
    try testing.expect(res.exit_code != 0);
}
