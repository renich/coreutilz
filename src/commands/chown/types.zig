const std = @import("std");

pub const Verbosity = enum {
    off,
    changes_only,
    high,
};

pub const SymlinkMode = enum {
    no_dereference,
    dereference,
};

pub const TraverseMode = enum {
    physical, // -P (default)
    command_line, // -H
    logical, // -L
};

pub const DevIno = struct {
    dev: u64,
    ino: u64,
};

pub const ChownConfig = struct {
    cmd_name: []const u8 = "chown",
    is_chgrp: bool = false,
    uid: ?u32 = null,
    gid: ?u32 = null,
    target_user_str: ?[]const u8 = null,
    target_group_str: ?[]const u8 = null,
    req_uid: ?u32 = null,
    req_gid: ?u32 = null,
    verbosity: Verbosity = .off,
    recurse: bool = false,
    preserve_root: bool = false,
    symlink_mode: SymlinkMode = .dereference,
    traverse_mode: TraverseMode = .physical,
    silent: bool = false,
    affect_symlink_referent: bool = true,
    root_dev: ?u64 = null,
    root_ino: ?u64 = null,
};
