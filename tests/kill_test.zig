const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "kill --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "kill");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, "Usage: kill"));

    var res_ver = try ctx.runCommand(&[_][]const u8{ bin, "--version" }, null);
    defer res_ver.deinit();
    try testing.expectEqual(@as(u8, 0), res_ver.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_ver.stdout, 1, "kill (coreutilz)"));
}

test "kill -l signal listing and conversion" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "kill");
    defer allocator.free(bin);

    var res_l = try ctx.runCommand(&[_][]const u8{ bin, "-l" }, null);
    defer res_l.deinit();
    try testing.expectEqual(@as(u8, 0), res_l.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_l.stdout, 1, "HUP\n"));
    try testing.expect(std.mem.containsAtLeast(u8, res_l.stdout, 1, "TERM\n"));

    var res_term = try ctx.runCommand(&[_][]const u8{ bin, "-l", "TERM" }, null);
    defer res_term.deinit();
    try testing.expectEqual(@as(u8, 0), res_term.exit_code);
    try testing.expectEqualStrings("15\n", res_term.stdout);

    var res_15 = try ctx.runCommand(&[_][]const u8{ bin, "-l", "15" }, null);
    defer res_15.deinit();
    try testing.expectEqual(@as(u8, 0), res_15.exit_code);
    try testing.expectEqualStrings("TERM\n", res_15.stdout);

    var res_143 = try ctx.runCommand(&[_][]const u8{ bin, "-l", "143" }, null);
    defer res_143.deinit();
    try testing.expectEqual(@as(u8, 0), res_143.exit_code);
    try testing.expectEqualStrings("TERM\n", res_143.stdout);
}

test "kill -0 on self pid" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "kill");
    defer allocator.free(bin);

    const pid = std.os.linux.getpid();
    var pid_buf: [32]u8 = undefined;
    const pid_str = try std.fmt.bufPrint(&pid_buf, "{d}", .{pid});

    var res = try ctx.runCommand(&[_][]const u8{ bin, "-0", pid_str }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
}
