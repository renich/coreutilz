const std = @import("std");

pub const DisplayMode = union(enum) {
    block_size: u64,
    human_1024,
    human_1000,
};

pub const TimeType = enum {
    none,
    mtime,
    atime,
    ctime,
};

pub const TimeStyle = union(enum) {
    iso,
    long_iso,
    full_iso,
    custom: []const u8,
};

pub const DevIno = struct {
    dev: u64,
    ino: u64,
};

pub const ExcludeRule = struct {
    pattern: []const u8,
    has_slash: bool,
};

pub const DuStats = struct {
    size: u64 = 0,
    inodes: u64 = 0,
    tmax: i64 = 0,
    tmax_nsec: i64 = 0,

    pub fn add(self: *DuStats, other: DuStats) void {
        self.size += other.size;
        self.inodes += other.inodes;
        if (other.tmax > self.tmax or (other.tmax == self.tmax and other.tmax_nsec > self.tmax_nsec)) {
            self.tmax = other.tmax;
            self.tmax_nsec = other.tmax_nsec;
        }
    }
};

pub const DuConfig = struct {
    apparent_size: bool = false,
    all_files: bool = false,
    summarize_only: bool = false,
    max_depth: ?usize = null,
    separate_dirs: bool = false,
    count_links: bool = false,
    total: bool = false,
    one_file_system: bool = false,
    null_terminate: bool = false,
    inodes_mode: bool = false,
    dereference_all: bool = false,
    dereference_args: bool = false,
    threshold: ?i64 = null,
    display_mode: DisplayMode = .{ .block_size = 1024 },
    time_type: TimeType = .none,
    time_style: TimeStyle = .long_iso,
    excludes: std.ArrayList(ExcludeRule),
    files0_from: ?[]const u8 = null,

    pub fn deinit(self: *DuConfig, allocator: std.mem.Allocator) void {
        for (self.excludes.items) |rule| {
            allocator.free(rule.pattern);
        }
        self.excludes.deinit(allocator);
    }
};
