const std = @import("std");
const coreutilz = @import("coreutilz");

pub fn main(init: std.process.Init) !void {
    const args = try coreutilz.utils.args.getArgs(init, init.arena.allocator());

    if (args.len < 1) {
        std.debug.print("Error: no command specified\n", .{});
        std.process.exit(1);
    }

    const arg0 = std.fs.path.basename(args[0]);

    const exit_code = blk: {
        if (std.mem.eql(u8, arg0, "coreutilz")) {
            if (args.len > 1) {
                const subcmd = std.fs.path.basename(args[1]);
                break :blk dispatch(subcmd, args[1..]) catch |err| {
                    std.debug.print("Error: {s}\n", .{@errorName(err)});
                    std.process.exit(1);
                };
            } else {
                std.debug.print("Usage: coreutilz <command> [arguments...]\n", .{});
                std.process.exit(1);
            }
        } else {
            break :blk dispatch(arg0, args) catch |err| {
                std.debug.print("Error: {s}\n", .{@errorName(err)});
                std.process.exit(1);
            };
        }
    };

    std.process.exit(exit_code);
}

fn dispatch(command: []const u8, args: [][]const u8) !u8 {
    const allocator = std.heap.page_allocator;

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
    } else {
        std.debug.print("{s}: unknown command\n", .{command});
        return 1;
    }
}
