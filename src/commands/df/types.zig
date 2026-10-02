const std = @import("std");

pub const OutputField = enum {
    source,
    fstype,
    itotal,
    iused,
    iavail,
    ipcent,
    size,
    used,
    avail,
    pcent,
    file,
    target,

    pub fn fromString(s: []const u8) ?OutputField {
        if (std.mem.eql(u8, s, "source")) return .source;
        if (std.mem.eql(u8, s, "fstype")) return .fstype;
        if (std.mem.eql(u8, s, "itotal")) return .itotal;
        if (std.mem.eql(u8, s, "iused")) return .iused;
        if (std.mem.eql(u8, s, "iavail")) return .iavail;
        if (std.mem.eql(u8, s, "ipcent")) return .ipcent;
        if (std.mem.eql(u8, s, "size")) return .size;
        if (std.mem.eql(u8, s, "used")) return .used;
        if (std.mem.eql(u8, s, "avail")) return .avail;
        if (std.mem.eql(u8, s, "pcent")) return .pcent;
        if (std.mem.eql(u8, s, "file")) return .file;
        if (std.mem.eql(u8, s, "target")) return .target;
        return null;
    }
};

pub const MountInfo = struct {
    fsname: []const u8,
    dir: []const u8,
    fstype: []const u8,
    dev: u64,
    is_dummy: bool,
    is_remote: bool,
    stat_ok: bool,
    f_frsize: u64,
    f_blocks: u64,
    f_bfree: u64,
    f_bavail: u64,
    f_files: u64,
    f_ffree: u64,
    f_favail: u64,
    file_operand: ?[]const u8 = null,
};

pub const DisplayMode = enum {
    human_1024,
    human_1000,
    block_size,
};

pub const DfConfig = struct {
    all: bool = false,
    display_mode: DisplayMode = .block_size,
    block_size: u64 = 1024,
    block_label: []const u8 = "1K-blocks",
    inodes_mode: bool = false,
    portability: bool = false,
    print_type: bool = false,
    local_only: bool = false,
    grand_total: bool = false,
    do_sync: bool = false,
    custom_output: bool = false,
    output_fields: std.ArrayList(OutputField) = .empty,
    include_types: std.ArrayList([]const u8) = .empty,
    exclude_types: std.ArrayList([]const u8) = .empty,

    pub fn deinit(self: *DfConfig, allocator: std.mem.Allocator) void {
        self.output_fields.deinit(allocator);
        self.include_types.deinit(allocator);
        self.exclude_types.deinit(allocator);
    }
};
