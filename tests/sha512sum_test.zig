const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "sha512sum stdin and vectors" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "sha512sum");
    defer allocator.free(bin);

    // Empty input: 512 bits = 128 hex chars
    const empty_512 = "cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e  -\n";
    var res1 = try ctx.runCommand(&[_][]const u8{bin}, "");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings(empty_512, res1.stdout);

    // "abc"
    const abc_512 = "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f  -\n";
    var res2 = try ctx.runCommand(&[_][]const u8{bin}, "abc");
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings(abc_512, res2.stdout);
}

test "sha512sum check and tag modes" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "sha512sum");
    defer allocator.free(bin);

    try ctx.writeFile("data512.bin", "coreutils 512 test");

    var res_gen = try ctx.runCommand(&[_][]const u8{ bin, "data512.bin" }, null);
    defer res_gen.deinit();
    try testing.expectEqual(@as(u8, 0), res_gen.exit_code);
    try ctx.writeFile("data512.sha512", res_gen.stdout);

    var res_chk = try ctx.runCommand(&[_][]const u8{ bin, "-c", "data512.sha512" }, null);
    defer res_chk.deinit();
    try testing.expectEqual(@as(u8, 0), res_chk.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_chk.stdout, 1, "data512.bin: OK\n"));

    var res_tag = try ctx.runCommand(&[_][]const u8{ bin, "--tag", "data512.bin" }, null);
    defer res_tag.deinit();
    try testing.expectEqual(@as(u8, 0), res_tag.exit_code);
    try testing.expect(std.mem.startsWith(u8, res_tag.stdout, "SHA512 (data512.bin) = "));
}

test "sha512sum nonexistent file error" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "sha512sum");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "missing-512-file" }, null);
    defer res.deinit();
    try testing.expect(res.exit_code != 0);
}
