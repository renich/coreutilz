const std = @import("std");
const errors = @import("../utils/errors.zig");
const types = @import("chown/types.zig");
const spec_mod = @import("chown/spec.zig");
const engine = @import("chown/engine.zig");
const options_mod = @import("chown/options.zig");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "chown";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var parsed = try options_mod.parseArgs(name, false, args, allocator, stdout, stderr);
    defer parsed.operands.deinit(allocator);

    if (parsed.early_exit) |code| {
        stdout.flush() catch return 1;
        return code;
    }
    const rc = try dispatchChown(&parsed.cfg, parsed.ref_file, parsed.operands.items, allocator, stdout, stderr);
    stdout.flush() catch return 1;
    return rc;
}

fn dispatchChown(
    cfg: *types.ChownConfig,
    ref_file: ?[]const u8,
    operands: []const []const u8,
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    if (ref_file) |rf| {
        if (operands.len == 0) {
            try stderr.print("chown: missing operand\nTry 'chown --help' for more information.\n", .{});
            return 1;
        }
        try applyRefStats(cfg, rf, allocator, stderr);
        return engine.execute(cfg, operands, allocator, stdout, stderr);
    }
    if (operands.len == 0) {
        try stderr.print("chown: missing operand\nTry 'chown --help' for more information.\n", .{});
        return 1;
    }
    if (operands.len == 1) {
        try stderr.print("chown: missing operand after '{s}'\nTry 'chown --help' for more information.\n", .{operands[0]});
        return 1;
    }
    return executeWithUserSpec(cfg, operands[0], operands[1..], allocator, stdout, stderr);
}

fn executeWithUserSpec(
    cfg: *types.ChownConfig,
    user_spec_str: []const u8,
    targets: []const []const u8,
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    const spec = spec_mod.parseUserSpec(user_spec_str, false, allocator) catch |err| {
        if (err == error.InvalidUser) {
            try stderr.print("chown: invalid user: '{s}'\n", .{user_spec_str});
        } else if (err == error.InvalidGroup) {
            try stderr.print("chown: invalid group: '{s}'\n", .{user_spec_str});
        } else {
            try stderr.print("chown: invalid spec: '{s}'\n", .{user_spec_str});
        }
        return 1;
    };
    cfg.uid = spec.uid;
    cfg.gid = spec.gid;
    cfg.target_user_str = spec.user_name;
    cfg.target_group_str = spec.group_name;
    return engine.execute(cfg, targets, allocator, stdout, stderr);
}

fn applyRefStats(cfg: *types.ChownConfig, rf: []const u8, allocator: std.mem.Allocator, stderr: anytype) !void {
    const rf_z = try allocator.dupeZ(u8, rf);
    defer allocator.free(rf_z);
    var st: c.struct_stat = undefined;
    if (c.stat(rf_z.ptr, &st) != 0) {
        const err_str = std.mem.span(c.strerror(c.__errno_location().*));
        try stderr.print("chown: failed to get attributes of '{s}': {s}\n", .{ rf, err_str });
        return error.ReferenceStatFailed;
    }
    cfg.uid = st.st_uid;
    cfg.gid = st.st_gid;
    cfg.target_user_str = try spec_mod.uidToName(st.st_uid, allocator);
    cfg.target_group_str = try spec_mod.gidToName(st.st_gid, allocator);
}
