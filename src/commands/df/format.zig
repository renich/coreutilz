const std = @import("std");
const types = @import("types.zig");

pub const ColumnDef = struct {
    field: types.OutputField,
    header: []const u8,
    is_right: bool,
};

pub fn resolveColumns(cfg: *const types.DfConfig, allocator: std.mem.Allocator) !std.ArrayList(ColumnDef) {
    var cols = std.ArrayList(ColumnDef).empty;
    if (cfg.custom_output) {
        for (cfg.output_fields.items) |f| {
            try cols.append(allocator, getColumnDef(f, cfg));
        }
        return cols;
    }

    try cols.append(allocator, .{ .field = .source, .header = "Filesystem", .is_right = false });
    if (cfg.print_type) {
        try cols.append(allocator, .{ .field = .fstype, .header = "Type", .is_right = false });
    }
    if (cfg.inodes_mode) {
        try cols.append(allocator, .{ .field = .itotal, .header = "Inodes", .is_right = true });
        try cols.append(allocator, .{ .field = .iused, .header = "IUsed", .is_right = true });
        try cols.append(allocator, .{ .field = .iavail, .header = "IFree", .is_right = true });
        try cols.append(allocator, .{ .field = .ipcent, .header = "IUse%", .is_right = true });
    } else {
        const size_hdr = if (cfg.portability) "1024-blocks" else if (cfg.display_mode != .block_size) "Size" else cfg.block_label;
        const avail_hdr = if (cfg.display_mode != .block_size) "Avail" else "Available";
        const cap_hdr = if (cfg.portability) "Capacity" else "Use%";
        try cols.append(allocator, .{ .field = .size, .header = size_hdr, .is_right = true });
        try cols.append(allocator, .{ .field = .used, .header = "Used", .is_right = true });
        try cols.append(allocator, .{ .field = .avail, .header = avail_hdr, .is_right = true });
        try cols.append(allocator, .{ .field = .pcent, .header = cap_hdr, .is_right = true });
    }
    try cols.append(allocator, .{ .field = .target, .header = "Mounted on", .is_right = false });
    return cols;
}

fn getColumnDef(f: types.OutputField, cfg: *const types.DfConfig) ColumnDef {
    return switch (f) {
        .source => .{ .field = .source, .header = "Filesystem", .is_right = false },
        .fstype => .{ .field = .fstype, .header = "Type", .is_right = false },
        .itotal => .{ .field = .itotal, .header = "Inodes", .is_right = true },
        .iused => .{ .field = .iused, .header = "IUsed", .is_right = true },
        .iavail => .{ .field = .iavail, .header = "IFree", .is_right = true },
        .ipcent => .{ .field = .ipcent, .header = "IUse%", .is_right = true },
        .size => .{ .field = .size, .header = if (cfg.display_mode != .block_size) "Size" else cfg.block_label, .is_right = true },
        .used => .{ .field = .used, .header = "Used", .is_right = true },
        .avail => .{ .field = .avail, .header = "Avail", .is_right = true },
        .pcent => .{ .field = .pcent, .header = "Use%", .is_right = true },
        .file => .{ .field = .file, .header = "File", .is_right = false },
        .target => .{ .field = .target, .header = "Mounted on", .is_right = false },
    };
}

pub fn printTable(
    mounts: []const types.MountInfo,
    cfg: *const types.DfConfig,
    cols: []const ColumnDef,
    allocator: std.mem.Allocator,
    stdout: anytype,
) !void {
    const total_rows = mounts.len + (if (cfg.grand_total) @as(usize, 1) else @as(usize, 0));
    const widths = try allocator.alloc(usize, cols.len);
    defer allocator.free(widths);

    const grid = try allocator.alloc([]const u8, total_rows * cols.len);
    defer {
        for (grid) |s| allocator.free(s);
        allocator.free(grid);
    }

    computeGrid(mounts, cfg, cols, grid, widths, allocator);
    try outputGrid(cols, grid, widths, total_rows, stdout);
}

fn computeGrid(
    mounts: []const types.MountInfo,
    cfg: *const types.DfConfig,
    cols: []const ColumnDef,
    grid: [][]const u8,
    widths: []usize,
    allocator: std.mem.Allocator,
) void {
    for (cols, 0..) |col, j| widths[j] = col.header.len;

    for (mounts, 0..) |*m, i| {
        for (cols, 0..) |col, j| {
            var buf: [64]u8 = undefined;
            const str = formatCell(m, col.field, cfg, &buf);
            grid[i * cols.len + j] = allocator.dupe(u8, str) catch "";
            if (str.len > widths[j]) widths[j] = str.len;
        }
    }

    if (cfg.grand_total) {
        computeTotalRow(mounts, cfg, cols, grid, widths, allocator);
    }
}

fn outputGrid(cols: []const ColumnDef, grid: []const []const u8, widths: []const usize, total_rows: usize, stdout: anytype) !void {
    for (cols, 0..) |col, j| {
        if (j > 0) try stdout.writeByte(' ');
        try printPadded(col.header, widths[j], col.is_right, j == cols.len - 1, stdout);
    }
    try stdout.writeByte('\n');

    for (0..total_rows) |i| {
        for (cols, 0..) |col, j| {
            if (j > 0) try stdout.writeByte(' ');
            const val = grid[i * cols.len + j];
            try printPadded(val, widths[j], col.is_right, j == cols.len - 1, stdout);
        }
        try stdout.writeByte('\n');
    }
}

fn printPadded(str: []const u8, width: usize, is_right: bool, is_last: bool, stdout: anytype) !void {
    const pad = if (width > str.len) width - str.len else 0;
    if (is_right) {
        for (0..pad) |_| try stdout.writeByte(' ');
        try stdout.writeAll(str);
    } else {
        try stdout.writeAll(str);
        if (!is_last) {
            for (0..pad) |_| try stdout.writeByte(' ');
        }
    }
}

fn formatCell(m: *const types.MountInfo, f: types.OutputField, cfg: *const types.DfConfig, buf: []u8) []const u8 {
    if (!m.stat_ok) {
        return switch (f) {
            .source => m.fsname,
            .fstype => "-",
            .file => m.file_operand orelse "-",
            .target => m.dir,
            else => "-",
        };
    }
    const total_bytes = m.f_blocks * m.f_frsize;
    const free_bytes = m.f_bfree * m.f_frsize;
    const avail_bytes = m.f_bavail * m.f_frsize;
    const used_bytes = if (total_bytes > free_bytes) total_bytes - free_bytes else 0;

    return switch (f) {
        .source => m.fsname,
        .fstype => m.fstype,
        .itotal => std.fmt.bufPrint(buf, "{d}", .{m.f_files}) catch "?",
        .iused => std.fmt.bufPrint(buf, "{d}", .{if (m.f_files >= m.f_ffree) m.f_files - m.f_ffree else 0}) catch "?",
        .iavail => std.fmt.bufPrint(buf, "{d}", .{m.f_favail}) catch "?",
        .ipcent => formatPercent(if (m.f_files >= m.f_ffree) m.f_files - m.f_ffree else 0, m.f_favail, buf),
        .size => formatScaled(total_bytes, cfg, buf),
        .used => formatScaled(used_bytes, cfg, buf),
        .avail => formatScaled(avail_bytes, cfg, buf),
        .pcent => formatPercent(used_bytes, avail_bytes, buf),
        .file => m.file_operand orelse "-",
        .target => m.dir,
    };
}

const TotalStats = struct {
    tot_size: u64 = 0,
    tot_used: u64 = 0,
    tot_avail: u64 = 0,
    tot_files: u64 = 0,
    tot_iused: u64 = 0,
    tot_ifree: u64 = 0,
};

fn sumTotalStats(mounts: []const types.MountInfo) TotalStats {
    var s = TotalStats{};
    for (mounts) |*m| {
        const tb = m.f_blocks * m.f_frsize;
        const fb = m.f_bfree * m.f_frsize;
        s.tot_size += tb;
        s.tot_used += if (tb > fb) tb - fb else 0;
        s.tot_avail += m.f_bavail * m.f_frsize;
        s.tot_files += m.f_files;
        s.tot_iused += if (m.f_files >= m.f_ffree) m.f_files - m.f_ffree else 0;
        s.tot_ifree += m.f_favail;
    }
    return s;
}

fn computeTotalRow(
    mounts: []const types.MountInfo,
    cfg: *const types.DfConfig,
    cols: []const ColumnDef,
    grid: [][]const u8,
    widths: []usize,
    allocator: std.mem.Allocator,
) void {
    const s = sumTotalStats(mounts);
    const row_idx = mounts.len;
    var has_source = false;
    for (cols) |col| if (col.field == .source) {
        has_source = true;
        break;
    };

    for (cols, 0..) |col, j| {
        var buf: [64]u8 = undefined;
        const str = formatTotalCell(col.field, cfg, has_source, j == 0, s.tot_size, s.tot_used, s.tot_avail, s.tot_files, s.tot_iused, s.tot_ifree, &buf);
        grid[row_idx * cols.len + j] = allocator.dupe(u8, str) catch "";
        if (str.len > widths[j]) widths[j] = str.len;
    }
}

fn formatTotalCell(
    f: types.OutputField,
    cfg: *const types.DfConfig,
    has_source: bool,
    is_first: bool,
    tot_size: u64,
    tot_used: u64,
    tot_avail: u64,
    tot_files: u64,
    tot_iused: u64,
    tot_ifree: u64,
    buf: []u8,
) []const u8 {
    return switch (f) {
        .source => "total",
        .fstype, .file => "-",
        .target => if (has_source or !is_first) "-" else "total",
        .itotal => std.fmt.bufPrint(buf, "{d}", .{tot_files}) catch "?",
        .iused => std.fmt.bufPrint(buf, "{d}", .{tot_iused}) catch "?",
        .iavail => std.fmt.bufPrint(buf, "{d}", .{tot_ifree}) catch "?",
        .ipcent => formatPercent(tot_iused, tot_ifree, buf),
        .size => formatScaled(tot_size, cfg, buf),
        .used => formatScaled(tot_used, cfg, buf),
        .avail => formatScaled(tot_avail, cfg, buf),
        .pcent => formatPercent(tot_used, tot_avail, buf),
    };
}

fn formatPercent(used: u64, avail: u64, buf: []u8) []const u8 {
    const total = used + avail;
    if (total == 0) return "-";
    const used_times_100 = used * 100;
    const pct = used_times_100 / total + (if (used_times_100 % total != 0) @as(u64, 1) else @as(u64, 0));
    return std.fmt.bufPrint(buf, "{d}%", .{pct}) catch "-";
}

fn formatScaled(bytes: u64, cfg: *const types.DfConfig, buf: []u8) []const u8 {
    if (bytes == 0 and cfg.display_mode != .block_size) return "0";
    return switch (cfg.display_mode) {
        .human_1024 => formatHuman(bytes, 1024.0, &[_]u8{ 'B', 'K', 'M', 'G', 'T', 'P' }, buf),
        .human_1000 => formatHuman(bytes, 1000.0, &[_]u8{ 'B', 'k', 'M', 'G', 'T', 'P' }, buf),
        .block_size => {
            const count = (bytes + cfg.block_size - 1) / cfg.block_size;
            return std.fmt.bufPrint(buf, "{d}", .{count}) catch "?";
        },
    };
}

fn formatHuman(bytes: u64, divisor: f64, units: []const u8, buf: []u8) []const u8 {
    if (bytes == 0) return "0";
    var f_size: f64 = @floatFromInt(bytes);
    var u_idx: usize = 0;
    while (f_size >= divisor and u_idx + 1 < units.len) {
        f_size /= divisor;
        u_idx += 1;
    }
    if (u_idx == 0) return std.fmt.bufPrint(buf, "{d}", .{bytes}) catch "?";
    if (f_size < 9.95) return std.fmt.bufPrint(buf, "{d:.1}{c}", .{ f_size, units[u_idx] }) catch "?";
    const rounded: u64 = @intFromFloat(@round(f_size));
    return std.fmt.bufPrint(buf, "{d}{c}", .{ rounded, units[u_idx] }) catch "?";
}
