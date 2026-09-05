const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "nohup basic command execution" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nohup");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "echo", "hello" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("hello\n", result.stdout);
}

test "nohup ignores SIGHUP" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nohup");
    defer allocator.free(binary_path);

    // Run a command that waits
    var child = std.process.Child.init(&[_][]const u8{ binary_path, "sleep", "60" }, allocator);
    try child.spawn();

    // Send SIGHUP to the nohup process
    _ = std.os.linux.kill(@intCast(child.id), std.os.linux.SIG.HUP);

    // Give it a moment
    std.Thread.sleep(100 * std.time.ns_per_ms);

    // Check if it's still running (kill with 0 signal)
    const kill_res = std.os.linux.kill(@intCast(child.id), 0);
    try testing.expectEqual(@as(usize, 0), kill_res);

    // Clean up
    try std.os.linux.kill(@intCast(child.id), std.os.linux.SIG.TERM);
    _ = try child.wait();
}

test "nohup redirects to nohup.out" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nohup");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    // To test nohup.out creation, we need stdout to not be a pipe.
    // We'll run it with stdout/stderr ignored in the Child, which should trigger nohup's redirection.
    var child = std.process.Child.init(&[_][]const u8{ binary_path, "echo", "test-nohup-out" }, allocator);
    child.cwd = tmp_path;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    try child.spawn();
    _ = try child.wait();

    // Check for nohup.out in the temp directory
    const nohup_out_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "nohup.out" });
    defer allocator.free(nohup_out_path);

    const content = try ctx.readFile("nohup.out");
    defer allocator.free(content);

    try testing.expect(std.mem.containsAtLeast(u8, content, 1, "test-nohup-out"));
}

test "nohup with existing output file" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nohup");
    defer allocator.free(binary_path);

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);

    // Pre-create nohup.out
    try ctx.writeFile("nohup.out", "existing\n");

    var child = std.process.Child.init(&[_][]const u8{ binary_path, "echo", "appended" }, allocator);
    child.cwd = tmp_path;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;

    try child.spawn();
    _ = try child.wait();

    const content = try ctx.readFile("nohup.out");
    defer allocator.free(content);

    try testing.expect(std.mem.containsAtLeast(u8, content, 1, "existing"));
    try testing.expect(std.mem.containsAtLeast(u8, content, 1, "appended"));
}

test "nohup --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nohup");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "nohup --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nohup");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "nohup"));
}
