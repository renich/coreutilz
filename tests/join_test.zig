const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "join --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "join");
    defer allocator.free(bin);

    var res_h = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res_h.deinit();
    try testing.expectEqual(@as(u8, 0), res_h.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_h.stdout, 1, "Usage: join"));

    var res_v = try ctx.runCommand(&[_][]const u8{ bin, "--version" }, null);
    defer res_v.deinit();
    try testing.expectEqual(@as(u8, 0), res_v.exit_code);
}

test "join basic two files" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "join");
    defer allocator.free(bin);

    try ctx.writeFile("file1.txt", "1 apple\n2 banana\n3 cherry\n");
    try ctx.writeFile("file2.txt", "1 red\n2 yellow\n4 green\n");

    const p1 = try ctx.tmpPath("file1.txt");
    defer allocator.free(p1);
    const p2 = try ctx.tmpPath("file2.txt");
    defer allocator.free(p2);

    var res = try ctx.runCommand(&[_][]const u8{ bin, p1, p2 }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("1 apple red\n2 banana yellow\n", res.stdout);
}

test "join -t separator and -a unpairable" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "join");
    defer allocator.free(bin);

    try ctx.writeFile("f1.csv", "1,apple\n2,banana\n");
    try ctx.writeFile("f2.csv", "1,red\n3,blue\n");

    const p1 = try ctx.tmpPath("f1.csv");
    defer allocator.free(p1);
    const p2 = try ctx.tmpPath("f2.csv");
    defer allocator.free(p2);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-t,", "-a1", p1, p2 }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("1,apple,red\n2,banana\n", res.stdout);
}
