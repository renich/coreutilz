const std = @import("std");

// Command modules
pub const true_cmd = @import("commands/true.zig");
pub const false_cmd = @import("commands/false.zig");
pub const echo_cmd = @import("commands/echo.zig");
pub const cat_cmd = @import("commands/cat.zig");
pub const hostname_cmd = @import("commands/hostname.zig");
pub const logname_cmd = @import("commands/logname.zig");
pub const tty_cmd = @import("commands/tty.zig");
pub const whoami_cmd = @import("commands/whoami.zig");
pub const nproc_cmd = @import("commands/nproc.zig");
pub const hostid_cmd = @import("commands/hostid.zig");
pub const unlink_cmd = @import("commands/unlink.zig");
pub const dirname_cmd = @import("commands/dirname.zig");
pub const basename_cmd = @import("commands/basename.zig");
pub const printenv_cmd = @import("commands/printenv.zig");
pub const pwd_cmd = @import("commands/pwd.zig");
pub const readlink_cmd = @import("commands/readlink.zig");
pub const mkdir_cmd = @import("commands/mkdir.zig");
pub const rmdir_cmd = @import("commands/rmdir.zig");
pub const rm_cmd = @import("commands/rm.zig");
pub const link_cmd = @import("commands/link.zig");
pub const yes_cmd = @import("commands/yes.zig");
pub const sleep_cmd = @import("commands/sleep.zig");
pub const sync_cmd = @import("commands/sync.zig");
pub const env_cmd = @import("commands/env.zig");
pub const cp_cmd = @import("commands/cp.zig");
pub const mv_cmd = @import("commands/mv.zig");
// pub const ls_cmd = @import("commands/ls.zig");
pub const chmod_cmd = @import("commands/chmod.zig");
pub const ln_cmd = @import("commands/ln.zig");
// pub const chown_cmd = @import("commands/chown.zig");
// pub const chgrp_cmd = @import("commands/chgrp.zig");
pub const stat_cmd = @import("commands/stat.zig");
pub const dd_cmd = @import("commands/dd.zig");

// Utility modules
pub const utils = struct {
    pub const args = @import("utils/args.zig");
    pub const errors = @import("utils/errors.zig");
    pub const fs = @import("utils/fs.zig");
    pub const io = @import("utils/io.zig");
};

/// Simple buffered print for testing
pub fn bufferedPrint() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("Hello from coreutilz!\n");
}
