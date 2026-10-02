const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "sha224sum stdin and vectors" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "sha224sum");
    defer allocator.free(bin);

    // Empty input: d14a028c2a3a2bc9476102bb288234c415a2b01f828ea62ac5b3e42f  -
    var res1 = try ctx.runCommand(&[_][]const u8{bin}, "");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("d14a028c2a3a2bc9476102bb288234c415a2b01f828ea62ac5b3e42f  -\n", res1.stdout);

    // "abc": 23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7  -
    var res2 = try ctx.runCommand(&[_][]const u8{bin}, "abc");
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7  -\n", res2.stdout);
}

test "sha224sum check and tag modes" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "sha224sum");
    defer allocator.free(bin);

    try ctx.writeFile("data224.bin", "coreutils 224");

    var res_gen = try ctx.runCommand(&[_][]const u8{ bin, "data224.bin" }, null);
    defer res_gen.deinit();
    try testing.expectEqual(@as(u8, 0), res_gen.exit_code);
    try ctx.writeFile("data224.sha224", res_gen.stdout);

    var res_chk = try ctx.runCommand(&[_][]const u8{ bin, "-c", "data224.sha224" }, null);
    defer res_chk.deinit();
    try testing.expectEqual(@as(u8, 0), res_chk.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_chk.stdout, 1, "data224.bin: OK\n"));

    var res_tag = try ctx.runCommand(&[_][]const u8{ bin, "--tag", "data224.bin" }, null);
    defer res_tag.deinit();
    try testing.expectEqual(@as(u8, 0), res_tag.exit_code);
    try testing.expect(std.mem.startsWith(u8, res_tag.stdout, "SHA224 (data224.bin) = "));
}

test "sha224sum nonexistent file error" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "sha224sum");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "no-such-file" }, null);
    defer res.deinit();
    try testing.expect(res.exit_code != 0);
}
