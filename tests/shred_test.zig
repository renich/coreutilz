const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "shred --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "shred");
    defer allocator.free(bin);

    var res_h = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res_h.deinit();
    try testing.expectEqual(@as(u8, 0), res_h.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_h.stdout, 1, "Usage: shred"));

    var res_v = try ctx.runCommand(&[_][]const u8{ bin, "--version" }, null);
    defer res_v.deinit();
    try testing.expectEqual(@as(u8, 0), res_v.exit_code);
}

test "shred overwrites file and zeros with -z" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "shred");
    defer allocator.free(bin);

    const secret = "SUPER_SECRET_TOKEN_DO_NOT_REVEAL_ANYWHERE";
    try ctx.writeFile("secret.txt", secret);
    const p = try ctx.tmpPath("secret.txt");
    defer allocator.free(p);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-n", "1", "-z", "-x", p }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);

    const content = try ctx.readFile("secret.txt");
    defer allocator.free(content);
    try testing.expectEqual(secret.len, content.len);
    // Because of -z, all bytes must be 0
    for (content) |b| {
        try testing.expectEqual(@as(u8, 0), b);
    }
}

test "shred -u removes file" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "shred");
    defer allocator.free(bin);

    try ctx.writeFile("temp_file.txt", "data to delete");
    const p = try ctx.tmpPath("temp_file.txt");
    defer allocator.free(p);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-u", p }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);

    // Verify file is gone
    const exists = try ctx.fileExists("temp_file.txt");
    try testing.expect(!exists);
}
