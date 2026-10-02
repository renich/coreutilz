const std = @import("std");
const c = @import("../compat/c.zig").c;
const signals = @import("kill/signals.zig");

pub const name: []const u8 = "kill";
pub const version: []const u8 = "0.1.0";

fn printHelp(stdout: anytype) !void {
    try stdout.print(
        \\Usage: {s} [-s SIGNAL | -SIGNAL] PID...
        \\  or:  {s} -l [SIGNAL]...
        \\  or:  {s} -t [SIGNAL]...
        \\Send signals to processes, or list signals.
        \\
        \\  -s, --signal=SIGNAL, -SIGNAL
        \\         specify the name or number of the signal to be sent
        \\  -l, --list
        \\         list signal names, or convert signal names to/from numbers
        \\  -t, --table
        \\         print a table of signal information
        \\      --help      display this help and exit
        \\      --version   output version information and exit
        \\
        \\SIGNAL may be a signal name like 'HUP', or a signal number like '1'.
        \\PID is an integer; if negative it identifies a process group.
        \\
    , .{ name, name, name });
}

const KillOptions = struct {
    list: bool = false,
    table: bool = false,
    signum: ?u8 = null,
};

fn parseSignalOption(arg: []const u8, opts: *KillOptions, stderr: anytype) !bool {
    if (opts.signum != null) {
        try stderr.print("{s}: multiple signals specified\n", .{name});
        return false;
    }
    const sig = signals.parseOperandToSig(arg);
    if (sig == null) {
        try stderr.print("{s}: {s}: invalid signal\n", .{ name, arg });
        return false;
    }
    opts.signum = sig;
    return true;
}

fn printNumericSignal(val_in: u32, stdout: anytype, stderr: anytype) !bool {
    var val = val_in;
    if (val > 128) {
        val = if (val >= 0xFF) (val & 0xFF) else (val & 0x7F);
    }
    if (val <= 64) {
        if (signals.signumToName(@intCast(val))) |n| {
            try stdout.print("{s}\n", .{n});
        } else {
            try stdout.print("{d}\n", .{val});
        }
        return true;
    }
    try stderr.print("{s}: {d}: invalid signal\n", .{ name, val_in });
    return false;
}

fn handleSingleListOperand(op: []const u8, stdout: anytype, stderr: anytype) !bool {
    if (op.len == 0) {
        try stderr.print("{s}: {s}: invalid signal\n", .{ name, op });
        return false;
    }
    var all_digits = true;
    for (op) |ch| if (!std.ascii.isDigit(ch)) {
        all_digits = false;
        break;
    };
    if (all_digits) {
        const val = std.fmt.parseInt(u32, op, 10) catch {
            try stderr.print("{s}: {s}: invalid signal\n", .{ name, op });
            return false;
        };
        return try printNumericSignal(val, stdout, stderr);
    }
    if (signals.nameToSignum(op)) |num| {
        try stdout.print("{d}\n", .{num});
        return true;
    }
    try stderr.print("{s}: {s}: invalid signal\n", .{ name, op });
    return false;
}

fn handleListOperands(operands: []const []const u8, stdout: anytype, stderr: anytype) !bool {
    var ok = true;
    for (operands) |op| {
        if (!try handleSingleListOperand(op, stdout, stderr)) ok = false;
    }
    return ok;
}

fn handleTableOperands(operands: []const []const u8, stdout: anytype, stderr: anytype) !bool {
    var ok = true;
    for (operands) |op| {
        const snum = signals.parseOperandToSig(op);
        if (snum) |num| {
            try signals.printTableRow(num, stdout);
        } else {
            try stderr.print("{s}: {s}: invalid signal\n", .{ name, op });
            ok = false;
        }
    }
    return ok;
}

fn sendSignals(signum: u8, pids: []const []const u8, stderr: anytype) !bool {
    var ok = true;
    for (pids) |p_str| {
        const pid = std.fmt.parseInt(c_int, p_str, 10) catch {
            try stderr.print("{s}: {s}: invalid process id\n", .{ name, p_str });
            ok = false;
            continue;
        };
        if (c.kill(pid, @as(c_int, signum)) != 0) {
            const err_num = c.__errno_location().*;
            const err_str = std.mem.span(c.strerror(err_num));
            if (err_num == c.EINVAL) {
                try stderr.print("{s}: {d}: {s}\n", .{ name, signum, err_str });
            } else {
                try stderr.print("{s}: {s}: {s}\n", .{ name, p_str, err_str });
            }
            ok = false;
        }
    }
    return ok;
}

fn parseOptFlag(arg: []const u8, i: *usize, args: [][]const u8, opts: *KillOptions, stderr: anytype) !?u8 {
    if (std.mem.eql(u8, arg, "-l") or std.mem.eql(u8, arg, "--list")) {
        if (opts.list or opts.table) {
            try stderr.print("{s}: multiple -l or -t options specified\n", .{name});
            return 1;
        }
        opts.list = true;
    } else if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--table") or std.mem.eql(u8, arg, "-L")) {
        if (opts.list or opts.table) {
            try stderr.print("{s}: multiple -l or -t options specified\n", .{name});
            return 1;
        }
        opts.table = true;
    } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "-n")) {
        i.* += 1;
        if (i.* >= args.len or !try parseSignalOption(args[i.*], opts, stderr)) return 1;
    } else if (std.mem.startsWith(u8, arg, "--signal=")) {
        if (!try parseSignalOption(arg["--signal=".len..], opts, stderr)) return 1;
    } else if (std.mem.startsWith(u8, arg, "-s") or std.mem.startsWith(u8, arg, "-n")) {
        if (!try parseSignalOption(arg[2..], opts, stderr)) return 1;
    } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1 and i.* == 1) {
        const first_ch = arg[1];
        if (std.ascii.isDigit(first_ch) or std.ascii.isUpper(first_ch)) {
            if (!try parseSignalOption(arg[1..], opts, stderr)) return 1;
        } else {
            try stderr.print("{s}: invalid option -- '{c}'\nTry '{s} --help' for more information.\n", .{ name, first_ch, name });
            return 1;
        }
    } else return null;
    return 0;
}

fn parseArgs(
    args: [][]const u8,
    opts: *KillOptions,
    operands: *std.ArrayListUnmanaged([]const u8),
    alloc: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !?u8 {
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            while (i < args.len) : (i += 1) try operands.append(alloc, args[i]);
            break;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            try stdout.print("{s} (coreutilz) {s}\n", .{ name, version });
            return 0;
        } else if (try parseOptFlag(arg, &i, args, opts, stderr)) |status| {
            if (status != 0) return status;
        } else {
            try operands.append(alloc, arg);
        }
    }
    return null;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    var opts = KillOptions{};
    var operands: std.ArrayListUnmanaged([]const u8) = .empty;
    defer operands.deinit(allocator);

    if (try parseArgs(args, &opts, &operands, allocator, stdout, stderr)) |rc| {
        stdout.flush() catch return 1;
        stderr.flush() catch {};
        return rc;
    }

    if ((opts.list or opts.table) and opts.signum != null) {
        try stderr.print("{s}: cannot combine signal with -l or -t\n", .{name});
        stderr.flush() catch {};
        return 1;
    }

    var success = true;
    if (opts.list) {
        if (operands.items.len == 0) {
            try signals.listAllSignals(stdout);
        } else {
            success = try handleListOperands(operands.items, stdout, stderr);
        }
    } else if (opts.table) {
        if (operands.items.len == 0) {
            try signals.printAllTable(stdout);
        } else {
            success = try handleTableOperands(operands.items, stdout, stderr);
        }
    } else {
        if (operands.items.len == 0) {
            try stderr.print("{s}: no process ID specified\n", .{name});
            stderr.flush() catch {};
            return 1;
        }
        const sig = opts.signum orelse 15;
        success = try sendSignals(sig, operands.items, stderr);
    }

    stdout.flush() catch return 1;
    stderr.flush() catch {};
    return if (success) 0 else 1;
}
