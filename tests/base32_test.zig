const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "base32 encode stdin" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "base32");
    defer allocator.free(bin);

    // Empty input produces empty output
    var res1 = try ctx.runCommand(&[_][]const u8{bin}, "");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("", res1.stdout);

    // "hello" -> "NBSWY3DP\n"
    var res2 = try ctx.runCommand(&[_][]const u8{bin}, "hello");
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("NBSWY3DP\n", res2.stdout);
}

test "base32 decode stdin" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "base32");
    defer allocator.free(bin);

    // "NBSWY3DP\n" -> "hello"
    var res1 = try ctx.runCommand(&[_][]const u8{ bin, "-d" }, "NBSWY3DP\n");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("hello", res1.stdout);

    // Decode with ignored garbage
    var res2 = try ctx.runCommand(&[_][]const u8{ bin, "-d", "-i" }, "NB SW\n Y3 DP");
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("hello", res2.stdout);
}

test "base32 wrapping flag" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "base32");
    defer allocator.free(bin);

    // "hello" -> "NBSWY3DP\n". With -w 4 -> "NBSW\nY3DP\n"
    var res = try ctx.runCommand(&[_][]const u8{ bin, "-w", "4" }, "hello");
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("NBSW\nY3DP\n", res.stdout);
}

test "base32 file roundtrip and errors" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "base32");
    defer allocator.free(bin);

    try ctx.writeFile("data.bin", "base32 file payload");

    var res_enc = try ctx.runCommand(&[_][]const u8{ bin, "data.bin" }, null);
    defer res_enc.deinit();
    try testing.expectEqual(@as(u8, 0), res_enc.exit_code);
    try ctx.writeFile("data.b32", res_enc.stdout);

    var res_dec = try ctx.runCommand(&[_][]const u8{ bin, "-d", "data.b32" }, null);
    defer res_dec.deinit();
    try testing.expectEqual(@as(u8, 0), res_dec.exit_code);
    try testing.expectEqualStrings("base32 file payload", res_dec.stdout);

    // Invalid character error
    var res_bad = try ctx.runCommand(&[_][]const u8{ bin, "-d" }, "invalid888999");
    defer res_bad.deinit();
    try testing.expect(res_bad.exit_code != 0);
}
