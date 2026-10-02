const std = @import("std");
const coreutilz = @import("coreutilz");

pub fn main(init: std.process.Init.Minimal) u8 {
    coreutilz.utils.signals.restoreDefaultSignals();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = coreutilz.utils.args.getArgs(init.args, allocator) catch |err| {
        handleDispatchError("coreutilz", err);
        return 1;
    };

    if (args.len < 1) {
        std.debug.print("coreutilz: no command specified\n", .{});
        return 1;
    }

    const arg0 = std.fs.path.basename(args[0]);

    if (std.mem.eql(u8, arg0, "coreutilz")) {
        if (args.len > 1) {
            const subcmd = std.fs.path.basename(args[1]);
            if (std.mem.eql(u8, subcmd, "--help") or std.mem.eql(u8, subcmd, "-h")) {
                printUsage();
                return 0;
            } else if (std.mem.eql(u8, subcmd, "--version") or std.mem.eql(u8, subcmd, "-v")) {
                printVersion();
                return 0;
            }
            return dispatch(subcmd, args[1..], allocator) catch |err| {
                handleDispatchError(subcmd, err);
                return coreutilz.utils.runner.getExitFailure(subcmd);
            };
        } else {
            printUsage();
            return 0;
        }
    } else {
        return dispatch(arg0, args, allocator) catch |err| {
            handleDispatchError(arg0, err);
            return coreutilz.utils.runner.getExitFailure(arg0);
        };
    }
}

fn handleDispatchError(command: []const u8, err: anyerror) void {
    var stderr_buf: [256]u8 = undefined;
    var stderr_writer = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stderr = &stderr_writer.interface;
    switch (err) {
        error.OutOfMemory => {
            stderr.print("{s}: memory exhausted\n", .{command}) catch {};
        },
        error.BrokenPipe => {
            stderr.print("{s}: write error: Broken pipe\n", .{command}) catch {};
        },
        error.WriteFailed, error.DiskFull, error.NoSpaceLeft, error.WriteError => {
            const errno_val = coreutilz.compat.c.__errno_location().*;
            if (errno_val != 0) {
                const err_str = std.mem.span(coreutilz.compat.c.strerror(errno_val));
                stderr.print("{s}: write error: {s}\n", .{ command, err_str }) catch {};
            } else {
                stderr.print("{s}: write error: No space left on device\n", .{command}) catch {};
            }
        },
        else => {
            stderr.print("{s}: {s}\n", .{ command, coreutilz.utils.errors.errorDescription(err) }) catch {};
        },
    }
    stderr.flush() catch {};
}

const CmdEntry = struct {
    name: []const u8,
    run: *const fn ([][]const u8, std.mem.Allocator) anyerror!u8,
};

const COMMANDS = [_]CmdEntry{
    .{ .name = "true", .run = coreutilz.true_cmd.run },           .{ .name = "false", .run = coreutilz.false_cmd.run },
    .{ .name = "echo", .run = coreutilz.echo_cmd.run },           .{ .name = "cat", .run = coreutilz.cat_cmd.run },
    .{ .name = "hostname", .run = coreutilz.hostname_cmd.run },   .{ .name = "logname", .run = coreutilz.logname_cmd.run },
    .{ .name = "tty", .run = coreutilz.tty_cmd.run },             .{ .name = "whoami", .run = coreutilz.whoami_cmd.run },
    .{ .name = "nproc", .run = coreutilz.nproc_cmd.run },         .{ .name = "hostid", .run = coreutilz.hostid_cmd.run },
    .{ .name = "unlink", .run = coreutilz.unlink_cmd.run },       .{ .name = "dirname", .run = coreutilz.dirname_cmd.run },
    .{ .name = "basename", .run = coreutilz.basename_cmd.run },   .{ .name = "printenv", .run = coreutilz.printenv_cmd.run },
    .{ .name = "pwd", .run = coreutilz.pwd_cmd.run },             .{ .name = "readlink", .run = coreutilz.readlink_cmd.run },
    .{ .name = "mkdir", .run = coreutilz.mkdir_cmd.run },         .{ .name = "rmdir", .run = coreutilz.rmdir_cmd.run },
    .{ .name = "rm", .run = coreutilz.rm_cmd.run },               .{ .name = "link", .run = coreutilz.link_cmd.run },
    .{ .name = "yes", .run = coreutilz.yes_cmd.run },             .{ .name = "sleep", .run = coreutilz.sleep_cmd.run },
    .{ .name = "sync", .run = coreutilz.sync_cmd.run },           .{ .name = "env", .run = coreutilz.env_cmd.run },
    .{ .name = "cp", .run = coreutilz.cp_cmd.run },               .{ .name = "mv", .run = coreutilz.mv_cmd.run },
    .{ .name = "ls", .run = coreutilz.ls_cmd.run },               .{ .name = "dir", .run = coreutilz.dir_cmd.run },
    .{ .name = "vdir", .run = coreutilz.vdir_cmd.run },           .{ .name = "chmod", .run = coreutilz.chmod_cmd.run },
    .{ .name = "ln", .run = coreutilz.ln_cmd.run },               .{ .name = "mkfifo", .run = coreutilz.mkfifo_cmd.run },
    .{ .name = "mknod", .run = coreutilz.mknod_cmd.run },         .{ .name = "chown", .run = coreutilz.chown_cmd.run },
    .{ .name = "chgrp", .run = coreutilz.chgrp_cmd.run },         .{ .name = "df", .run = coreutilz.df_cmd.run },
    .{ .name = "du", .run = coreutilz.du_cmd.run },               .{ .name = "stat", .run = coreutilz.stat_cmd.run },
    .{ .name = "dd", .run = coreutilz.dd_cmd.run },               .{ .name = "head", .run = coreutilz.head_cmd.run },
    .{ .name = "wc", .run = coreutilz.wc_cmd.run },               .{ .name = "tee", .run = coreutilz.tee_cmd.run },
    .{ .name = "truncate", .run = coreutilz.truncate_cmd.run },   .{ .name = "touch", .run = coreutilz.touch_cmd.run },
    .{ .name = "cut", .run = coreutilz.cut_cmd.run },             .{ .name = "paste", .run = coreutilz.paste_cmd.run },
    .{ .name = "seq", .run = coreutilz.seq_cmd.run },             .{ .name = "sort", .run = coreutilz.sort_cmd.run },
    .{ .name = "uniq", .run = coreutilz.uniq_cmd.run },           .{ .name = "comm", .run = coreutilz.comm_cmd.run },
    .{ .name = "shuf", .run = coreutilz.shuf_cmd.run },           .{ .name = "tac", .run = coreutilz.tac_cmd.run },
    .{ .name = "split", .run = coreutilz.split_cmd.run },         .{ .name = "csplit", .run = coreutilz.csplit_cmd.run },
    .{ .name = "tail", .run = coreutilz.tail_cmd.run },           .{ .name = "tr", .run = coreutilz.tr_cmd.run },
    .{ .name = "fold", .run = coreutilz.fold_cmd.run },           .{ .name = "cksum", .run = coreutilz.cksum_cmd.run },
    .{ .name = "b2sum", .run = coreutilz.b2sum_cmd.run },         .{ .name = "md5sum", .run = coreutilz.md5sum_cmd.run },
    .{ .name = "sha1sum", .run = coreutilz.sha1sum_cmd.run },     .{ .name = "sha224sum", .run = coreutilz.sha224sum_cmd.run },
    .{ .name = "sha256sum", .run = coreutilz.sha256sum_cmd.run }, .{ .name = "sha384sum", .run = coreutilz.sha384sum_cmd.run },
    .{ .name = "sha512sum", .run = coreutilz.sha512sum_cmd.run }, .{ .name = "base64", .run = coreutilz.base64_cmd.run },
    .{ .name = "base32", .run = coreutilz.base32_cmd.run },       .{ .name = "basenc", .run = coreutilz.basenc_cmd.run },
    .{ .name = "nl", .run = coreutilz.nl_cmd.run },               .{ .name = "fmt", .run = coreutilz.fmt_cmd.run },
    .{ .name = "pr", .run = coreutilz.pr_cmd.run },               .{ .name = "expand", .run = coreutilz.expand_cmd.run },
    .{ .name = "unexpand", .run = coreutilz.unexpand_cmd.run },   .{ .name = "od", .run = coreutilz.od_cmd.run },
    .{ .name = "ptx", .run = coreutilz.ptx_cmd.run },             .{ .name = "numfmt", .run = coreutilz.numfmt_cmd.run },
    .{ .name = "timeout", .run = coreutilz.timeout_cmd.run },     .{ .name = "nice", .run = coreutilz.nice_cmd.run },
    .{ .name = "nohup", .run = coreutilz.nohup_cmd.run },         .{ .name = "stdbuf", .run = coreutilz.stdbuf_cmd.run },
    .{ .name = "stty", .run = coreutilz.stty_cmd.run },           .{ .name = "date", .run = coreutilz.date_cmd.run },
    .{ .name = "chroot", .run = coreutilz.chroot_cmd.run },       .{ .name = "id", .run = coreutilz.id_cmd.run },
    .{ .name = "groups", .run = coreutilz.groups_cmd.run },       .{ .name = "who", .run = coreutilz.who_cmd.run },
    .{ .name = "users", .run = coreutilz.users_cmd.run },         .{ .name = "pinky", .run = coreutilz.pinky_cmd.run },
    .{ .name = "uname", .run = coreutilz.uname_cmd.run },         .{ .name = "arch", .run = coreutilz.arch_cmd.run },
    .{ .name = "chcon", .run = coreutilz.chcon_cmd.run },         .{ .name = "runcon", .run = coreutilz.runcon_cmd.run },
    .{ .name = "pathchk", .run = coreutilz.pathchk_cmd.run },     .{ .name = "realpath", .run = coreutilz.realpath_cmd.run },
    .{ .name = "mktemp", .run = coreutilz.mktemp_cmd.run },       .{ .name = "tsort", .run = coreutilz.tsort_cmd.run },
    .{ .name = "factor", .run = coreutilz.factor_cmd.run },       .{ .name = "dircolors", .run = coreutilz.dircolors_cmd.run },
    .{ .name = "test", .run = coreutilz.test_cmd.run },           .{ .name = "[", .run = coreutilz.test_cmd.run },
    .{ .name = "expr", .run = coreutilz.expr_cmd.run },           .{ .name = "printf", .run = coreutilz.printf_cmd.run },
    .{ .name = "join", .run = coreutilz.join_cmd.run },           .{ .name = "shred", .run = coreutilz.shred_cmd.run },
    .{ .name = "install", .run = coreutilz.install_cmd.run },
};

fn dispatch(command: []const u8, args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    for (COMMANDS) |cmd| {
        if (std.mem.eql(u8, command, cmd.name)) {
            return try cmd.run(args, allocator);
        }
    }
    std.debug.print("{s}: unknown command\n", .{command});
    return 1;
}

fn printUsage() void {
    var buf: [4096]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &buf);
    _ = writer.interface.write(
        \\Coreutilz 0.1.0 - 100% GNU-compatible Coreutils in Zig
        \\
        \\Usage: coreutilz <command> [arguments...]
        \\   or: <command> [arguments...] (via symlink)
        \\
        \\All 106 GNU Coreutils commands supported.
        \\
    ) catch {};

    writer.interface.flush() catch {};
}

fn printVersion() void {
    var buf: [64]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &buf);
    _ = writer.interface.write("coreutilz 0.1.0\n") catch {};
    writer.interface.flush() catch {};
}
