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
                return 1;
            };
        } else {
            printUsage();
            return 0;
        }
    } else {
        return dispatch(arg0, args, allocator) catch |err| {
            handleDispatchError(arg0, err);
            return 1;
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

fn dispatch(command: []const u8, args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    if (std.mem.eql(u8, command, "true")) {
        return try coreutilz.true_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "false")) {
        return try coreutilz.false_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "echo")) {
        return try coreutilz.echo_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "cat")) {
        return try coreutilz.cat_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "hostname")) {
        return try coreutilz.hostname_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "logname")) {
        return try coreutilz.logname_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "tty")) {
        return try coreutilz.tty_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "whoami")) {
        return try coreutilz.whoami_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "nproc")) {
        return try coreutilz.nproc_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "hostid")) {
        return try coreutilz.hostid_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "unlink")) {
        return try coreutilz.unlink_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "dirname")) {
        return try coreutilz.dirname_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "basename")) {
        return try coreutilz.basename_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "printenv")) {
        return try coreutilz.printenv_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "pwd")) {
        return try coreutilz.pwd_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "readlink")) {
        return try coreutilz.readlink_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "mkdir")) {
        return try coreutilz.mkdir_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "rmdir")) {
        return try coreutilz.rmdir_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "rm")) {
        return try coreutilz.rm_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "link")) {
        return try coreutilz.link_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "yes")) {
        return try coreutilz.yes_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "sleep")) {
        return try coreutilz.sleep_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "sync")) {
        return try coreutilz.sync_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "env")) {
        return try coreutilz.env_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "cp")) {
        return try coreutilz.cp_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "mv")) {
        return try coreutilz.mv_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "chmod")) {
        return try coreutilz.chmod_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "ln")) {
        return try coreutilz.ln_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "stat")) {
        return try coreutilz.stat_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "dd")) {
        return try coreutilz.dd_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "head")) {
        return try coreutilz.head_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "wc")) {
        return try coreutilz.wc_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "tee")) {
        return try coreutilz.tee_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "truncate")) {
        return try coreutilz.truncate_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "touch")) {
        return try coreutilz.touch_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "cut")) {
        return try coreutilz.cut_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "paste")) {
        return try coreutilz.paste_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "seq")) {
        return try coreutilz.seq_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "ls")) {
        return try coreutilz.ls_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "dir")) {
        return try coreutilz.dir_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "vdir")) {
        return try coreutilz.vdir_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "sort")) {
        return try coreutilz.sort_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "uniq")) {
        return try coreutilz.uniq_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "comm")) {
        return try coreutilz.comm_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "shuf")) {
        return try coreutilz.shuf_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "tac")) {
        return try coreutilz.tac_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "split")) {
        return try coreutilz.split_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "csplit")) {
        return try coreutilz.csplit_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "tail")) {
        return try coreutilz.tail_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "tr")) {
        return try coreutilz.tr_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "fold")) {
        return try coreutilz.fold_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "mkfifo")) {
        return try coreutilz.mkfifo_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "mknod")) {
        return try coreutilz.mknod_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "chown")) {
        return try coreutilz.chown_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "chgrp")) {
        return try coreutilz.chgrp_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "df")) {
        return try coreutilz.df_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "du")) {
        return try coreutilz.du_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "cksum")) {
        return try coreutilz.cksum_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "b2sum")) {
        return try coreutilz.b2sum_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "md5sum")) {
        return try coreutilz.md5sum_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "sha1sum")) {
        return try coreutilz.sha1sum_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "sha224sum")) {
        return try coreutilz.sha224sum_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "sha256sum")) {
        return try coreutilz.sha256sum_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "sha384sum")) {
        return try coreutilz.sha384sum_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "sha512sum")) {
        return try coreutilz.sha512sum_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "base64")) {
        return try coreutilz.base64_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "base32")) {
        return try coreutilz.base32_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "basenc")) {
        return try coreutilz.basenc_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "nl")) {
        return try coreutilz.nl_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "fmt")) {
        return try coreutilz.fmt_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "pr")) {
        return try coreutilz.pr_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "expand")) {
        return try coreutilz.expand_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "unexpand")) {
        return try coreutilz.unexpand_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "od")) {
        return try coreutilz.od_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "ptx")) {
        return try coreutilz.ptx_cmd.run(args, allocator);
    } else if (std.mem.eql(u8, command, "numfmt")) {
        return try coreutilz.numfmt_cmd.run(args, allocator);
    } else {
        std.debug.print("{s}: unknown command\n", .{command});
        return 1;
    }
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
        \\Available commands:
        \\  basename, cat, chmod, comm, cp, csplit, cut, dd, dir, dirname, echo, env,
        \\  false, fold, head, hostid, hostname, link, ln, logname, ls, mkdir, mv,
        \\  nproc, paste, printenv, pwd, readlink, rm, rmdir, seq, shuf, sleep, sort,
        \\  split, stat, sync, tac, tail, tee, touch, tr, true, truncate, tty, uniq,
        \\  unlink, vdir, wc, whoami, yes, mkfifo, mknod, chown, chgrp, df, du,
        \\  cksum, b2sum, md5sum, sha1sum, sha224sum, sha256sum, sha384sum, sha512sum,
        \\  base64, base32, basenc, nl, fmt, pr, expand, unexpand, od, ptx, numfmt
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
