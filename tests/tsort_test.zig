const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "tsort --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "tsort");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stdout, 1, "Usage: tsort"));
}

test "tsort basic pipeline" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "tsort");
    defer allocator.free(bin);

    const input = "a b\nb c\n";
    var res = try ctx.runCommand(&[_][]const u8{bin}, input);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);

    const out = res.stdout;
    const a_pos = std.mem.indexOf(u8, out, "a") orelse return error.TestExpectedEqual;
    const b_pos = std.mem.indexOf(u8, out, "b") orelse return error.TestExpectedEqual;
    const c_pos = std.mem.indexOf(u8, out, "c") orelse return error.TestExpectedEqual;
    try testing.expect(a_pos < b_pos);
    try testing.expect(b_pos < c_pos);
}

test "tsort loop detection" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "tsort");
    defer allocator.free(bin);

    const input = "a b\nb a\n";
    var res = try ctx.runCommand(&[_][]const u8{bin}, input);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 1), res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res.stderr, 1, "input contains a loop:"));
}
