const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "sha256sum stdin and vectors" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "sha256sum");
    defer allocator.free(bin);

    // Empty input: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  -
    var res1 = try ctx.runCommand(&[_][]const u8{bin}, "");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855  -\n", res1.stdout);

    // "abc": ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  -
    var res2 = try ctx.runCommand(&[_][]const u8{bin}, "abc");
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  -\n", res2.stdout);
}

test "sha256sum check and tag modes" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "sha256sum");
    defer allocator.free(bin);

    try ctx.writeFile("data256.bin", "coreutils 256 test");

    var res_gen = try ctx.runCommand(&[_][]const u8{ bin, "data256.bin" }, null);
    defer res_gen.deinit();
    try testing.expectEqual(@as(u8, 0), res_gen.exit_code);
    try ctx.writeFile("data256.sha256", res_gen.stdout);

    var res_chk = try ctx.runCommand(&[_][]const u8{ bin, "-c", "data256.sha256" }, null);
    defer res_chk.deinit();
    try testing.expectEqual(@as(u8, 0), res_chk.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_chk.stdout, 1, "data256.bin: OK\n"));

    var res_tag = try ctx.runCommand(&[_][]const u8{ bin, "--tag", "data256.bin" }, null);
    defer res_tag.deinit();
    try testing.expectEqual(@as(u8, 0), res_tag.exit_code);
    try testing.expect(std.mem.startsWith(u8, res_tag.stdout, "SHA256 (data256.bin) = "));
}

test "sha256sum nonexistent file error" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "sha256sum");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "missing-256-file" }, null);
    defer res.deinit();
    try testing.expect(res.exit_code != 0);
}
