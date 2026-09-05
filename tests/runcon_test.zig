const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

fn hasSELinux() bool {
    const f = std.fs.openFileAbsolute("/sys/fs/selinux/enforce", .{}) catch return false;
    f.close();
    return true;
}

test "runcon --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "runcon");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "runcon --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "runcon");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "runcon"));
}

test "runcon basic (SELinux only)" {
    if (!hasSELinux()) return error.SkipZigTest;

    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "runcon");
    defer allocator.free(binary_path);

    // This is hard to test reliably without knowing the exact policy,
    // but we can try to run with the current context.
    // We can use 'id -Z' to get the current context.
    var id_result = try ctx.runCommand(&[_][]const u8{ "id", "-Z" }, null);
    defer id_result.deinit();

    if (id_result.exit_code == 0) {
        const current_context = std.mem.trim(u8, id_result.stdout, " \n\r\t");
        var result = try ctx.runCommand(&[_][]const u8{ binary_path, current_context, "id" }, null);
        defer result.deinit();
        try testing.expectEqual(@as(u8, 0), result.exit_code);
    }
}

test "runcon -t type (SELinux only)" {
    if (!hasSELinux()) return error.SkipZigTest;

    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "runcon");
    defer allocator.free(binary_path);

    // Test specifying just the type.
    // We use a common type like 'unconfined_t' if available.
    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-t", "unconfined_t", "id" }, null);
    defer result.deinit();
}

test "runcon -u user (SELinux only)" {
    if (!hasSELinux()) return error.SkipZigTest;

    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "runcon");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-u", "unconfined_u", "id" }, null);
    defer result.deinit();
}

test "runcon -r role (SELinux only)" {
    if (!hasSELinux()) return error.SkipZigTest;

    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "runcon");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-r", "unconfined_r", "id" }, null);
    defer result.deinit();
}
