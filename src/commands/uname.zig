const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "uname";
pub const version: []const u8 = "0.1.0";

const UnameOptions = struct {
    kernel_name: bool = false,
    nodename: bool = false,
    kernel_release: bool = false,
    kernel_version: bool = false,
    machine: bool = false,
    processor: bool = false,
    hardware_platform: bool = false,
    operating_system: bool = false,
    all: bool = false,
};

fn parseShortOpt(ch: u8, opts: *UnameOptions) bool {
    switch (ch) {
        'a' => {
            opts.all = true;
            opts.kernel_name = true;
            opts.nodename = true;
            opts.kernel_release = true;
            opts.kernel_version = true;
            opts.machine = true;
            opts.processor = true;
            opts.hardware_platform = true;
            opts.operating_system = true;
        },
        's' => opts.kernel_name = true,
        'n' => opts.nodename = true,
        'r' => opts.kernel_release = true,
        'v' => opts.kernel_version = true,
        'm' => opts.machine = true,
        'p' => opts.processor = true,
        'i' => opts.hardware_platform = true,
        'o' => opts.operating_system = true,
        else => return false,
    }
    return true;
}

fn parseLongOpt(arg: []const u8, opts: *UnameOptions) bool {
    if (std.mem.eql(u8, arg, "--all")) return parseShortOpt('a', opts);
    if (std.mem.eql(u8, arg, "--kernel-name")) {
        opts.kernel_name = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--nodename")) {
        opts.nodename = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--kernel-release")) {
        opts.kernel_release = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--kernel-version")) {
        opts.kernel_version = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--machine")) {
        opts.machine = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--processor")) {
        opts.processor = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--hardware-platform")) {
        opts.hardware_platform = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--operating-system")) {
        opts.operating_system = true;
        return true;
    }
    return false;
}

fn parseOptions(args: [][]const u8, opts: *UnameOptions, stdout: anytype, stderr: anytype) !?u8 {
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try stdout.print("Usage: uname [OPTION]...\nPrint certain system information.  With no OPTION, same as -s.\n", .{});
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("uname (coreutilz) {s}\n", .{version});
            return 0;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            if (!parseLongOpt(arg, opts)) {
                try stderr.print("uname: unrecognized option '{s}'\nTry 'uname --help' for more information.\n", .{arg});
                return 1;
            }
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            for (arg[1..]) |ch| {
                if (!parseShortOpt(ch, opts)) {
                    try stderr.print("uname: invalid option -- '{c}'\nTry 'uname --help' for more information.\n", .{ch});
                    return 1;
                }
            }
        } else {
            try stderr.print("uname: extra operand '{s}'\nTry 'uname --help' for more information.\n", .{arg});
            return 1;
        }
    }
    return null;
}

fn printField(stdout: anytype, first: *bool, val: []const u8) !void {
    if (!first.*) try stdout.writeByte(' ');
    first.* = false;
    try stdout.print("{s}", .{val});
}

fn printUnameFields(opts: *const UnameOptions, uts: *const c.struct_utsname, stdout: anytype) !void {
    const s_name = std.mem.sliceTo(&uts.sysname, 0);
    const n_name = std.mem.sliceTo(&uts.nodename, 0);
    const r_name = std.mem.sliceTo(&uts.release, 0);
    const v_name = std.mem.sliceTo(&uts.version, 0);
    const m_name = std.mem.sliceTo(&uts.machine, 0);

    var first = true;
    if (opts.kernel_name) try printField(stdout, &first, s_name);
    if (opts.nodename) try printField(stdout, &first, n_name);
    if (opts.kernel_release) try printField(stdout, &first, r_name);
    if (opts.kernel_version) try printField(stdout, &first, v_name);
    if (opts.machine) try printField(stdout, &first, m_name);
    if (opts.processor and !opts.all) try printField(stdout, &first, "unknown");
    if (opts.hardware_platform and !opts.all) try printField(stdout, &first, "unknown");
    if (opts.operating_system) try printField(stdout, &first, "GNU/Linux");
    try stdout.writeByte('\n');
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    _ = allocator;
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    var opts = UnameOptions{};
    if (try parseOptions(args, &opts, stdout, stderr)) |rc| {
        stdout.flush() catch return 1;
        stderr.flush() catch return 1;
        return rc;
    }

    const any_sel = opts.kernel_name or opts.nodename or opts.kernel_release or
        opts.kernel_version or opts.machine or opts.processor or
        opts.hardware_platform or opts.operating_system;
    if (!any_sel) opts.kernel_name = true;

    var uts: c.struct_utsname = undefined;
    if (c.uname(&uts) != 0) return 1;

    try printUnameFields(&opts, &uts, stdout);
    stdout.flush() catch return 1;
    return 0;
}
