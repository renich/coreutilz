const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

// Test data ported from coreutils/tests/misc/link.sh
test "link creates hard link" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "link");
    defer allocator.free(binary_path);

    try ctx.writeFile("target.txt", "content");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const target = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "target.txt" });
    defer allocator.free(target);
    const linkname = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "hardlink" });
    defer allocator.free(linkname);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, target, linkname }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);

    // Verify link was created by reading content
    const linked_content = try ctx.readFile("hardlink");
    defer allocator.free(linked_content);
    try testing.expectEqualStrings("content", linked_content);
}

test "link fails if target missing" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "link");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const target = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "nonexistent" });
    defer allocator.free(target);
    const linkname = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "link" });
    defer allocator.free(linkname);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, target, linkname }, null);
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
}

test "link fails with too few arguments" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "link");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "target" }, null);
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
}

test "link fails with too many arguments" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "link");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const target = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "target" });
    defer allocator.free(target);
    const linkname = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "link" });
    defer allocator.free(linkname);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, target, linkname, "extra" }, null);
    defer result.deinit();

    try testing.expect(result.exit_code != 0);
}

test "link --help option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "link");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "link --version option" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "link");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "link"));
}
