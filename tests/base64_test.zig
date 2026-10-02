const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "base64 encode stdin" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "base64");
    defer allocator.free(bin);

    // Empty input produces empty output
    var res1 = try ctx.runCommand(&[_][]const u8{bin}, "");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("", res1.stdout);

    // "hello" -> "aGVsbG8=\n"
    var res2 = try ctx.runCommand(&[_][]const u8{bin}, "hello");
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("aGVsbG8=\n", res2.stdout);
}

test "base64 decode stdin" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "base64");
    defer allocator.free(bin);

    // "aGVsbG8=\n" -> "hello"
    var res1 = try ctx.runCommand(&[_][]const u8{ bin, "-d" }, "aGVsbG8=\n");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("hello", res1.stdout);

    // Decode with ignored garbage
    var res2 = try ctx.runCommand(&[_][]const u8{ bin, "-d", "-i" }, "aG Vsb\n G8=");
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("hello", res2.stdout);
}

test "base64 wrapping flag" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "base64");
    defer allocator.free(bin);

    // "abcdef" -> "YWJjZGVm\n" (8 chars). With -w 4 -> "YWJj\nZGVm\n"
    var res = try ctx.runCommand(&[_][]const u8{ bin, "-w", "4" }, "abcdef");
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("YWJj\nZGVm\n", res.stdout);
}

test "base64 file roundtrip and errors" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "base64");
    defer allocator.free(bin);

    try ctx.writeFile("raw.bin", "file content 1234567890");

    var res_enc = try ctx.runCommand(&[_][]const u8{ bin, "raw.bin" }, null);
    defer res_enc.deinit();
    try testing.expectEqual(@as(u8, 0), res_enc.exit_code);
    try ctx.writeFile("enc.b64", res_enc.stdout);

    var res_dec = try ctx.runCommand(&[_][]const u8{ bin, "-d", "enc.b64" }, null);
    defer res_dec.deinit();
    try testing.expectEqual(@as(u8, 0), res_dec.exit_code);
    try testing.expectEqualStrings("file content 1234567890", res_dec.stdout);

    // Invalid base64 without -i fails
    var res_bad = try ctx.runCommand(&[_][]const u8{ bin, "-d" }, "invalid!!!base64");
    defer res_bad.deinit();
    try testing.expect(res_bad.exit_code != 0);
}

test "base64 --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "base64");
    defer allocator.free(bin);

    var res_h = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res_h.deinit();
    try testing.expectEqual(@as(u8, 0), res_h.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_h.stdout, 1, "Usage: base64"));

    var res_v = try ctx.runCommand(&[_][]const u8{ bin, "--version" }, null);
    defer res_v.deinit();
    try testing.expectEqual(@as(u8, 0), res_v.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_v.stdout, 1, "base64 (coreutilz)"));
}
