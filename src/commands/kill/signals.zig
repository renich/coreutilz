const std = @import("std");

pub const SignalEntry = struct {
    num: u8,
    name: []const u8,
    desc: []const u8,
};

pub const SIGNALS = [_]SignalEntry{
    .{ .num = 0, .name = "0", .desc = "Unknown signal 0" },
    .{ .num = 1, .name = "HUP", .desc = "Hangup" },
    .{ .num = 2, .name = "INT", .desc = "Interrupt" },
    .{ .num = 3, .name = "QUIT", .desc = "Quit" },
    .{ .num = 4, .name = "ILL", .desc = "Illegal instruction" },
    .{ .num = 5, .name = "TRAP", .desc = "Trace/breakpoint trap" },
    .{ .num = 6, .name = "ABRT", .desc = "Aborted" },
    .{ .num = 7, .name = "BUS", .desc = "Bus error" },
    .{ .num = 8, .name = "FPE", .desc = "Floating point exception" },
    .{ .num = 9, .name = "KILL", .desc = "Killed" },
    .{ .num = 10, .name = "USR1", .desc = "User defined signal 1" },
    .{ .num = 11, .name = "SEGV", .desc = "Segmentation fault" },
    .{ .num = 12, .name = "USR2", .desc = "User defined signal 2" },
    .{ .num = 13, .name = "PIPE", .desc = "Broken pipe" },
    .{ .num = 14, .name = "ALRM", .desc = "Alarm clock" },
    .{ .num = 15, .name = "TERM", .desc = "Terminated" },
    .{ .num = 16, .name = "STKFLT", .desc = "Stack fault" },
    .{ .num = 17, .name = "CHLD", .desc = "Child exited" },
    .{ .num = 18, .name = "CONT", .desc = "Continued" },
    .{ .num = 19, .name = "STOP", .desc = "Stopped (signal)" },
    .{ .num = 20, .name = "TSTP", .desc = "Stopped" },
    .{ .num = 21, .name = "TTIN", .desc = "Stopped (tty input)" },
    .{ .num = 22, .name = "TTOU", .desc = "Stopped (tty output)" },
    .{ .num = 23, .name = "URG", .desc = "Urgent I/O condition" },
    .{ .num = 24, .name = "XCPU", .desc = "CPU time limit exceeded" },
    .{ .num = 25, .name = "XFSZ", .desc = "File size limit exceeded" },
    .{ .num = 26, .name = "VTALRM", .desc = "Virtual timer expired" },
    .{ .num = 27, .name = "PROF", .desc = "Profiling timer expired" },
    .{ .num = 28, .name = "WINCH", .desc = "Window changed" },
    .{ .num = 29, .name = "POLL", .desc = "I/O possible" },
    .{ .num = 30, .name = "PWR", .desc = "Power failure" },
    .{ .num = 31, .name = "SYS", .desc = "Bad system call" },
    .{ .num = 34, .name = "RTMIN", .desc = "Real-time signal 0" },
    .{ .num = 35, .name = "RTMIN+1", .desc = "Real-time signal 1" },
    .{ .num = 36, .name = "RTMIN+2", .desc = "Real-time signal 2" },
    .{ .num = 37, .name = "RTMIN+3", .desc = "Real-time signal 3" },
    .{ .num = 38, .name = "RTMIN+4", .desc = "Real-time signal 4" },
    .{ .num = 39, .name = "RTMIN+5", .desc = "Real-time signal 5" },
    .{ .num = 40, .name = "RTMIN+6", .desc = "Real-time signal 6" },
    .{ .num = 41, .name = "RTMIN+7", .desc = "Real-time signal 7" },
    .{ .num = 42, .name = "RTMIN+8", .desc = "Real-time signal 8" },
    .{ .num = 43, .name = "RTMIN+9", .desc = "Real-time signal 9" },
    .{ .num = 44, .name = "RTMIN+10", .desc = "Real-time signal 10" },
    .{ .num = 45, .name = "RTMIN+11", .desc = "Real-time signal 11" },
    .{ .num = 46, .name = "RTMIN+12", .desc = "Real-time signal 12" },
    .{ .num = 47, .name = "RTMIN+13", .desc = "Real-time signal 13" },
    .{ .num = 48, .name = "RTMIN+14", .desc = "Real-time signal 14" },
    .{ .num = 49, .name = "RTMIN+15", .desc = "Real-time signal 15" },
    .{ .num = 50, .name = "RTMAX-14", .desc = "Real-time signal 16" },
    .{ .num = 51, .name = "RTMAX-13", .desc = "Real-time signal 17" },
    .{ .num = 52, .name = "RTMAX-12", .desc = "Real-time signal 18" },
    .{ .num = 53, .name = "RTMAX-11", .desc = "Real-time signal 19" },
    .{ .num = 54, .name = "RTMAX-10", .desc = "Real-time signal 20" },
    .{ .num = 55, .name = "RTMAX-9", .desc = "Real-time signal 21" },
    .{ .num = 56, .name = "RTMAX-8", .desc = "Real-time signal 22" },
    .{ .num = 57, .name = "RTMAX-7", .desc = "Real-time signal 23" },
    .{ .num = 58, .name = "RTMAX-6", .desc = "Real-time signal 24" },
    .{ .num = 59, .name = "RTMAX-5", .desc = "Real-time signal 25" },
    .{ .num = 60, .name = "RTMAX-4", .desc = "Real-time signal 26" },
    .{ .num = 61, .name = "RTMAX-3", .desc = "Real-time signal 27" },
    .{ .num = 62, .name = "RTMAX-2", .desc = "Real-time signal 28" },
    .{ .num = 63, .name = "RTMAX-1", .desc = "Real-time signal 29" },
    .{ .num = 64, .name = "RTMAX", .desc = "Real-time signal 30" },
};

pub fn signumToName(num: u8) ?[]const u8 {
    for (SIGNALS) |s| {
        if (s.num == num) return s.name;
    }
    return null;
}

pub fn nameToSignum(name: []const u8) ?u8 {
    var clean = name;
    if (std.ascii.startsWithIgnoreCase(clean, "SIG")) {
        clean = clean[3..];
    }
    if (std.ascii.eqlIgnoreCase(clean, "IOT")) return 6;
    if (std.ascii.eqlIgnoreCase(clean, "CLD")) return 17;
    if (std.ascii.eqlIgnoreCase(clean, "IO")) return 29;

    for (SIGNALS) |s| {
        if (std.ascii.eqlIgnoreCase(clean, s.name)) return s.num;
    }
    return null;
}

pub fn parseOperandToSig(operand: []const u8) ?u8 {
    if (operand.len == 0) return null;
    var all_digits = true;
    for (operand) |ch| {
        if (!std.ascii.isDigit(ch)) {
            all_digits = false;
            break;
        }
    }
    if (all_digits) {
        var val = std.fmt.parseInt(u32, operand, 10) catch return null;
        if (val > 128) {
            val = if (val >= 0xFF) (val & 0xFF) else (val & 0x7F);
        }
        if (val <= 64) return @intCast(val);
        return null;
    }
    return nameToSignum(operand);
}

pub fn listAllSignals(stdout: anytype) !void {
    for (SIGNALS) |s| {
        try stdout.print("{s}\n", .{s.name});
    }
}

pub fn printTableRow(num: u8, stdout: anytype) !void {
    for (SIGNALS) |s| {
        if (s.num == num) {
            try stdout.print("{d:>2} {s:<8} {s}\n", .{ s.num, s.name, s.desc });
            return;
        }
    }
    try stdout.print("{d:>2} SIG{d:<5} Unknown signal {d}\n", .{ num, num, num });
}

pub fn printAllTable(stdout: anytype) !void {
    for (SIGNALS) |s| {
        try stdout.print("{d:>2} {s:<8} {s}\n", .{ s.num, s.name, s.desc });
    }
}
