const std = @import("std");

pub fn getClassChars(name: []const u8, buf: *[256]u8) ?usize {
    var count: usize = 0;
    if (std.mem.eql(u8, name, "alnum")) {
        for (0..256) |i| {
            const b: u8 = @intCast(i);
            if (std.ascii.isAlphanumeric(b)) {
                buf[count] = b;
                count += 1;
            }
        }
        return count;
    }
    if (std.mem.eql(u8, name, "alpha")) {
        for (0..256) |i| {
            const b: u8 = @intCast(i);
            if (std.ascii.isAlphabetic(b)) {
                buf[count] = b;
                count += 1;
            }
        }
        return count;
    }
    if (std.mem.eql(u8, name, "blank")) {
        buf[0] = '\t';
        buf[1] = ' ';
        return 2;
    }
    if (std.mem.eql(u8, name, "cntrl")) {
        for (0..256) |i| {
            const b: u8 = @intCast(i);
            if (std.ascii.isControl(b)) {
                buf[count] = b;
                count += 1;
            }
        }
        return count;
    }
    if (std.mem.eql(u8, name, "digit")) {
        for ('0'..'9' + 1) |b| {
            buf[count] = @intCast(b);
            count += 1;
        }
        return count;
    }
    if (std.mem.eql(u8, name, "graph")) {
        for (0..256) |i| {
            const b: u8 = @intCast(i);
            if (std.ascii.isGraphical(b)) {
                buf[count] = b;
                count += 1;
            }
        }
        return count;
    }
    if (std.mem.eql(u8, name, "lower")) {
        for ('a'..'z' + 1) |b| {
            buf[count] = @intCast(b);
            count += 1;
        }
        return count;
    }
    if (std.mem.eql(u8, name, "print")) {
        for (0..256) |i| {
            const b: u8 = @intCast(i);
            if (std.ascii.isPrint(b)) {
                buf[count] = b;
                count += 1;
            }
        }
        return count;
    }
    if (std.mem.eql(u8, name, "punct")) {
        for (0..256) |i| {
            const b: u8 = @intCast(i);
            if (std.ascii.isPunctuation(b)) {
                buf[count] = b;
                count += 1;
            }
        }
        return count;
    }
    if (std.mem.eql(u8, name, "space")) {
        for (0..256) |i| {
            const b: u8 = @intCast(i);
            if (std.ascii.isWhitespace(b)) {
                buf[count] = b;
                count += 1;
            }
        }
        return count;
    }
    if (std.mem.eql(u8, name, "upper")) {
        for ('A'..'Z' + 1) |b| {
            buf[count] = @intCast(b);
            count += 1;
        }
        return count;
    }
    if (std.mem.eql(u8, name, "xdigit")) {
        for (0..256) |i| {
            const b: u8 = @intCast(i);
            if (std.ascii.isHex(b)) {
                buf[count] = b;
                count += 1;
            }
        }
        return count;
    }
    return null;
}
