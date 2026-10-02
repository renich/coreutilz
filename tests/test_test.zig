const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "test --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "test");
    defer allocator.free(bin);

    var res_h = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res_h.deinit();
    try testing.expectEqual(@as(u8, 0), res_h.exit_code);

    var res_v = try ctx.runCommand(&[_][]const u8{ bin, "--version" }, null);
    defer res_v.deinit();
    try testing.expectEqual(@as(u8, 0), res_v.exit_code);
}

test "test basic string and int operators" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "test");
    defer allocator.free(bin);

    // true: 1 -eq 1
    var res1 = try ctx.runCommand(&[_][]const u8{ bin, "1", "-eq", "1" }, null);
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);

    // false: 1 -eq 2
    var res2 = try ctx.runCommand(&[_][]const u8{ bin, "1", "-eq", "2" }, null);
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 1), res2.exit_code);

    // -n non-empty
    var res3 = try ctx.runCommand(&[_][]const u8{ bin, "-n", "hello" }, null);
    defer res3.deinit();
    try testing.expectEqual(@as(u8, 0), res3.exit_code);

    // -z empty
    var res4 = try ctx.runCommand(&[_][]const u8{ bin, "-z", "" }, null);
    defer res4.deinit();
    try testing.expectEqual(@as(u8, 0), res4.exit_code);
}

test "test file tests -d and -f" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "test");
    defer allocator.free(bin);

    // /etc is a directory
    var res1 = try ctx.runCommand(&[_][]const u8{ bin, "-d", "/etc" }, null);
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);

    // /etc is not a regular file
    var res2 = try ctx.runCommand(&[_][]const u8{ bin, "-f", "/etc" }, null);
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 1), res2.exit_code);
}

test "[ bracket syntax" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "[");
    defer allocator.free(bin);

    var res1 = try ctx.runCommand(&[_][]const u8{ bin, "1", "-eq", "1", "]" }, null);
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 0), res1.exit_code);

    // Missing ']'
    var res2 = try ctx.runCommand(&[_][]const u8{ bin, "1", "-eq", "1" }, null);
    defer res2.deinit();
    try testing.expectEqual(@as(u8, 2), res2.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res2.stderr, 1, "missing ']'"));
}
