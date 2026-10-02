const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "cksum posix crc default" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "cksum");
    defer allocator.free(bin);

    // Empty input: crc of "" is 4294967295 0
    var res1 = try ctx.runCommand(&[_][]const u8{bin}, "");
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);
    try testing.expectEqualStrings("4294967295 0\n", res1.stdout);

    // "a": 1220704766 1
    var res2 = try ctx.runCommand(&[_][]const u8{bin}, "a");
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 0), res2.exit_code);
    try testing.expectEqualStrings("1220704766 1\n", res2.stdout);
}

test "cksum file input and multiple files" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "cksum");
    defer allocator.free(bin);

    try ctx.writeFile("file1.txt", "abc");
    try ctx.writeFile("file2.txt", "12345");

    var res = try ctx.runCommand(&[_][]const u8{ bin, "file1.txt", "file2.txt" }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, "file1.txt\n"));
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, "file2.txt\n"));
}

test "cksum algorithms" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "cksum");
    defer allocator.free(bin);

    // -a md5
    var res_md5 = try ctx.runCommand(&[_][]const u8{ bin, "-a", "md5" }, "abc");
    defer res_md5.deinit();
    try testing.expectEqual(@as(u8, 0), res_md5.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_md5.stdout, 1, "MD5"));
    try testing.expect(std.mem.containsAtLeast(u8, res_md5.stdout, 1, "900150983cd24fb0d6963f7d28e17f72"));

    // -a sha256 --untagged
    var res_sha = try ctx.runCommand(&[_][]const u8{ bin, "-a", "sha256", "--untagged" }, "abc");
    defer res_sha.deinit();
    try testing.expectEqual(@as(u8, 0), res_sha.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_sha.stdout, 1, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  -"));
}

test "cksum check mode" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "cksum");
    defer allocator.free(bin);

    try ctx.writeFile("data.txt", "hello world\n");

    // Generate tagged checksum
    var gen_res = try ctx.runCommand(&[_][]const u8{ bin, "-a", "sha256", "data.txt" }, null);
    defer gen_res.deinit();
    try testing.expectEqual(@as(u8, 0), gen_res.exit_code);
    try ctx.writeFile("check.sum", gen_res.stdout);

    // Verify
    var chk_res = try ctx.runCommand(&[_][]const u8{ bin, "-a", "sha256", "-c", "check.sum" }, null);
    defer chk_res.deinit();
    try testing.expectEqual(@as(u8, 0), chk_res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, chk_res.stdout, 1, "data.txt: OK\n"));
}

test "cksum raw and base64 options" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "cksum");
    defer allocator.free(bin);

    // --raw with md5
    var res_raw = try ctx.runCommand(&[_][]const u8{ bin, "-a", "md5", "--raw" }, "abc");
    defer res_raw.deinit();
    try testing.expectEqual(@as(u8, 0), res_raw.exit_code);
    try testing.expectEqual(@as(usize, 16), res_raw.stdout.len);

    // --base64 with md5
    var res_b64 = try ctx.runCommand(&[_][]const u8{ bin, "-a", "md5", "--base64" }, "abc");
    defer res_b64.deinit();
    try testing.expectEqual(@as(u8, 0), res_b64.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_b64.stdout, 1, "kAFQmDzST7DWlj99KOF/cg=="));
}

test "cksum nonexistent file error" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "cksum");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "nonexistent-file-404.txt" }, null);
    defer res.deinit();
    try testing.expect(res.exit_code != 0);
    try testing.expect(res.stderr.len > 0);
}

test "cksum check stdin diagnostics" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "cksum");
    defer allocator.free(bin);

    // Stdin invalid line with --warn should reference 'standard input'
    var res = try ctx.runCommand(&[_][]const u8{ bin, "--warn", "-c" }, "invalid line\n");
    defer res.deinit();
    try testing.expectEqual(@as(u8, 1), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stderr, 1, "'standard input': 1: improperly formatted CRC checksum line\n"));
    try testing.expect(std.mem.containsAtLeast(u8, res.stderr, 1, "'standard input': no properly formatted checksum lines found\n"));
}

test "cksum tag spacing strictness" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "cksum");
    defer allocator.free(bin);

    // Two spaces between algorithm and '(' must be rejected
    const bad_tag = "SHA256  (foo) = ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad\n";
    var res = try ctx.runCommand(&[_][]const u8{ bin, "-c" }, bad_tag);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 1), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stderr, 1, "no properly formatted checksum lines found\n"));
}

test "cksum --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "cksum");
    defer allocator.free(bin);

    var res_h = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res_h.deinit();
    try testing.expectEqual(@as(u8, 0), res_h.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_h.stdout, 1, "Usage: cksum"));

    var res_v = try ctx.runCommand(&[_][]const u8{ bin, "--version" }, null);
    defer res_v.deinit();
    try testing.expectEqual(@as(u8, 0), res_v.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_v.stdout, 1, "cksum (coreutilz)"));
}
