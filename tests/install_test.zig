const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "install --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "install");
    defer allocator.free(bin);

    var res_h = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res_h.deinit();
    try testing.expectEqual(@as(u8, 0), res_h.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_h.stdout, 1, "Usage: install"));

    var res_v = try ctx.runCommand(&[_][]const u8{ bin, "--version" }, null);
    defer res_v.deinit();
    try testing.expectEqual(@as(u8, 0), res_v.exit_code);
}

test "install -d directory creation" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "install");
    defer allocator.free(bin);

    const dir_path = try ctx.tmpPathRaw("new_dir/sub_dir");
    defer allocator.free(dir_path);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-d", dir_path }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expect(try ctx.fileExists("new_dir/sub_dir"));
}

test "install copy file with mode" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "install");
    defer allocator.free(bin);

    try ctx.writeFile("src.txt", "hello install");
    const src_p = try ctx.tmpPath("src.txt");
    defer allocator.free(src_p);
    const dst_p = try ctx.tmpPathRaw("dst.txt");
    defer allocator.free(dst_p);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-m", "0644", src_p, dst_p }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);

    const content = try ctx.readFile("dst.txt");
    defer allocator.free(content);
    try testing.expectEqualStrings("hello install", content);
}
