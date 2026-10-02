const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "pathchk --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "pathchk");
    defer allocator.free(bin);

    var res_help = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
    defer res_help.deinit();
    try testing.expectEqual(@as(u8, 0), res_help.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_help.stdout, 1, "Usage: pathchk"));

    var res_ver = try ctx.runCommand(&[_][]const u8{ bin, "--version" }, null);
    defer res_ver.deinit();
    try testing.expectEqual(@as(u8, 0), res_ver.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_ver.stdout, 1, "pathchk (coreutilz)"));
}

test "pathchk basic valid path" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "pathchk");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "foo/bar/baz.txt" }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
}

test "pathchk -p portability checks" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "pathchk");
    defer allocator.free(bin);

    // Character '$' is not portable
    var res_char = try ctx.runCommand(&[_][]const u8{ bin, "-p", "hello$world" }, null);
    defer res_char.deinit();
    try testing.expectEqual(@as(u8, 1), res_char.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_char.stderr, 1, "non-portable character"));

    // Exceeding 14 chars component
    var res_len = try ctx.runCommand(&[_][]const u8{ bin, "-p", "this_component_is_way_too_long" }, null);
    defer res_len.deinit();
    try testing.expectEqual(@as(u8, 1), res_len.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_len.stderr, 1, "limit 14 exceeded"));
}

test "pathchk -P empty or leading hyphen" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "pathchk");
    defer allocator.free(bin);

    var res_empty = try ctx.runCommand(&[_][]const u8{ bin, "-P", "" }, null);
    defer res_empty.deinit();
    try testing.expectEqual(@as(u8, 1), res_empty.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_empty.stderr, 1, "empty file name"));

    var res_hyphen = try ctx.runCommand(&[_][]const u8{ bin, "-P", "--", "-hyphen" }, null);
    defer res_hyphen.deinit();
    try testing.expectEqual(@as(u8, 1), res_hyphen.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, res_hyphen.stderr, 1, "leading '-' in a component"));
}
