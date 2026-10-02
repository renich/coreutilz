const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "pr -t omit header" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "pr");
    defer allocator.free(bin);

    try ctx.writeFile("input.txt", "line1\nline2\n");
    const p = try ctx.tmpPath("input.txt");
    defer allocator.free(p);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-t", p }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("line1\nline2\n", res.stdout);
}

test "pr -t -n line numbering" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "pr");
    defer allocator.free(bin);

    try ctx.writeFile("input.txt", "alpha\nbeta\n");
    const p = try ctx.tmpPath("input.txt");
    defer allocator.free(p);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-t", "-n", p }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("    1\talpha\n    2\tbeta\n", res.stdout);
}

test "pr -t -d double space" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "pr");
    defer allocator.free(bin);

    try ctx.writeFile("input.txt", "first\nsecond\n");
    const p = try ctx.tmpPath("input.txt");
    defer allocator.free(p);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-t", "-d", p }, null);
    defer res.deinit();

    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("first\n\nsecond\n\n", res.stdout);
}

test "pr --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "pr");
    defer allocator.free(bin);

    var res_h = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res_h.deinit();
    try testing.expectEqual(@as(u8, 0), res_h.exit_code);

    var res_v = try ctx.runCommand(&[_][]const u8{ bin, "--version" }, null);
    defer res_v.deinit();
    try testing.expectEqual(@as(u8, 0), res_v.exit_code);
}
