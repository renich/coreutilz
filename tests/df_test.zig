const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "df basic on current directory" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "df");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "." }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "Filesystem") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "1K-blocks") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "Mounted on") != null);
}

test "df -P portability mode" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "df");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-P", "." }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "1024-blocks") != null);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "Capacity") != null);
}

test "df -h and -H human readable" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "df");
    defer allocator.free(binary_path);

    var res_h = try ctx.runCommand(&[_][]const u8{ binary_path, "-h", "." }, null);
    defer res_h.deinit();
    try testing.expectEqual(@as(u8, 0), res_h.exit_code);
    try testing.expect(std.mem.indexOf(u8, res_h.stdout, "Size") != null);

    var res_si = try ctx.runCommand(&[_][]const u8{ binary_path, "-H", "." }, null);
    defer res_si.deinit();
    try testing.expectEqual(@as(u8, 0), res_si.exit_code);
    try testing.expect(std.mem.indexOf(u8, res_si.stdout, "Size") != null);
}

test "df -T print type and -i inodes" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "df");
    defer allocator.free(binary_path);

    var res_t = try ctx.runCommand(&[_][]const u8{ binary_path, "-T", "." }, null);
    defer res_t.deinit();
    try testing.expectEqual(@as(u8, 0), res_t.exit_code);
    try testing.expect(std.mem.indexOf(u8, res_t.stdout, "Type") != null);

    var res_i = try ctx.runCommand(&[_][]const u8{ binary_path, "-i", "." }, null);
    defer res_i.deinit();
    try testing.expectEqual(@as(u8, 0), res_i.exit_code);
    try testing.expect(std.mem.indexOf(u8, res_i.stdout, "Inodes") != null);
}

test "df --output custom fields and mutual exclusion" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "df");
    defer allocator.free(binary_path);

    var res_out = try ctx.runCommand(&[_][]const u8{ binary_path, "--output=source,target,pcent", "." }, null);
    defer res_out.deinit();
    try testing.expectEqual(@as(u8, 0), res_out.exit_code);
    try testing.expect(std.mem.indexOf(u8, res_out.stdout, "Filesystem") != null);
    try testing.expect(std.mem.indexOf(u8, res_out.stdout, "Mounted on") != null);
    try testing.expect(std.mem.indexOf(u8, res_out.stdout, "Use%") != null);
    try testing.expect(std.mem.indexOf(u8, res_out.stdout, "1K-blocks") == null);

    var res_ex = try ctx.runCommand(&[_][]const u8{ binary_path, "-i", "--output", "." }, null);
    defer res_ex.deinit();
    try testing.expectEqual(@as(u8, 1), res_ex.exit_code);
    try testing.expect(std.mem.indexOf(u8, res_ex.stderr, "mutually exclusive") != null);
}

test "df --total appends total row" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "df");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--total", "." }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.indexOf(u8, result.stdout, "total") != null);
}

test "df non-existent file or fs type reports error" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "df");
    defer allocator.free(binary_path);

    var res_fnf = try ctx.runCommand(&[_][]const u8{ binary_path, "_non_existent_file_" }, null);
    defer res_fnf.deinit();
    try testing.expectEqual(@as(u8, 1), res_fnf.exit_code);
    try testing.expect(std.mem.indexOf(u8, res_fnf.stderr, "No such file or directory") != null);

    var res_fs = try ctx.runCommand(&[_][]const u8{ binary_path, "-t", "_unknown_fs_type_" }, null);
    defer res_fs.deinit();
    try testing.expectEqual(@as(u8, 1), res_fs.exit_code);
    try testing.expect(std.mem.indexOf(u8, res_fs.stderr, "no file systems processed") != null);
}

test "df -x (exclude type)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "df");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-x", "nonexistent_fs_type_999", "." }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "df --help" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "df");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "Usage:"));
}

test "df --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "df");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "df"));
}
