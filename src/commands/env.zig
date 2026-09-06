const std = @import("std");
const errors = @import("../utils/errors.zig");

const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "env";
pub const version: []const u8 = "0.1.0";

const DEFAULT_SIGNAL_OPTION: c_int = 256;
const IGNORE_SIGNAL_OPTION: c_int = 257;
const BLOCK_SIGNAL_OPTION: c_int = 258;
const LIST_SIGNAL_HANDLING_OPTION: c_int = 259;

const SignalMode = enum {
    unchanged,
    default,
    default_noerr,
    ignore,
    ignore_noerr,
};

fn scanVarname(str: []const u8) ?usize {
    if (str.len < 3 or str[0] != '$' or str[1] != '{') return null;
    const first = str[2];
    if (!std.ascii.isAlphabetic(first) and first != '_') return null;
    var idx: usize = 3;
    while (idx < str.len) : (idx += 1) {
        const ch = str[idx];
        if (ch == '}') return idx;
        if (!std.ascii.isAlphanumeric(ch) and ch != '_') return null;
    }
    return null;
}

fn buildArgv(allocator: std.mem.Allocator, str: [:0]const u8, dev_debug: bool, stderr: anytype) !?std.ArrayList([:0]const u8) {
    var result: std.ArrayList([:0]const u8) = .empty;
    var current_arg: std.ArrayList(u8) = .empty;
    defer current_arg.deinit(allocator);

    var has_active_arg = false;
    var sep = true;
    var sq = false;
    var dq = false;

    var ptr: usize = 0;
    while (ptr < str.len) {
        const ch = str[ptr];
        switch (ch) {
            '\'' => {
                if (dq) {
                    if (sep) {
                        if (has_active_arg) {
                            try result.append(allocator, try current_arg.toOwnedSliceSentinel(allocator, 0));
                        }
                        has_active_arg = true;
                        sep = false;
                    }
                    try current_arg.append(allocator, '\'');
                    ptr += 1;
                    continue;
                }
                sq = !sq;
                if (sep) {
                    if (has_active_arg) {
                        try result.append(allocator, try current_arg.toOwnedSliceSentinel(allocator, 0));
                    }
                    has_active_arg = true;
                    sep = false;
                }
                ptr += 1;
                continue;
            },
            '"' => {
                if (sq) {
                    if (sep) {
                        if (has_active_arg) {
                            try result.append(allocator, try current_arg.toOwnedSliceSentinel(allocator, 0));
                        }
                        has_active_arg = true;
                        sep = false;
                    }
                    try current_arg.append(allocator, '"');
                    ptr += 1;
                    continue;
                }
                dq = !dq;
                if (sep) {
                    if (has_active_arg) {
                        try result.append(allocator, try current_arg.toOwnedSliceSentinel(allocator, 0));
                    }
                    has_active_arg = true;
                    sep = false;
                }
                ptr += 1;
                continue;
            },
            ' ', '\t', '\n', 0x0b, 0x0c, '\r' => {
                if (sq or dq) {
                    try current_arg.append(allocator, ch);
                    ptr += 1;
                    continue;
                }
                sep = true;
                while (ptr < str.len) : (ptr += 1) {
                    const c_ch = str[ptr];
                    if (c_ch != ' ' and c_ch != '\t' and c_ch != '\n' and c_ch != 0x0b and c_ch != 0x0c and c_ch != '\r') break;
                }
                continue;
            },
            '#' => {
                if (sep and !sq and !dq) {
                    break;
                }
                if (sep) {
                    if (has_active_arg) {
                        try result.append(allocator, try current_arg.toOwnedSliceSentinel(allocator, 0));
                    }
                    has_active_arg = true;
                    sep = false;
                }
                try current_arg.append(allocator, '#');
                ptr += 1;
                continue;
            },
            '\\' => {
                if (sq) {
                    if (ptr + 1 < str.len and (str[ptr + 1] == '\\' or str[ptr + 1] == '\'')) {
                        ptr += 1;
                        try current_arg.append(allocator, str[ptr]);
                        ptr += 1;
                        continue;
                    }
                    try current_arg.append(allocator, '\\');
                    ptr += 1;
                    continue;
                }
                ptr += 1;
                if (ptr >= str.len) {
                    try stderr.print("env: invalid backslash at end of string in -S\n", .{});
                    return null;
                }
                const next = str[ptr];
                switch (next) {
                    '"', '#', '$', '\'', '\\' => {
                        if (sep) {
                            if (has_active_arg) {
                                try result.append(allocator, try current_arg.toOwnedSliceSentinel(allocator, 0));
                            }
                            has_active_arg = true;
                            sep = false;
                        }
                        try current_arg.append(allocator, next);
                        ptr += 1;
                    },
                    '_' => {
                        if (!dq) {
                            ptr += 1;
                            sep = true;
                            continue;
                        }
                        if (sep) {
                            if (has_active_arg) {
                                try result.append(allocator, try current_arg.toOwnedSliceSentinel(allocator, 0));
                            }
                            has_active_arg = true;
                            sep = false;
                        }
                        try current_arg.append(allocator, ' ');
                        ptr += 1;
                    },
                    'c' => {
                        if (dq) {
                            try stderr.print("env: '\\c' must not appear in double-quoted -S string\n", .{});
                            return null;
                        }
                        break;
                    },
                    'f' => {
                        if (sep) {
                            if (has_active_arg) {
                                try result.append(allocator, try current_arg.toOwnedSliceSentinel(allocator, 0));
                            }
                            has_active_arg = true;
                            sep = false;
                        }
                        try current_arg.append(allocator, 0x0c);
                        ptr += 1;
                    },
                    'n' => {
                        if (sep) {
                            if (has_active_arg) {
                                try result.append(allocator, try current_arg.toOwnedSliceSentinel(allocator, 0));
                            }
                            has_active_arg = true;
                            sep = false;
                        }
                        try current_arg.append(allocator, '\n');
                        ptr += 1;
                    },
                    'r' => {
                        if (sep) {
                            if (has_active_arg) {
                                try result.append(allocator, try current_arg.toOwnedSliceSentinel(allocator, 0));
                            }
                            has_active_arg = true;
                            sep = false;
                        }
                        try current_arg.append(allocator, '\r');
                        ptr += 1;
                    },
                    't' => {
                        if (sep) {
                            if (has_active_arg) {
                                try result.append(allocator, try current_arg.toOwnedSliceSentinel(allocator, 0));
                            }
                            has_active_arg = true;
                            sep = false;
                        }
                        try current_arg.append(allocator, '\t');
                        ptr += 1;
                    },
                    'v' => {
                        if (sep) {
                            if (has_active_arg) {
                                try result.append(allocator, try current_arg.toOwnedSliceSentinel(allocator, 0));
                            }
                            has_active_arg = true;
                            sep = false;
                        }
                        try current_arg.append(allocator, 0x0b);
                        ptr += 1;
                    },
                    else => {
                        try stderr.print("env: invalid sequence '\\{c}' in -S\n", .{next});
                        return null;
                    },
                }
            },
            '$' => {
                if (sq) {
                    if (sep) {
                        if (has_active_arg) {
                            try result.append(allocator, try current_arg.toOwnedSliceSentinel(allocator, 0));
                        }
                        has_active_arg = true;
                        sep = false;
                    }
                    try current_arg.append(allocator, '$');
                    ptr += 1;
                    continue;
                }
                const end_pos = scanVarname(str[ptr..]);
                if (end_pos == null) {
                    try stderr.print("env: only ${{VARNAME}} expansion is supported, error at: {s}\n", .{str[ptr..]});
                    return null;
                }
                const vname = str[ptr + 2 .. ptr + end_pos.?];
                const vname_z = try allocator.dupeZ(u8, vname);
                defer allocator.free(vname_z);
                const val = c.getenv(vname_z.ptr);
                if (val != null) {
                    if (sep) {
                        if (has_active_arg) {
                            try result.append(allocator, try current_arg.toOwnedSliceSentinel(allocator, 0));
                        }
                        has_active_arg = true;
                        sep = false;
                    }
                    const v_span = std.mem.span(val);
                    if (dev_debug) {
                        try stderr.print("expanding ${{{s}}} into '{s}'\n", .{ vname, v_span });
                    }
                    try current_arg.appendSlice(allocator, v_span);
                } else {
                    if (dev_debug) {
                        try stderr.print("replacing ${{{s}}} with null string\n", .{vname});
                    }
                }
                ptr += end_pos.? + 1;
                continue;
            },
            else => {
                if (sep) {
                    if (has_active_arg) {
                        try result.append(allocator, try current_arg.toOwnedSliceSentinel(allocator, 0));
                    }
                    has_active_arg = true;
                    sep = false;
                }
                try current_arg.append(allocator, ch);
                ptr += 1;
            },
        }
    }

    if (sq or dq) {
        try stderr.print("env: no terminating quote in -S string\n", .{});
        return null;
    }

    if (has_active_arg) {
        try result.append(allocator, try current_arg.toOwnedSliceSentinel(allocator, 0));
    }

    return result;
}

fn parseSignal(name_str: []const u8) ?c_int {
    var s = name_str;
    if (std.mem.startsWith(u8, s, "SIG") or std.mem.startsWith(u8, s, "sig")) {
        s = s[3..];
    }
    if (std.ascii.eqlIgnoreCase(s, "HUP")) return c.SIGHUP;
    if (std.ascii.eqlIgnoreCase(s, "INT")) return c.SIGINT;
    if (std.ascii.eqlIgnoreCase(s, "QUIT")) return c.SIGQUIT;
    if (std.ascii.eqlIgnoreCase(s, "ILL")) return c.SIGILL;
    if (std.ascii.eqlIgnoreCase(s, "TRAP")) return c.SIGTRAP;
    if (std.ascii.eqlIgnoreCase(s, "ABRT") or std.ascii.eqlIgnoreCase(s, "IOT")) return c.SIGABRT;
    if (std.ascii.eqlIgnoreCase(s, "BUS")) return c.SIGBUS;
    if (std.ascii.eqlIgnoreCase(s, "FPE")) return c.SIGFPE;
    if (std.ascii.eqlIgnoreCase(s, "KILL")) return c.SIGKILL;
    if (std.ascii.eqlIgnoreCase(s, "USR1")) return c.SIGUSR1;
    if (std.ascii.eqlIgnoreCase(s, "SEGV")) return c.SIGSEGV;
    if (std.ascii.eqlIgnoreCase(s, "USR2")) return c.SIGUSR2;
    if (std.ascii.eqlIgnoreCase(s, "PIPE")) return c.SIGPIPE;
    if (std.ascii.eqlIgnoreCase(s, "ALRM")) return c.SIGALRM;
    if (std.ascii.eqlIgnoreCase(s, "TERM")) return c.SIGTERM;
    if (std.ascii.eqlIgnoreCase(s, "STKFLT")) return 16;
    if (std.ascii.eqlIgnoreCase(s, "CHLD") or std.ascii.eqlIgnoreCase(s, "CLD")) return c.SIGCHLD;
    if (std.ascii.eqlIgnoreCase(s, "CONT")) return c.SIGCONT;
    if (std.ascii.eqlIgnoreCase(s, "STOP")) return c.SIGSTOP;
    if (std.ascii.eqlIgnoreCase(s, "TSTP")) return c.SIGTSTP;
    if (std.ascii.eqlIgnoreCase(s, "TTIN")) return c.SIGTTIN;
    if (std.ascii.eqlIgnoreCase(s, "TTOU")) return c.SIGTTOU;
    if (std.ascii.eqlIgnoreCase(s, "URG")) return c.SIGURG;
    if (std.ascii.eqlIgnoreCase(s, "XCPU")) return c.SIGXCPU;
    if (std.ascii.eqlIgnoreCase(s, "XFSZ")) return c.SIGXFSZ;
    if (std.ascii.eqlIgnoreCase(s, "VTALRM")) return c.SIGVTALRM;
    if (std.ascii.eqlIgnoreCase(s, "PROF")) return c.SIGPROF;
    if (std.ascii.eqlIgnoreCase(s, "WINCH")) return c.SIGWINCH;
    if (std.ascii.eqlIgnoreCase(s, "POLL") or std.ascii.eqlIgnoreCase(s, "IO")) return c.SIGPOLL;
    if (std.ascii.eqlIgnoreCase(s, "PWR")) return c.SIGPWR;
    if (std.ascii.eqlIgnoreCase(s, "SYS")) return c.SIGSYS;

    const rtmin = c.__libc_current_sigrtmin();
    const rtmax = c.__libc_current_sigrtmax();
    if (std.ascii.eqlIgnoreCase(s, "RTMIN")) return rtmin;
    if (std.ascii.eqlIgnoreCase(s, "RTMAX")) return rtmax;
    if (std.ascii.startsWithIgnoreCase(s, "RTMIN+")) {
        const offset = std.fmt.parseInt(c_int, s["RTMIN+".len..], 10) catch return null;
        if (rtmin + offset <= rtmax) return rtmin + offset;
        return null;
    }
    if (std.ascii.startsWithIgnoreCase(s, "RTMAX-")) {
        const offset = std.fmt.parseInt(c_int, s["RTMAX-".len..], 10) catch return null;
        if (rtmax - offset >= rtmin) return rtmax - offset;
        return null;
    }

    if (std.fmt.parseInt(c_int, s, 10)) |num| {
        if (num > 0 and num <= 64) return num;
    } else |_| {}
    return null;
}

fn signalName(signum: c_int) []const u8 {
    return switch (signum) {
        c.SIGHUP => "HUP",
        c.SIGINT => "INT",
        c.SIGQUIT => "QUIT",
        c.SIGILL => "ILL",
        c.SIGTRAP => "TRAP",
        c.SIGABRT => "ABRT",
        c.SIGBUS => "BUS",
        c.SIGFPE => "FPE",
        c.SIGKILL => "KILL",
        c.SIGUSR1 => "USR1",
        c.SIGSEGV => "SEGV",
        c.SIGUSR2 => "USR2",
        c.SIGPIPE => "PIPE",
        c.SIGALRM => "ALRM",
        c.SIGTERM => "TERM",
        16 => "STKFLT",
        c.SIGCHLD => "CHLD",
        c.SIGCONT => "CONT",
        c.SIGSTOP => "STOP",
        c.SIGTSTP => "TSTP",
        c.SIGTTIN => "TTIN",
        c.SIGTTOU => "TTOU",
        c.SIGURG => "URG",
        c.SIGXCPU => "XCPU",
        c.SIGXFSZ => "XFSZ",
        c.SIGVTALRM => "VTALRM",
        c.SIGPROF => "PROF",
        c.SIGWINCH => "WINCH",
        c.SIGPOLL => "POLL",
        c.SIGPWR => "PWR",
        c.SIGSYS => "SYS",
        else => blk: {
            const rtmin = c.__libc_current_sigrtmin();
            const rtmax = c.__libc_current_sigrtmax();
            if (signum == rtmin) break :blk "RTMIN";
            if (signum == rtmax) break :blk "RTMAX";
            break :blk "UNKNOWN";
        },
    };
}

fn parseSignalActionParams(
    arg: ?[*:0]const u8,
    set_default: bool,
    signals: *[65]SignalMode,
    block_signals: *c.sigset_t,
    unblock_signals: *c.sigset_t,
    sig_mask_changed: *bool,
    stderr: anytype,
) !bool {
    if (arg == null) {
        for (1..65) |i| {
            signals[i] = if (set_default) .default_noerr else .ignore_noerr;
        }
        if (set_default) {
            _ = c.sigfillset(unblock_signals);
            _ = c.sigemptyset(block_signals);
            sig_mask_changed.* = true;
        }
        return true;
    }

    var it = std.mem.splitScalar(u8, std.mem.span(arg.?), ',');
    while (it.next()) |token| {
        if (token.len == 0) continue;
        const signum = parseSignal(token) orelse {
            try stderr.print("env: '{s}': invalid signal\nTry 'env --help' for more information.\n", .{token});
            return false;
        };
        if (signum <= 0 or signum > 64) {
            try stderr.print("env: '{s}': invalid signal\nTry 'env --help' for more information.\n", .{token});
            return false;
        }
        signals[@intCast(signum)] = if (set_default) .default else .ignore;
        if (set_default) {
            if (!sig_mask_changed.*) {
                _ = c.sigemptyset(block_signals);
                _ = c.sigemptyset(unblock_signals);
                sig_mask_changed.* = true;
            }
            _ = c.sigaddset(unblock_signals, signum);
            _ = c.sigdelset(block_signals, signum);
        }
    }
    return true;
}

fn parseBlockSignalParams(
    arg: ?[*:0]const u8,
    block: bool,
    block_signals: *c.sigset_t,
    unblock_signals: *c.sigset_t,
    sig_mask_changed: *bool,
    stderr: anytype,
) !bool {
    if (arg == null) {
        if (block) {
            _ = c.sigfillset(block_signals);
            _ = c.sigemptyset(unblock_signals);
        } else {
            _ = c.sigfillset(unblock_signals);
            _ = c.sigemptyset(block_signals);
        }
        sig_mask_changed.* = true;
        return true;
    }

    if (!sig_mask_changed.*) {
        _ = c.sigemptyset(block_signals);
        _ = c.sigemptyset(unblock_signals);
        sig_mask_changed.* = true;
    }

    var it = std.mem.splitScalar(u8, std.mem.span(arg.?), ',');
    while (it.next()) |token| {
        if (token.len == 0) continue;
        const signum = parseSignal(token) orelse {
            try stderr.print("env: '{s}': invalid signal\nTry 'env --help' for more information.\n", .{token});
            return false;
        };
        if (signum <= 0 or signum > 64) {
            try stderr.print("env: '{s}': invalid signal\nTry 'env --help' for more information.\n", .{token});
            return false;
        }
        if (block) {
            _ = c.sigaddset(block_signals, signum);
            _ = c.sigdelset(unblock_signals, signum);
        } else {
            _ = c.sigaddset(unblock_signals, signum);
            _ = c.sigdelset(block_signals, signum);
        }
    }
    return true;
}

fn resetSignalHandlers(signals: *const [65]SignalMode, dev_debug: bool, stderr: anytype) !u8 {
    for (1..65) |i_usize| {
        const i: c_int = @intCast(i_usize);
        if (signals[i_usize] == .unchanged) continue;
        const ignore_errors = (signals[i_usize] == .default_noerr or signals[i_usize] == .ignore_noerr);
        const set_to_default = (signals[i_usize] == .default or signals[i_usize] == .default_noerr);

        var act: c.struct_sigaction = std.mem.zeroes(c.struct_sigaction);
        var sig_err = c.sigaction(i, null, &act);
        if (sig_err != 0 and !ignore_errors) {
            const err = c.__errno_location().*;
            try stderr.print("env: failed to get signal action for signal {d}: {s}\n", .{ i, std.mem.span(c.strerror(err)) });
            return 125;
        }
        if (sig_err == 0) {
            act.__sigaction_handler.sa_handler = if (set_to_default) c.SIG_DFL else c.SIG_IGN;
            sig_err = c.sigaction(i, &act, null);
            if (sig_err != 0 and !ignore_errors) {
                const err = c.__errno_location().*;
                try stderr.print("env: failed to set signal action for signal {d}: {s}\n", .{ i, std.mem.span(c.strerror(err)) });
                return 125;
            }
        }
        if (dev_debug) {
            const sname = signalName(i);
            const act_name = if (set_to_default) "DEFAULT" else "IGNORE";
            const fail_str = if (sig_err != 0) " (failure ignored)" else "";
            try stderr.print("Reset signal {s} ({d}) to {s}{s}\n", .{ sname, i, act_name, fail_str });
        }
    }
    return 0;
}

fn setSignalProcMask(block_signals: *const c.sigset_t, unblock_signals: *const c.sigset_t, dev_debug: bool, stderr: anytype) !u8 {
    var set: c.sigset_t = undefined;
    _ = c.sigemptyset(&set);
    if (c.sigprocmask(0, null, &set) != 0) {
        const err = c.__errno_location().*;
        try stderr.print("env: failed to get signal process mask: {s}\n", .{std.mem.span(c.strerror(err))});
        return 125;
    }

    for (1..65) |i_usize| {
        const i: c_int = @intCast(i_usize);
        var debug_act: ?[]const u8 = null;
        if (c.sigismember(block_signals, i) != 0) {
            _ = c.sigaddset(&set, i);
            debug_act = "BLOCK";
        } else if (c.sigismember(unblock_signals, i) != 0) {
            _ = c.sigdelset(&set, i);
            debug_act = "UNBLOCK";
        }

        if (dev_debug and debug_act != null) {
            const sname = signalName(i);
            try stderr.print("signal {s} ({d}) mask set to {s}\n", .{ sname, i, debug_act.? });
        }
    }

    if (c.sigprocmask(c.SIG_SETMASK, &set, null) != 0) {
        const err = c.__errno_location().*;
        try stderr.print("env: failed to set signal process mask: {s}\n", .{std.mem.span(c.strerror(err))});
        return 125;
    }
    return 0;
}

fn listSignalHandling(stderr: anytype) !void {
    var set: c.sigset_t = undefined;
    _ = c.sigemptyset(&set);
    if (c.sigprocmask(0, null, &set) != 0) {
        const err = c.__errno_location().*;
        try stderr.print("env: failed to get signal process mask: {s}\n", .{std.mem.span(c.strerror(err))});
        return;
    }

    for (1..65) |i_usize| {
        const i: c_int = @intCast(i_usize);
        var act: c.struct_sigaction = undefined;
        if (c.sigaction(i, null, &act) != 0) continue;

        const is_ign = act.__sigaction_handler.sa_handler == c.SIG_IGN;
        const is_blk = c.sigismember(&set, i) != 0;

        if (!is_ign and !is_blk) continue;

        const sname = signalName(i);
        const blocked_str = if (is_blk) "BLOCK" else "";
        const connect_str = if (is_blk and is_ign) "," else "";
        const ignored_str = if (is_ign) "IGNORE" else "";

        try stderr.print("{s:<10} ({d:>2}): {s}{s}{s}\n", .{ sname, i, blocked_str, connect_str, ignored_str });
    }
    try stderr.flush();
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [65536]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var argv_list: std.ArrayList(?[*:0]u8) = .empty;
    defer argv_list.deinit(allocator);

    for (args) |a| {
        const a_z = try allocator.dupeZ(u8, a);
        try argv_list.append(allocator, a_z.ptr);
    }
    try argv_list.append(allocator, null);

    var dev_debug = false;
    var ignore_environment = false;
    var opt_nul_terminate_output = false;
    var newdir: ?[]const u8 = null;
    var argv0: ?[]const u8 = null;
    var list_signals = false;

    var usvars: std.ArrayList([]const u8) = .empty;
    defer usvars.deinit(allocator);

    var signals: [65]SignalMode = [_]SignalMode{.unchanged} ** 65;
    var block_signals: c.sigset_t = undefined;
    var unblock_signals: c.sigset_t = undefined;
    var sig_mask_changed = false;
    _ = c.sigemptyset(&block_signals);
    _ = c.sigemptyset(&unblock_signals);

    const shortopts = "+a:C:iS:u:v0 \t\n\x0b\x0c\r";
    const longopts = [_]c.struct_option{
        .{ .name = "argv0", .has_arg = 1, .flag = null, .val = 'a' },
        .{ .name = "ignore-environment", .has_arg = 0, .flag = null, .val = 'i' },
        .{ .name = "null", .has_arg = 0, .flag = null, .val = '0' },
        .{ .name = "unset", .has_arg = 1, .flag = null, .val = 'u' },
        .{ .name = "chdir", .has_arg = 1, .flag = null, .val = 'C' },
        .{ .name = "default-signal", .has_arg = 2, .flag = null, .val = DEFAULT_SIGNAL_OPTION },
        .{ .name = "ignore-signal", .has_arg = 2, .flag = null, .val = IGNORE_SIGNAL_OPTION },
        .{ .name = "block-signal", .has_arg = 2, .flag = null, .val = BLOCK_SIGNAL_OPTION },
        .{ .name = "list-signal-handling", .has_arg = 0, .flag = null, .val = LIST_SIGNAL_HANDLING_OPTION },
        .{ .name = "debug", .has_arg = 0, .flag = null, .val = 'v' },
        .{ .name = "split-string", .has_arg = 1, .flag = null, .val = 'S' },
        .{ .name = "help", .has_arg = 0, .flag = null, .val = 'h' },
        .{ .name = "version", .has_arg = 0, .flag = null, .val = 'V' },
        .{ .name = null, .has_arg = 0, .flag = null, .val = 0 },
    };

    c.optind = 0;
    while (true) {
        const argc: c_int = @intCast(argv_list.items.len - 1);
        const optc = c.getopt_long(
            argc,
            @ptrCast(argv_list.items.ptr),
            shortopts,
            &longopts,
            null,
        );
        if (optc == -1) break;

        switch (optc) {
            'a' => {
                argv0 = std.mem.span(c.optarg);
            },
            'i' => {
                ignore_environment = true;
            },
            '0' => {
                opt_nul_terminate_output = true;
            },
            'u' => {
                const uvar = std.mem.span(c.optarg);
                if (uvar.len == 0 or std.mem.indexOfScalar(u8, uvar, '=') != null) {
                    try stderr.print("env: cannot unset '{s}': Invalid argument\n", .{uvar});
                    return 125;
                }
                try usvars.append(allocator, uvar);
            },
            'C' => {
                newdir = std.mem.span(c.optarg);
            },
            'v' => {
                dev_debug = true;
            },
            'S' => {
                const s_str: [:0]const u8 = std.mem.span(c.optarg);
                var new_items = (try buildArgv(allocator, s_str, dev_debug, stderr)) orelse return 125;
                defer new_items.deinit(allocator);

                if (dev_debug and new_items.items.len > 0) {
                    try stderr.print("split -S:  '{s}'\n", .{s_str});
                    try stderr.print(" into:    '{s}'\n", .{new_items.items[0]});
                    for (new_items.items[1..]) |p| {
                        try stderr.print("     &    '{s}'\n", .{p});
                    }
                    try stderr.flush();
                }

                var next_argv: std.ArrayList(?[*:0]u8) = .empty;
                try next_argv.append(allocator, argv_list.items[0]);
                for (new_items.items) |ni| {
                    try next_argv.append(allocator, @constCast(ni.ptr));
                }
                const extra_start: usize = @intCast(c.optind);
                for (argv_list.items[extra_start .. argv_list.items.len - 1]) |extra| {
                    try next_argv.append(allocator, extra);
                }
                try next_argv.append(allocator, null);
                argv_list.deinit(allocator);
                argv_list = next_argv;
                c.optind = 0;
            },
            ' ', '\t', '\n', 0x0b, 0x0c, '\r' => {
                try stderr.print("env: invalid option -- '{c}'\n", .{@as(u8, @intCast(optc))});
                try stderr.print("env: use -[v]S to pass options in shebang lines\n", .{});
                try stderr.print("Try 'env --help' for more information.\n", .{});
                return 125;
            },
            DEFAULT_SIGNAL_OPTION => {
                const optarg_z: ?[*:0]const u8 = if (c.optarg != null) c.optarg else null;
                const ok = try parseSignalActionParams(optarg_z, true, &signals, &block_signals, &unblock_signals, &sig_mask_changed, stderr);
                if (!ok) return 125;
            },
            IGNORE_SIGNAL_OPTION => {
                const optarg_z: ?[*:0]const u8 = if (c.optarg != null) c.optarg else null;
                const ok = try parseSignalActionParams(optarg_z, false, &signals, &block_signals, &unblock_signals, &sig_mask_changed, stderr);
                if (!ok) return 125;
            },
            BLOCK_SIGNAL_OPTION => {
                const optarg_z: ?[*:0]const u8 = if (c.optarg != null) c.optarg else null;
                const ok = try parseBlockSignalParams(optarg_z, true, &block_signals, &unblock_signals, &sig_mask_changed, stderr);
                if (!ok) return 125;
            },
            LIST_SIGNAL_HANDLING_OPTION => {
                list_signals = true;
            },
            'h' => {
                printHelp(stdout) catch return 125;
                stdout.flush() catch return 125;
                return 0;
            },
            'V' => {
                printVersion(stdout) catch return 125;
                stdout.flush() catch return 125;
                return 0;
            },
            '?' => {
                try stderr.print("Try 'env --help' for more information.\n", .{});
                return 125;
            },
            else => {
                try stderr.print("Try 'env --help' for more information.\n", .{});
                return 125;
            },
        }
    }

    const total_argc = argv_list.items.len - 1;
    var cur_idx: usize = @intCast(c.optind);

    if (cur_idx < total_argc and std.mem.eql(u8, std.mem.span(argv_list.items[cur_idx].?), "-")) {
        ignore_environment = true;
        cur_idx += 1;
    }

    if (ignore_environment) {
        if (dev_debug) {
            try stderr.print("cleaning environ\n", .{});
        }
        _ = c.clearenv();
    } else {
        for (usvars.items) |uvar| {
            if (dev_debug) {
                try stderr.print("unset:    {s}\n", .{uvar});
            }
            const uvar_z = try allocator.dupeZ(u8, uvar);
            defer allocator.free(uvar_z);
            if (c.unsetenv(uvar_z.ptr) != 0) {
                const err = c.__errno_location().*;
                try stderr.print("env: cannot unset '{s}': {s}\n", .{ uvar, std.mem.span(c.strerror(err)) });
                return 125;
            }
        }
    }

    while (cur_idx < total_argc) {
        const s_arg = std.mem.span(argv_list.items[cur_idx].?);
        if (std.mem.indexOfScalar(u8, s_arg, '=') == null) break;
        if (dev_debug) {
            try stderr.print("setenv:   {s}\n", .{s_arg});
        }
        if (c.putenv(argv_list.items[cur_idx].?) != 0) {
            const err = c.__errno_location().*;
            const eq_pos = std.mem.indexOfScalar(u8, s_arg, '=').?;
            try stderr.print("env: cannot set '{s}': {s}\n", .{ s_arg[0..eq_pos], std.mem.span(c.strerror(err)) });
            return 125;
        }
        cur_idx += 1;
    }

    const program_specified = cur_idx < total_argc;

    if (opt_nul_terminate_output and program_specified) {
        try stderr.print("env: cannot specify --null (-0) with command\nTry 'env --help' for more information.\n", .{});
        return 125;
    }

    if (newdir != null and !program_specified) {
        try stderr.print("env: must specify command with --chdir (-C)\nTry 'env --help' for more information.\n", .{});
        return 125;
    }

    if (argv0 != null and !program_specified) {
        try stderr.print("env: must specify command with --argv0 (-a)\nTry 'env --help' for more information.\n", .{});
        return 125;
    }

    if (newdir) |dir| {
        const dir_z = try allocator.dupeZ(u8, dir);
        defer allocator.free(dir_z);
        if (c.chdir(dir_z.ptr) != 0) {
            const err = c.__errno_location().*;
            try stderr.print("env: cannot change directory to '{s}': {s}\n", .{ dir, std.mem.span(c.strerror(err)) });
            return 125;
        }
    }

    const sig_reset_status = try resetSignalHandlers(&signals, dev_debug, stderr);
    if (sig_reset_status != 0) return sig_reset_status;

    if (sig_mask_changed) {
        const sig_mask_status = try setSignalProcMask(&block_signals, &unblock_signals, dev_debug, stderr);
        if (sig_mask_status != 0) return sig_mask_status;
    }

    if (list_signals) {
        try listSignalHandling(stderr);
    }

    if (!program_specified) {
        const terminator: u8 = if (opt_nul_terminate_output) 0 else '\n';
        if (c.environ != null) {
            var ei: usize = 0;
            while (c.environ[ei] != null) : (ei += 1) {
                const entry = std.mem.span(c.environ[ei]);
                try stdout.writeAll(entry);
                try stdout.writeByte(terminator);
            }
        }
        stdout.flush() catch return 125;
        return 0;
    }

    const cmd = std.mem.span(argv_list.items[cur_idx].?);
    const effective_argv0 = argv0 orelse cmd;

    if (dev_debug) {
        if (argv0 != null) {
            try stderr.print("argv0:     '{s}'\n", .{argv0.?});
        }
        try stderr.print("executing: {s}\n", .{cmd});
        try stderr.print("   arg[0]= '{s}'\n", .{effective_argv0});
        for (argv_list.items[cur_idx + 1 .. total_argc], 1..) |ca, idx| {
            try stderr.print("   arg[{d}]= '{s}'\n", .{ idx, std.mem.span(ca.?) });
        }
        try stderr.flush();
    }

    var c_exec_argv = try allocator.alloc(?[*:0]u8, total_argc - cur_idx + 1);
    defer allocator.free(c_exec_argv);

    const a0_z = try allocator.dupeZ(u8, effective_argv0);
    defer allocator.free(a0_z);
    c_exec_argv[0] = a0_z.ptr;

    for (argv_list.items[cur_idx + 1 .. total_argc], 1..) |ca, idx| {
        c_exec_argv[idx] = ca;
    }
    c_exec_argv[total_argc - cur_idx] = null;

    _ = c.execvp(argv_list.items[cur_idx].?, @ptrCast(c_exec_argv.ptr));

    const err = c.__errno_location().*;
    const msg = std.mem.span(c.strerror(err));
    try stderr.print("env: '{s}': {s}\n", .{ cmd, msg });
    if (err == c.ENOENT and (std.mem.indexOfScalar(u8, cmd, ' ') != null or std.mem.indexOfScalar(u8, cmd, '\t') != null)) {
        try stderr.print("env: use -[v]S to pass options in shebang lines\n", .{});
    }
    try stderr.flush();
    if (err == c.ENOENT) return 127;
    return 126;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: env [OPTION]... [-] [NAME=VALUE]... [COMMAND [ARG]...]
        \\Set each NAME to VALUE in the environment and run COMMAND.
        \\
        \\Mandatory arguments to long options are mandatory for short options too.
        \\  -a, --argv0=ARG
        \\         pass ARG as the zeroth argument of COMMAND
        \\  -i, --ignore-environment
        \\         start with an empty environment
        \\  -0, --null
        \\         end each output line with NUL, not newline
        \\  -u, --unset=NAME
        \\         remove variable from the environment
        \\  -C, --chdir=DIR
        \\         change working directory to DIR
        \\  -S, --split-string=S
        \\         process and split S into separate arguments;
        \\         used to pass multiple arguments on shebang lines
        \\      --block-signal[=SIG]
        \\         block delivery of SIG signal(s) to COMMAND
        \\      --default-signal[=SIG]
        \\         reset handling of SIG signal(s) to the default
        \\      --ignore-signal[=SIG]
        \\         set handling of SIG signal(s) to do nothing
        \\      --list-signal-handling
        \\         list non default signal handling to standard error
        \\  -v, --debug
        \\         print verbose information for each processing step
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
        \\A mere - implies -i.  If no COMMAND, print the resulting environment.
        \\
        \\SIG may be a signal name like 'PIPE', or a signal number like '13'.
        \\Without SIG, all known signals are included.  Multiple signals can be
        \\comma-separated.  An empty SIG argument is a no-op.
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
