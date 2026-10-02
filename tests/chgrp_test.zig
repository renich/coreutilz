const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "chgrp --preserve-root on root aborts with failsafe" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chgrp");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-R", "--preserve-root", "0", "/" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "it is dangerous to operate recursively on '/'") != null);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "use --no-preserve-root to override this failsafe") != null);
}

test "chgrp missing operand emits diagnostic" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chgrp");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{binary_path}, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "missing operand") != null);
}

test "chgrp invalid group reports error" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chgrp");
    defer allocator.free(binary_path);

    try ctx.writeFile("file.txt", "a");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "file.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "nonexistent_grp_9999999", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "invalid group") != null);
}

test "chgrp -R --dereference without -H or -L errors" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chgrp");
    defer allocator.free(binary_path);

    try ctx.writeFile("f.txt", "1");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "f.txt" });
    defer allocator.free(file_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-R", "--dereference", "0", file_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stderr, "-R --dereference requires either -H or -L") != null);
}

test "chgrp --reference file" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chgrp");
    defer allocator.free(binary_path);

    try ctx.writeFile("reference.txt", "reference content\n");
    try ctx.writeFile("target.txt", "target content\n");

    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const ref_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "reference.txt" });
    defer allocator.free(ref_path);
    const target_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "target.txt" });
    defer allocator.free(target_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--reference", ref_path, target_path }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "chgrp --help option" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chgrp");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "chgrp --version option" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "chgrp");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "chgrp"));
}
