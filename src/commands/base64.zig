const std = @import("std");
const common = @import("basenc/common.zig");
const base64_mod = @import("basenc/base64.zig");
const WrapWriter = common.WrapWriter;
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "base64";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    _ = allocator;
    _ = c.signal(c.SIGPIPE, c.SIG_DFL);
    var stdout_buf: [16384]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var opts: common.Options = .{};
    if (try parseCliArgs(args, stdout, &opts)) |exit_code| return exit_code;
    return execute(opts, stdout);
}

fn parseCliArgs(args: [][]const u8, stdout: *std.Io.Writer, opts: *common.Options) !?u8 {
    var operand_seen = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            while (i < args.len) : (i += 1) {
                if (operand_seen) {
                    common.emitExtraOperand(name, args[i]);
                    return 1;
                }
                opts.file_path = args[i];
                operand_seen = true;
            }
            break;
        }
        if (std.mem.startsWith(u8, arg, "--")) {
            if (try handleLong(arg, &i, args, stdout, opts)) |rc| return rc;
        } else if (arg.len > 1 and arg[0] == '-') {
            if (handleShort(arg, &i, args, opts)) |rc| return rc;
        } else {
            if (operand_seen) {
                common.emitExtraOperand(name, arg);
                return 1;
            }
            opts.file_path = arg;
            operand_seen = true;
        }
    }
    return null;
}

fn handleLong(
    arg: []const u8,
    i: *usize,
    args: [][]const u8,
    stdout: *std.Io.Writer,
    opts: *common.Options,
) !?u8 {
    if (std.mem.eql(u8, arg, "--help")) {
        try printHelp(stdout);
        stdout.flush() catch return 1;
        return 0;
    } else if (std.mem.eql(u8, arg, "--version")) {
        try printVersion(stdout);
        stdout.flush() catch return 1;
        return 0;
    } else if (std.mem.eql(u8, arg, "--decode")) {
        opts.decode = true;
    } else if (std.mem.eql(u8, arg, "--ignore-garbage")) {
        opts.ignore_garbage = true;
    } else if (std.mem.startsWith(u8, arg, "--wrap=")) {
        opts.wrap_column = common.parseWrapArg(name, arg[7..]) catch return 1;
    } else if (std.mem.eql(u8, arg, "--wrap")) {
        i.* += 1;
        if (i.* >= args.len) {
            common.emitOptionRequiresArgLong(name, "--wrap");
            return 1;
        }
        opts.wrap_column = common.parseWrapArg(name, args[i.*]) catch return 1;
    } else {
        emitUnknownOption(arg);
        return 1;
    }
    return null;
}

fn handleShort(arg: []const u8, i: *usize, args: [][]const u8, opts: *common.Options) ?u8 {
    var j: usize = 1;
    while (j < arg.len) : (j += 1) {
        switch (arg[j]) {
            'd' => opts.decode = true,
            'i' => opts.ignore_garbage = true,
            'w' => {
                const val = if (j + 1 < arg.len) arg[j + 1 ..] else blk: {
                    i.* += 1;
                    if (i.* >= args.len) {
                        emitOptionRequiresArg('w');
                        return 1;
                    }
                    break :blk args[i.*];
                };
                opts.wrap_column = common.parseWrapArg(name, val) catch return 1;
                break;
            },
            else => {
                emitInvalidOption(arg[j]);
                return 1;
            },
        }
    }
    return null;
}

fn execute(opts: common.Options, stdout: *std.Io.Writer) !u8 {
    const file = common.openInputFile(name, opts.file_path) catch return 1;
    defer if (opts.file_path != null and !std.mem.eql(u8, opts.file_path.?, "-")) {
        file.close(std.Options.debug_io);
    };

    if (opts.decode) {
        base64_mod.decodeStream(file, stdout, false, opts.ignore_garbage) catch |err| {
            if (err == error.InvalidInput) {
                common.emitInvalidInput(name);
                return 1;
            }
            return err;
        };
    } else {
        var wrap = WrapWriter.init(stdout, opts.wrap_column);
        try base64_mod.encodeStream(file, &wrap, false);
    }
    try stdout.flush();
    return 0;
}

fn printHelp(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\Usage: base64 [OPTION]... [FILE]
        \\Base64 encode or decode FILE, or standard input, to standard output.
        \\
        \\With no FILE, or when FILE is -, read standard input.
        \\
        \\Mandatory arguments to long options are mandatory for short options too.
        \\  -d, --decode          decode data
        \\  -i, --ignore-garbage  when decoding, ignore non-alphabet characters
        \\  -w, --wrap=COLS       wrap encoded lines after COLS character (default 76).
        \\                          Use 0 to disable line wrapping
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
        \\The data are encoded as described for the base64 alphabet in RFC 4648.
        \\When decoding, the input may contain newlines in addition to the bytes of
        \\the formal base64 alphabet.  Use --ignore-garbage to attempt to recover
        \\from any other non-alphabet bytes in the encoded stream.
        \\
    );
}

fn printVersion(writer: *std.Io.Writer) !void {
    try writer.writeAll("base64 (coreutilz) 0.1.0\n");
}

fn emitUnknownOption(opt: []const u8) void {
    var stderr_buf: [256]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stderr = &writer.interface;
    stderr.print("{s}: unrecognized option '{s}'\n", .{ name, opt }) catch {};
    writer.interface.flush() catch {};
    common.emitTryHelp(name);
}

fn emitInvalidOption(opt: u8) void {
    var stderr_buf: [256]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stderr = &writer.interface;
    stderr.print("{s}: invalid option -- '{c}'\n", .{ name, opt }) catch {};
    writer.interface.flush() catch {};
    common.emitTryHelp(name);
}

fn emitOptionRequiresArg(opt: u8) void {
    var stderr_buf: [256]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stderr = &writer.interface;
    stderr.print("{s}: option requires an argument -- '{c}'\n", .{ name, opt }) catch {};
    writer.interface.flush() catch {};
    common.emitTryHelp(name);
}
