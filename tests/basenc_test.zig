const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "basenc base64 and base32 encoding" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "basenc");
    defer allocator.free(bin);

    // --base64
    var res_b64 = try ctx.runCommand(&[_][]const u8{ bin, "--base64" }, "hello");
    defer res_b64.deinit();
    try testing.expectEqual(@as(u8, 0), res_b64.exit_code);
    try testing.expectEqualStrings("aGVsbG8=\n", res_b64.stdout);

    // --base32
    var res_b32 = try ctx.runCommand(&[_][]const u8{ bin, "--base32" }, "hello");
    defer res_b32.deinit();
    try testing.expectEqual(@as(u8, 0), res_b32.exit_code);
    try testing.expectEqualStrings("NBSWY3DP\n", res_b32.stdout);
}

test "basenc base16 and base2 encoding and decoding" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "basenc");
    defer allocator.free(bin);

    // --base16 encode: "f" (0x66) -> "66\n"
    var res_16 = try ctx.runCommand(&[_][]const u8{ bin, "--base16" }, "f");
    defer res_16.deinit();
    try testing.expectEqual(@as(u8, 0), res_16.exit_code);
    try testing.expectEqualStrings("66\n", res_16.stdout);

    // --base16 decode: "66\n" -> "f"
    var res_16_d = try ctx.runCommand(&[_][]const u8{ bin, "--base16", "-d" }, "66\n");
    defer res_16_d.deinit();
    try testing.expectEqual(@as(u8, 0), res_16_d.exit_code);
    try testing.expectEqualStrings("f", res_16_d.stdout);

    // --base2msbf encode: "f" (0x66 = 01100110)
    var res_2m = try ctx.runCommand(&[_][]const u8{ bin, "--base2msbf" }, "f");
    defer res_2m.deinit();
    try testing.expectEqual(@as(u8, 0), res_2m.exit_code);
    try testing.expectEqualStrings("01100110\n", res_2m.stdout);

    // --base2msbf decode
    var res_2m_d = try ctx.runCommand(&[_][]const u8{ bin, "--base2msbf", "-d" }, "01100110\n");
    defer res_2m_d.deinit();
    try testing.expectEqual(@as(u8, 0), res_2m_d.exit_code);
    try testing.expectEqualStrings("f", res_2m_d.stdout);
}

test "basenc z85 and base58 encoding" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "basenc");
    defer allocator.free(bin);

    // --z85 4 bytes
    var res_z85 = try ctx.runCommand(&[_][]const u8{ bin, "--z85" }, "\x86\x4F\xD2\x6F");
    defer res_z85.deinit();
    try testing.expectEqual(@as(u8, 0), res_z85.exit_code);
    try testing.expectEqualStrings("HelloWorld\n"[0..5], res_z85.stdout[0..5]);

    // --base58 encode: "Hello World" -> "JxF12TrwUP45BMd\n"
    var res_58 = try ctx.runCommand(&[_][]const u8{ bin, "--base58" }, "Hello World");
    defer res_58.deinit();
    try testing.expectEqual(@as(u8, 0), res_58.exit_code);
    try testing.expectEqualStrings("JxF12TrwUP45BMd\n", res_58.stdout);

    // --base58 decode
    var res_58_d = try ctx.runCommand(&[_][]const u8{ bin, "--base58", "-d" }, "JxF12TrwUP45BMd\n");
    defer res_58_d.deinit();
    try testing.expectEqual(@as(u8, 0), res_58_d.exit_code);
    try testing.expectEqualStrings("Hello World", res_58_d.stdout);
}

test "basenc missing algorithm error" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "basenc");
    defer allocator.free(bin);

    // basenc without algorithm must fail
    var res = try ctx.runCommand(&[_][]const u8{bin}, "test");
    defer res.deinit();
    try testing.expect(res.exit_code != 0);
}
