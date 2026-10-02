const std = @import("std");
const types = @import("types.zig");
const spec_mod = @import("spec.zig");
const errors = @import("../../utils/errors.zig");
const help = @import("help.zig");

pub const ParsedArgs = struct {
    cfg: types.ChownConfig,
    ref_file: ?[]const u8 = null,
    operands: std.ArrayList([]const u8),
    early_exit: ?u8 = null,
};

pub fn parseArgs(
    cmd_name: []const u8,
    is_chgrp: bool,
    args: [][]const u8,
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !ParsedArgs {
    var res = ParsedArgs{
        .cfg = .{ .cmd_name = cmd_name, .is_chgrp = is_chgrp },
        .operands = .empty,
    };
    var explicit_deref: ?bool = null;
    var parsing_options = true;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (parsing_options and std.mem.eql(u8, arg, "--")) {
            parsing_options = false;
            continue;
        }
        if (parsing_options and std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            const cont = try handleOption(arg, &i, args, &res, &explicit_deref, allocator, stdout, stderr);
            if (!cont) return res;
        } else {
            try res.operands.append(allocator, arg);
        }
    }

    if (!finalizeSymlinkMode(&res.cfg, explicit_deref, stderr)) {
        res.early_exit = 1;
    }
    return res;
}

fn handleOption(
    arg: []const u8,
    i: *usize,
    args: [][]const u8,
    res: *ParsedArgs,
    explicit_deref: *?bool,
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !bool {
    if (std.mem.startsWith(u8, arg, "--")) {
        return handleLongOpt(arg, i, args, res, explicit_deref, allocator, stdout, stderr);
    }
    return handleShortOpts(arg[1..], res, explicit_deref, stderr);
}

fn handleLongOpt(
    arg: []const u8,
    i: *usize,
    args: [][]const u8,
    res: *ParsedArgs,
    explicit_deref: *?bool,
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !bool {
    if (std.mem.eql(u8, arg, "--help")) {
        try printHelp(res.cfg.is_chgrp, stdout);
        stdout.flush() catch {
            res.early_exit = 1;
            return false;
        };
        res.early_exit = 0;
        return false;
    } else if (std.mem.eql(u8, arg, "--version")) {
        try stdout.print("{s} (coreutilz) 0.1.0\n", .{res.cfg.cmd_name});
        stdout.flush() catch {
            res.early_exit = 1;
            return false;
        };
        res.early_exit = 0;
        return false;
    }
    return handleLongOtherOpt(arg, i, args, res, explicit_deref, allocator, stderr);
}

fn handleLongOtherOpt(
    arg: []const u8,
    i: *usize,
    args: [][]const u8,
    res: *ParsedArgs,
    explicit_deref: *?bool,
    allocator: std.mem.Allocator,
    stderr: anytype,
) !bool {
    if (std.mem.eql(u8, arg, "--changes")) {
        res.cfg.verbosity = .changes_only;
    } else if (std.mem.eql(u8, arg, "--verbose")) {
        res.cfg.verbosity = .high;
    } else if (std.mem.eql(u8, arg, "--silent") or std.mem.eql(u8, arg, "--quiet")) {
        res.cfg.silent = true;
    } else if (std.mem.eql(u8, arg, "--recursive")) {
        res.cfg.recurse = true;
    } else if (std.mem.eql(u8, arg, "--no-dereference")) {
        res.cfg.symlink_mode = .no_dereference;
        explicit_deref.* = false;
    } else if (std.mem.eql(u8, arg, "--dereference")) {
        res.cfg.symlink_mode = .dereference;
        explicit_deref.* = true;
    } else if (std.mem.eql(u8, arg, "--preserve-root")) {
        res.cfg.preserve_root = true;
    } else if (std.mem.eql(u8, arg, "--no-preserve-root")) {
        res.cfg.preserve_root = false;
    } else {
        return handleLongRefFromOpt(arg, i, args, res, allocator, stderr);
    }
    return true;
}

fn handleLongRefFromOpt(
    arg: []const u8,
    i: *usize,
    args: [][]const u8,
    res: *ParsedArgs,
    allocator: std.mem.Allocator,
    stderr: anytype,
) !bool {
    if (std.mem.startsWith(u8, arg, "--reference=") or std.mem.eql(u8, arg, "--reference")) {
        return handleReferenceOpt(arg, i, args, res, stderr);
    } else if (std.mem.startsWith(u8, arg, "--from=") or std.mem.eql(u8, arg, "--from")) {
        return handleFromOpt(arg, i, args, res, allocator, stderr);
    } else {
        try stderr.print("{s}: unrecognized option '{s}'\nTry '{s} --help' for more information.\n", .{ res.cfg.cmd_name, arg, res.cfg.cmd_name });
        res.early_exit = 1;
        return false;
    }
    return true;
}

fn handleReferenceOpt(
    arg: []const u8,
    i: *usize,
    args: [][]const u8,
    res: *ParsedArgs,
    stderr: anytype,
) !bool {
    if (std.mem.startsWith(u8, arg, "--reference=")) {
        res.ref_file = arg["--reference=".len..];
        return true;
    }
    if (i.* + 1 >= args.len) {
        try errors.printErrorWithHelp(stderr, res.cfg.cmd_name, "option '--reference' requires an argument");
        res.early_exit = 1;
        return false;
    }
    i.* += 1;
    res.ref_file = args[i.*];
    return true;
}

fn handleFromOpt(
    arg: []const u8,
    i: *usize,
    args: [][]const u8,
    res: *ParsedArgs,
    allocator: std.mem.Allocator,
    stderr: anytype,
) !bool {
    const val = if (std.mem.startsWith(u8, arg, "--from="))
        arg["--from=".len..]
    else blk: {
        if (i.* + 1 >= args.len) {
            try errors.printErrorWithHelp(stderr, res.cfg.cmd_name, "option '--from' requires an argument");
            res.early_exit = 1;
            return false;
        }
        i.* += 1;
        break :blk args[i.*];
    };
    const from_spec = spec_mod.parseUserSpec(val, false, allocator) catch null;
    if (from_spec) |fs| {
        res.cfg.req_uid = fs.uid;
        res.cfg.req_gid = fs.gid;
    }
    return true;
}

fn handleShortOpts(
    opts: []const u8,
    res: *ParsedArgs,
    explicit_deref: *?bool,
    stderr: anytype,
) !bool {
    for (opts) |ch| {
        switch (ch) {
            'c' => res.cfg.verbosity = .changes_only,
            'v' => res.cfg.verbosity = .high,
            'f' => res.cfg.silent = true,
            'R' => res.cfg.recurse = true,
            'h' => {
                res.cfg.symlink_mode = .no_dereference;
                explicit_deref.* = false;
            },
            'H' => res.cfg.traverse_mode = .command_line,
            'L' => res.cfg.traverse_mode = .logical,
            'P' => res.cfg.traverse_mode = .physical,
            else => {
                try stderr.print("{s}: invalid option -- '{c}'\nTry '{s} --help' for more information.\n", .{ res.cfg.cmd_name, ch, res.cfg.cmd_name });
                res.early_exit = 1;
                return false;
            },
        }
    }
    return true;
}

fn finalizeSymlinkMode(cfg: *types.ChownConfig, explicit_deref: ?bool, stderr: anytype) bool {
    if (cfg.recurse) {
        if (cfg.traverse_mode == .physical) {
            if (explicit_deref == true) {
                stderr.print("{s}: -R --dereference requires either -H or -L\nTry '{s} --help' for more information.\n", .{ cfg.cmd_name, cfg.cmd_name }) catch {};
                return false;
            }
            cfg.affect_symlink_referent = false;
        } else {
            cfg.affect_symlink_referent = (explicit_deref != false);
        }
    } else {
        cfg.affect_symlink_referent = (explicit_deref != false);
    }
    return true;
}

fn printHelp(is_chgrp: bool, stdout: anytype) !void {
    if (is_chgrp) {
        return help.printChgrpHelp(stdout);
    } else {
        return help.printChownHelp(stdout);
    }
}
