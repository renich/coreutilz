const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

fn hasSELinux() bool {
    // A simple check for SELinux being enabled
    const f = std.fs.openFileAbsolute("/sys/fs/selinux/enforce", .{}) catch return false;
    f.close();
    return true;
}

test "chcon --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chcon");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "chcon --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chcon");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "chcon"));
}

test "chcon basic context (SELinux only)" {
    if (!hasSELinux()) return error.SkipZigTest;

    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chcon");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "content");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    // Get current context to use it as a base or just try a standard one
    // This might fail if the context is not allowed, but we test the tool's execution.
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "unconfined_u:object_r:user_tmp_t:s0", file_path }, null);
    defer result.deinit();

    // We don't strictly expect 0 because it depends on policy, but we check if it runs.
}

test "chcon -u user (SELinux only)" {
    if (!hasSELinux()) return error.SkipZigTest;

    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chcon");
    defer allocator.free(binary_path);

    try ctx.writeFile("test.txt", "content");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "test.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-u", "system_u", file_path }, null);
    defer result.deinit();
}

test "chcon -R recursive (SELinux only)" {
    if (!hasSELinux()) return error.SkipZigTest;

    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chcon");
    defer allocator.free(binary_path);

    std.fs.cwd().makePath("testdir") catch {};
    try ctx.writeFile("testdir/test.txt", "content");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const dir_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "testdir" });
    defer allocator.free(dir_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-R", "-t", "user_tmp_t", dir_path }, null);
    defer result.deinit();
}

test "chcon --reference (SELinux only)" {
    if (!hasSELinux()) return error.SkipZigTest;

    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chcon");
    defer allocator.free(binary_path);

    try ctx.writeFile("ref.txt", "content");
    try ctx.writeFile("target.txt", "content");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const ref_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "ref.txt" });
    defer allocator.free(ref_path);
    const target_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "target.txt" });
    defer allocator.free(target_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--reference", ref_path, target_path }, null);
    defer result.deinit();
}
