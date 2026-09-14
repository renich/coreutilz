const std = @import("std");

pub const DiredContext = struct {
    enabled: bool,
    pos: usize = 0,
    dired_positions: std.ArrayList(usize),
    subdired_positions: std.ArrayList(usize),

    pub fn init(allocator: std.mem.Allocator, enabled: bool) DiredContext {
        _ = allocator;
        return .{
            .enabled = enabled,
            .pos = 0,
            .dired_positions = std.ArrayList(usize).empty,
            .subdired_positions = std.ArrayList(usize).empty,
        };
    }

    pub fn writeBytes(self: *DiredContext, writer: anytype, bytes: []const u8) !void {
        try writer.writeAll(bytes);
        if (self.enabled) {
            self.pos += bytes.len;
        }
    }

    pub fn writeByte(self: *DiredContext, writer: anytype, b: u8) !void {
        try writer.writeByte(b);
        if (self.enabled) {
            self.pos += 1;
        }
    }

    pub fn print(self: *DiredContext, writer: anytype, comptime fmt: []const u8, args: anytype) !void {
        if (!self.enabled) {
            try writer.print(fmt, args);
            return;
        }
        var buf: [1024]u8 = undefined;
        if (std.fmt.bufPrint(&buf, fmt, args)) |s| {
            try writer.writeAll(s);
            self.pos += s.len;
        } else |_| {
            // Fallback for large formatted strings
            var list = std.ArrayList(u8).empty;
            const alloc = std.heap.c_allocator;
            defer list.deinit(alloc);
            try list.writer(alloc).print(fmt, args);
            try writer.writeAll(list.items);
            self.pos += list.items.len;
        }
    }

    pub fn indent(self: *DiredContext, writer: anytype) !void {
        if (self.enabled) {
            try self.writeBytes(writer, "  ");
        }
    }

    pub fn pushDired(self: *DiredContext, arena: std.mem.Allocator) !void {
        if (self.enabled) {
            try self.dired_positions.append(arena, self.pos);
        }
    }

    pub fn pushSubdired(self: *DiredContext, arena: std.mem.Allocator) !void {
        if (self.enabled) {
            try self.subdired_positions.append(arena, self.pos);
        }
    }

    pub fn finish(self: *DiredContext, writer: anytype, quoting_style_name: []const u8) !void {
        if (!self.enabled) return;
        if (self.dired_positions.items.len > 0) {
            try writer.writeAll("//DIRED//");
            for (self.dired_positions.items) |p| {
                try writer.print(" {d}", .{p});
            }
            try writer.writeByte('\n');
        }
        if (self.subdired_positions.items.len > 0) {
            try writer.writeAll("//SUBDIRED//");
            for (self.subdired_positions.items) |p| {
                try writer.print(" {d}", .{p});
            }
            try writer.writeByte('\n');
        }
        try writer.print("//DIRED-OPTIONS// --quoting-style={s}\n", .{quoting_style_name});
    }
};
