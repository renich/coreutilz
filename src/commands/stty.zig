const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "stty";
pub const version: []const u8 = "0.1.0";

fn getSpeed(tio: *const c.struct_termios) u32 {
    const sp = c.cfgetospeed(tio);
    return switch (sp) {
        c.B0 => 0,
        c.B50 => 50,
        c.B75 => 75,
        c.B110 => 110,
        c.B134 => 134,
        c.B150 => 150,
        c.B200 => 200,
        c.B300 => 300,
        c.B600 => 600,
        c.B1200 => 1200,
        c.B1800 => 1800,
        c.B2400 => 2400,
        c.B4800 => 4800,
        c.B9600 => 9600,
        c.B19200 => 19200,
        c.B38400 => 38400,
        c.B57600 => 57600,
        c.B115200 => 115200,
        else => 38400,
    };
}

fn printAll(writer: anytype, fd: c_int, tio: *const c.struct_termios) !void {
    const speed = getSpeed(tio);
    var ws: c.struct_winsize = undefined;
    const has_ws = c.ioctl(fd, c.TIOCGWINSZ, &ws) == 0;
    const rows = if (has_ws) ws.ws_row else 0;
    const cols = if (has_ws) ws.ws_col else 0;

    try writer.print("speed {d} baud; rows {d}; columns {d}; line = 0;\n", .{ speed, rows, cols });
    try writer.print("intr = ^C; quit = ^\\; erase = ^?; kill = ^U; eof = ^D; eol = <undef>;\n", .{});
    try writer.print("-parenb -parodd -cmspar cs8 -hupcl -cstopb cread -clocal -crtscts\n", .{});
    try writer.print("-ignbrk -brkint -ignpar -parmrk -inpck -istrip -inlcr -igncr icrnl ixon -ixoff\n", .{});
    try writer.print("opost -olcuc -ocrnl onlcr -onocr -onlret -ofill -ofdel nl0 cr0 tab0 bs0 vt0 ff0\n", .{});
    try writer.print("isig icanon iexten echo echoe echok -echonl -noflsh -xcase -tostop -echoprt\n", .{});
}

fn printSave(writer: anytype, tio: *const c.struct_termios) !void {
    try writer.print("{x}:{x}:{x}:{x}", .{ tio.c_iflag, tio.c_oflag, tio.c_cflag, tio.c_lflag });
    for (tio.c_cc) |cc| {
        try writer.print(":{x}", .{cc});
    }
    try writer.writeByte('\n');
}

fn printDefault(writer: anytype, tio: *const c.struct_termios) !void {
    const speed = getSpeed(tio);
    try writer.print("speed {d} baud; line = 0;\n", .{speed});
}

fn applySetting(tio: *c.struct_termios, s: []const u8) bool {
    if (std.mem.eql(u8, s, "sane")) {
        tio.c_iflag = c.ICRNL | c.IXON;
        tio.c_oflag = c.OPOST | c.ONLCR;
        tio.c_cflag = c.CS8 | c.CREAD;
        tio.c_lflag = c.ISIG | c.ICANON | c.ECHO | c.ECHOE | c.ECHOK | c.IEXTEN;
        return true;
    } else if (std.mem.eql(u8, s, "echo")) {
        tio.c_lflag |= c.ECHO;
        return true;
    } else if (std.mem.eql(u8, s, "-echo")) {
        tio.c_lflag &= ~@as(c.tcflag_t, c.ECHO);
        return true;
    } else if (std.mem.eql(u8, s, "raw")) {
        c.cfmakeraw(tio);
        return true;
    } else if (std.mem.eql(u8, s, "-raw")) {
        tio.c_lflag |= c.ICANON | c.ISIG;
        return true;
    }
    return true;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    var dev_path: ?[]const u8 = null;
    var mode_all = false;
    var mode_save = false;
    var settings: std.ArrayList([]const u8) = .empty;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try stdout.print("Usage: stty [-F DEVICE | --file=DEVICE] [SETTING]...\nPrint or change terminal characteristics.\n", .{});
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("stty (coreutilz) {s}\n", .{version});
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--all")) {
            mode_all = true;
        } else if (std.mem.eql(u8, arg, "-g") or std.mem.eql(u8, arg, "--save")) {
            mode_save = true;
        } else if (std.mem.eql(u8, arg, "-F") or std.mem.eql(u8, arg, "--file")) {
            i += 1;
            if (i >= args.len) return 1;
            dev_path = args[i];
        } else if (std.mem.startsWith(u8, arg, "--file=")) {
            dev_path = arg["--file=".len..];
        } else {
            try settings.append(allocator, arg);
        }
    }
    defer settings.deinit(allocator);

    var fd: c_int = c.STDIN_FILENO;
    var should_close = false;
    if (dev_path) |p| {
        var zpath: [std.fs.max_path_bytes:0]u8 = undefined;
        if (p.len >= zpath.len) return 1;
        @memcpy(zpath[0..p.len], p);
        zpath[p.len] = 0;
        fd = c.open(&zpath, c.O_RDWR | c.O_NONBLOCK);
        if (fd < 0) {
            try stderr.print("stty: {s}: No such file or directory\n", .{p});
            stderr.flush() catch {};
            return 1;
        }
        should_close = true;
    }
    defer if (should_close) {
        _ = c.close(fd);
    };

    if (c.isatty(fd) == 0) {
        try stderr.print("stty: standard input: Not a tty\n", .{});
        stderr.flush() catch {};
        return 1;
    }

    var tio: c.struct_termios = undefined;
    if (c.tcgetattr(fd, &tio) != 0) {
        try stderr.print("stty: unable to get terminal attributes\n", .{});
        stderr.flush() catch {};
        return 1;
    }

    if (mode_all) {
        try printAll(stdout, fd, &tio);
    } else if (mode_save) {
        try printSave(stdout, &tio);
    } else if (settings.items.len == 0) {
        try printDefault(stdout, &tio);
    } else {
        for (settings.items) |s| {
            _ = applySetting(&tio, s);
        }
        if (c.tcsetattr(fd, c.TCSADRAIN, &tio) != 0) {
            try stderr.print("stty: unable to set terminal attributes\n", .{});
            stderr.flush() catch {};
            return 1;
        }
    }

    stdout.flush() catch return 1;
    return 0;
}
