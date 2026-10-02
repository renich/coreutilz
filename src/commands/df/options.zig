const std = @import("std");
const types = @import("types.zig");

pub const ParsedDf = struct {
    cfg: types.DfConfig,
    operands: std.ArrayList([]const u8) = .empty,
    early_exit: ?u8 = null,

    pub fn deinit(self: *ParsedDf, allocator: std.mem.Allocator) void {
        self.cfg.deinit(allocator);
        self.operands.deinit(allocator);
    }
};

pub fn parseArgs(args: [][]const u8, allocator: std.mem.Allocator, stdout: anytype, stderr: anytype) !ParsedDf {
    var res = ParsedDf{ .cfg = .{} };
    var parsing_options = true;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (parsing_options and std.mem.eql(u8, arg, "--")) {
            parsing_options = false;
            continue;
        }
        if (parsing_options and std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            const cont = try handleOption(arg, &i, args, &res, allocator, stdout, stderr);
            if (!cont) return res;
        } else {
            try res.operands.append(allocator, arg);
        }
    }
    return res;
}

fn handleOption(arg: []const u8, i: *usize, args: [][]const u8, res: *ParsedDf, allocator: std.mem.Allocator, stdout: anytype, stderr: anytype) !bool {
    if (std.mem.startsWith(u8, arg, "--")) {
        return handleLongOpt(arg, res, allocator, stdout, stderr);
    }
    return handleShortOpts(arg[1..], i, args, res, allocator, stderr);
}

fn handleLongOpt(arg: []const u8, res: *ParsedDf, allocator: std.mem.Allocator, stdout: anytype, stderr: anytype) !bool {
    if (std.mem.eql(u8, arg, "--help")) {
        try printHelp(stdout);
        stdout.flush() catch {
            res.early_exit = 1;
            return false;
        };
        res.early_exit = 0;
        return false;
    } else if (std.mem.eql(u8, arg, "--version")) {
        try stdout.print("df (coreutilz) 0.1.0\n", .{});
        stdout.flush() catch {
            res.early_exit = 1;
            return false;
        };
        res.early_exit = 0;
        return false;
    }
    return handleLongConfigOpt(arg, res, allocator, stderr);
}

fn handleLongConfigOpt(arg: []const u8, res: *ParsedDf, allocator: std.mem.Allocator, stderr: anytype) !bool {
    if (std.mem.eql(u8, arg, "--all")) {
        res.cfg.all = true;
    } else if (std.mem.eql(u8, arg, "--human-readable")) {
        res.cfg.display_mode = .human_1024;
    } else if (std.mem.eql(u8, arg, "--si")) {
        res.cfg.display_mode = .human_1000;
    } else if (std.mem.eql(u8, arg, "--inodes")) {
        if (!checkMutualExclusion(&res.cfg, "-i", stderr)) {
            res.early_exit = 1;
            return false;
        }
        res.cfg.inodes_mode = true;
    } else if (std.mem.eql(u8, arg, "--portability")) {
        if (!checkMutualExclusion(&res.cfg, "-P", stderr)) {
            res.early_exit = 1;
            return false;
        }
        res.cfg.portability = true;
    } else if (std.mem.eql(u8, arg, "--print-type")) {
        if (!checkMutualExclusion(&res.cfg, "-T", stderr)) {
            res.early_exit = 1;
            return false;
        }
        res.cfg.print_type = true;
    } else {
        return handleLongMiscOpt(arg, res, allocator, stderr);
    }
    return true;
}

fn handleLongMiscOpt(arg: []const u8, res: *ParsedDf, allocator: std.mem.Allocator, stderr: anytype) !bool {
    if (std.mem.eql(u8, arg, "--local")) {
        res.cfg.local_only = true;
    } else if (std.mem.eql(u8, arg, "--total")) {
        res.cfg.grand_total = true;
    } else if (std.mem.eql(u8, arg, "--sync")) {
        res.cfg.do_sync = true;
    } else if (std.mem.eql(u8, arg, "--no-sync")) {
        res.cfg.do_sync = false;
    } else if (std.mem.startsWith(u8, arg, "--block-size=")) {
        parseBlockSize(arg["--block-size=".len..], &res.cfg);
    } else if (std.mem.startsWith(u8, arg, "--type=")) {
        try res.cfg.include_types.append(allocator, arg["--type=".len..]);
    } else if (std.mem.startsWith(u8, arg, "--exclude-type=")) {
        try res.cfg.exclude_types.append(allocator, arg["--exclude-type=".len..]);
    } else if (std.mem.startsWith(u8, arg, "--output=") or std.mem.startsWith(u8, arg, "--out=") or std.mem.startsWith(u8, arg, "--o=")) {
        const val = if (std.mem.indexOfScalar(u8, arg, '=')) |idx| arg[idx + 1 ..] else "";
        return parseOutputFieldList(val, res, allocator, stderr);
    } else if (std.mem.eql(u8, arg, "--output") or std.mem.eql(u8, arg, "--out") or std.mem.eql(u8, arg, "--o")) {
        return parseOutputFieldList("", res, allocator, stderr);
    } else {
        try stderr.print("df: unrecognized option '{s}'\nTry 'df --help' for more information.\n", .{arg});
        res.early_exit = 1;
        return false;
    }
    return true;
}

fn handleShortOpts(opts: []const u8, i: *usize, args: [][]const u8, res: *ParsedDf, allocator: std.mem.Allocator, stderr: anytype) !bool {
    var idx: usize = 0;
    while (idx < opts.len) : (idx += 1) {
        const ch = opts[idx];
        switch (ch) {
            'a' => res.cfg.all = true,
            'h' => res.cfg.display_mode = .human_1024,
            'H' => res.cfg.display_mode = .human_1000,
            'k' => setBlockSizePreset(&res.cfg, 1024, "1K-blocks"),
            'm' => setBlockSizePreset(&res.cfg, 1024 * 1024, "1M-blocks"),
            'l' => res.cfg.local_only = true,
            'v' => {},
            'i' => if (!checkShortMutual(&res.cfg, "-i", &res.early_exit, stderr)) return false else {
                res.cfg.inodes_mode = true;
            },
            'P' => if (!checkShortMutual(&res.cfg, "-P", &res.early_exit, stderr)) return false else {
                res.cfg.portability = true;
            },
            'T' => if (!checkShortMutual(&res.cfg, "-T", &res.early_exit, stderr)) return false else {
                res.cfg.print_type = true;
            },
            'B', 't', 'x' => {
                const opt_val = getOptVal(opts, idx, i, args, ch, stderr) orelse {
                    res.early_exit = 1;
                    return false;
                };
                if (ch == 'B') parseBlockSize(opt_val, &res.cfg) else if (ch == 't') try res.cfg.include_types.append(allocator, opt_val) else try res.cfg.exclude_types.append(allocator, opt_val);
                return true;
            },
            else => {
                try stderr.print("df: invalid option -- '{c}'\nTry 'df --help' for more information.\n", .{ch});
                res.early_exit = 1;
                return false;
            },
        }
    }
    return true;
}

fn setBlockSizePreset(cfg: *types.DfConfig, sz: u64, lbl: []const u8) void {
    cfg.display_mode = .block_size;
    cfg.block_size = sz;
    cfg.block_label = lbl;
}

fn checkShortMutual(cfg: *const types.DfConfig, flag: []const u8, early_exit: *?u8, stderr: anytype) bool {
    if (!checkMutualExclusion(cfg, flag, stderr)) {
        early_exit.* = 1;
        return false;
    }
    return true;
}

fn getOptVal(opts: []const u8, idx: usize, i: *usize, args: [][]const u8, ch: u8, stderr: anytype) ?[]const u8 {
    if (idx + 1 < opts.len) return opts[idx + 1 ..];
    if (i.* + 1 < args.len) {
        i.* += 1;
        return args[i.*];
    }
    stderr.print("df: option requires an argument -- '{c}'\nTry 'df --help' for more information.\n", .{ch}) catch {};
    return null;
}

fn parseBlockSize(val: []const u8, cfg: *types.DfConfig) void {
    if (val.len == 0) return;
    cfg.display_mode = .block_size;
    if (std.mem.eql(u8, val, "1K") or std.mem.eql(u8, val, "1024") or std.mem.eql(u8, val, "1k")) {
        setBlockSizePreset(cfg, 1024, "1K-blocks");
    } else if (std.mem.eql(u8, val, "1M")) {
        setBlockSizePreset(cfg, 1024 * 1024, "1M-blocks");
    } else if (std.mem.eql(u8, val, "1G")) {
        setBlockSizePreset(cfg, 1024 * 1024 * 1024, "1G-blocks");
    } else if (std.fmt.parseInt(u64, val, 10)) |num| {
        setBlockSizePreset(cfg, num, "blocks");
    } else |_| {
        setBlockSizePreset(cfg, 1024, "1K-blocks");
    }
}

fn checkMutualExclusion(cfg: *const types.DfConfig, opt_name: []const u8, stderr: anytype) bool {
    if (cfg.custom_output) {
        stderr.print("df: options {s} and --output are mutually exclusive\nTry 'df --help' for more information.\n", .{opt_name}) catch {};
        return false;
    }
    return true;
}

fn parseOutputFieldList(val: []const u8, res: *ParsedDf, allocator: std.mem.Allocator, stderr: anytype) !bool {
    if (res.cfg.inodes_mode) return emitMutualError("-i", res, stderr);
    if (res.cfg.portability) return emitMutualError("-P", res, stderr);
    if (res.cfg.print_type) return emitMutualError("-T", res, stderr);

    res.cfg.custom_output = true;
    if (val.len == 0) {
        const all_fields = [_]types.OutputField{ .source, .fstype, .itotal, .iused, .iavail, .ipcent, .size, .used, .avail, .pcent, .file, .target };
        for (all_fields) |f| try res.cfg.output_fields.append(allocator, f);
        return true;
    }

    var iter = std.mem.splitScalar(u8, val, ',');
    while (iter.next()) |token| {
        if (token.len == 0) continue;
        const field = types.OutputField.fromString(token) orelse {
            try stderr.print("df: option --output: invalid field '{s}'\nTry 'df --help' for more information.\n", .{token});
            res.early_exit = 1;
            return false;
        };
        for (res.cfg.output_fields.items) |existing| {
            if (existing == field) {
                try stderr.print("df: option --output: field '{s}' used more than once\nTry 'df --help' for more information.\n", .{token});
                res.early_exit = 1;
                return false;
            }
        }
        try res.cfg.output_fields.append(allocator, field);
    }
    return true;
}

fn emitMutualError(opt: []const u8, res: *ParsedDf, stderr: anytype) !bool {
    try stderr.print("df: options {s} and --output are mutually exclusive\nTry 'df --help' for more information.\n", .{opt});
    res.early_exit = 1;
    return false;
}

fn printHelp(stdout: anytype) !void {
    try stdout.print(
        \\Usage: df [OPTION]... [FILE]...
        \\Show information about the file system on which each FILE resides,
        \\or all file systems by default.
        \\
        \\  -a, --all             include pseudo, duplicate, inaccessible file systems
        \\  -B, --block-size=SIZE scale sizes by SIZE before printing them
        \\  -h, --human-readable  print sizes in powers of 1024 (e.g., 1023M)
        \\  -H, --si              print sizes in powers of 1000 (e.g., 1.1G)
        \\  -i, --inodes          list inode information instead of block usage
        \\  -k                    like --block-size=1K
        \\  -l, --local           limit listing to local file systems
        \\      --no-sync         do not acquire a sync before getting usage info (default)
        \\      --output[=FIELD_LIST] use the output format defined by FIELD_LIST,
        \\                            or print all fields if FIELD_LIST is omitted.
        \\  -P, --portability     use the POSIX output format
        \\      --sync            invoke sync before getting usage info
        \\      --total           produce a grand total
        \\  -t, --type=TYPE       limit listing to file systems of type TYPE
        \\  -T, --print-type      print file system type
        \\  -x, --exclude-type=TYPE limit listing to file systems not of type TYPE
        \\  -v                    (ignored)
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
        \\FIELD_LIST is a comma-separated list of columns to be included.  Valid
        \\field names are: 'source', 'fstype', 'itotal', 'iused', 'iavail', 'ipcent',
        \\'size', 'used', 'avail', 'pcent', 'file' and 'target'.
        \\
    , .{});
}
