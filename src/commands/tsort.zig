const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "tsort";
pub const version: []const u8 = "0.1.0";

const Successor = struct {
    suc: *Item,
    next: ?*Successor = null,
};

const Item = struct {
    name: []const u8,
    count: usize = 0,
    top: ?*Successor = null,
    qlink: ?*Item = null,
    printed: bool = false,
};

fn readAllInput(file: ?[]const u8, alloc: std.mem.Allocator, stderr: anytype) !?[]const u8 {
    var fd: c_int = 0;
    var should_close = false;
    if (file != null and !std.mem.eql(u8, file.?, "-")) {
        const path_z = try alloc.dupeZ(u8, file.?);
        defer alloc.free(path_z);
        fd = c.open(path_z.ptr, c.O_RDONLY);
        if (fd < 0) {
            stderr.print("tsort: '{s}': No such file or directory\n", .{file.?}) catch {};
            return null;
        }
        should_close = true;
    }
    defer if (should_close) {
        _ = c.close(fd);
    };

    var list: std.ArrayListUnmanaged(u8) = .empty;
    defer list.deinit(alloc);
    var buf: [16384]u8 = undefined;
    while (true) {
        const n = c.read(fd, &buf, buf.len);
        if (n < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return null;
        }
        if (n == 0) break;
        try list.appendSlice(alloc, buf[0..@intCast(n)]);
    }
    return try list.toOwnedSlice(alloc);
}

fn itemLessThan(_: void, a: *Item, b: *Item) bool {
    return std.mem.order(u8, a.name, b.name) == .lt;
}

fn parseTokens(content: []const u8, input_name: []const u8, arena: std.mem.Allocator, stderr: anytype) !?std.ArrayListUnmanaged([]const u8) {
    var tokens: std.ArrayListUnmanaged([]const u8) = .empty;
    var it = std.mem.tokenizeAny(u8, content, " \t\r\n");
    while (it.next()) |tok| try tokens.append(arena, tok);
    if (tokens.items.len % 2 != 0) {
        stderr.print("tsort: {s}: input contains an odd number of tokens\n", .{input_name}) catch {};
        return null;
    }
    return tokens;
}

fn buildItems(tokens: [][]const u8, arena: std.mem.Allocator) ![]*Item {
    var map: std.StringHashMapUnmanaged(*Item) = .empty;
    for (tokens) |tok| {
        if (!map.contains(tok)) {
            const item = try arena.create(Item);
            item.* = .{ .name = tok };
            try map.put(arena, tok, item);
        }
    }
    var items = try arena.alloc(*Item, map.count());
    var it = map.valueIterator();
    var idx: usize = 0;
    while (it.next()) |item_ptr| : (idx += 1) {
        items[idx] = item_ptr.*;
    }
    std.mem.sort(*Item, items, {}, itemLessThan);
    var i: usize = 0;
    while (i < tokens.len) : (i += 2) {
        const j = map.get(tokens[i]).?;
        const k = map.get(tokens[i + 1]).?;
        if (j != k) {
            k.count += 1;
            const p = try arena.create(Successor);
            p.* = .{ .suc = k, .next = j.top };
            j.top = p;
        }
    }
    return items;
}

fn scanZeros(items: []*Item, head_ptr: *?*Item, zeros_ptr: *?*Item) void {
    for (items) |k| {
        if (k.count == 0 and !k.printed) {
            if (head_ptr.* == null) {
                head_ptr.* = k;
            } else {
                zeros_ptr.*.?.qlink = k;
            }
            zeros_ptr.* = k;
        }
    }
}

fn drainQueue(head_ptr: *?*Item, zeros_ptr: *?*Item, n_strings: *usize, stdout: anytype) !void {
    while (head_ptr.*) |head| {
        try stdout.print("{s}\n", .{head.name});
        head.printed = true;
        n_strings.* -= 1;
        var p = head.top;
        while (p) |suc_node| : (p = suc_node.next) {
            suc_node.suc.count -= 1;
            if (suc_node.suc.count == 0) {
                zeros_ptr.*.?.qlink = suc_node.suc;
                zeros_ptr.* = suc_node.suc;
            }
        }
        head_ptr.* = head.qlink;
    }
}

fn retraceLoop(k: *Item, loop_ptr: *?*Item, p: *Successor, p_opt: *?*Successor, stderr: anytype) void {
    var curr = loop_ptr.*;
    while (curr) |c_node| {
        const tmp = c_node.qlink;
        stderr.print("tsort: {s}\n", .{c_node.name}) catch {};
        if (c_node == k) {
            p.suc.count -= 1;
            p_opt.* = p.next;
            break;
        }
        c_node.qlink = null;
        curr = tmp;
    }
    while (curr) |c_node| {
        const tmp = c_node.qlink;
        c_node.qlink = null;
        curr = tmp;
    }
    loop_ptr.* = null;
}

fn detectLoopStep(items: []*Item, loop_ptr: *?*Item, stderr: anytype) bool {
    for (items) |k| {
        if (k.count == 0) continue;
        if (loop_ptr.* == null) {
            loop_ptr.* = k;
            continue;
        }
        var p_opt = &k.top;
        while (p_opt.*) |p| : (p_opt = &p.next) {
            if (p.suc == loop_ptr.*) {
                if (k.qlink != null) {
                    retraceLoop(k, loop_ptr, p, p_opt, stderr);
                    return true;
                }
                k.qlink = loop_ptr.*;
                loop_ptr.* = k;
                break;
            }
        }
    }
    return false;
}

fn executeSort(items: []*Item, input_name: []const u8, stdout: anytype, stderr: anytype) !bool {
    var head: ?*Item = null;
    var zeros: ?*Item = null;
    var n_strings = items.len;
    var ok = true;

    while (n_strings > 0) {
        scanZeros(items, &head, &zeros);
        try drainQueue(&head, &zeros, &n_strings, stdout);
        if (n_strings > 0) {
            stderr.print("tsort: {s}: input contains a loop:\n", .{input_name}) catch {};
            ok = false;
            var loop: ?*Item = null;
            while (true) {
                if (detectLoopStep(items, &loop, stderr)) break;
            }
        }
    }
    return ok;
}

fn parseArgs(args: [][]const u8, input_file: *?[]const u8, stdout: anytype, stderr: anytype) ?u8 {
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            stdout.print("Usage: tsort [OPTION] [FILE]\nWrite totally ordered list consistent with the partial ordering in FILE.\n", .{}) catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            stdout.print("tsort (coreutilz) {s}\n", .{version}) catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "-w")) {
            continue;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            stderr.print("tsort: unrecognized option '{s}'\nTry 'tsort --help' for more information.\n", .{arg}) catch {};
            return 1;
        } else if (std.mem.startsWith(u8, arg, "-") and !std.mem.eql(u8, arg, "-")) {
            stderr.print("tsort: invalid option -- '{c}'\nTry 'tsort --help' for more information.\n", .{arg[1]}) catch {};
            return 1;
        } else if (input_file.* == null) {
            input_file.* = arg;
        } else {
            stderr.print("tsort: extra operand '{s}'\nTry 'tsort --help' for more information.\n", .{arg}) catch {};
            return 1;
        }
    }
    return null;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    var input_file: ?[]const u8 = null;
    if (parseArgs(args, &input_file, stdout, stderr)) |rc| {
        stdout.flush() catch return 1;
        stderr.flush() catch {};
        return rc;
    }

    const disp_name = input_file orelse "-";
    const data = (try readAllInput(input_file, allocator, stderr)) orelse {
        stderr.flush() catch {};
        return 1;
    };
    defer allocator.free(data);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const tokens = (try parseTokens(data, disp_name, arena.allocator(), stderr)) orelse {
        stderr.flush() catch {};
        return 1;
    };
    const items = try buildItems(tokens.items, arena.allocator());
    const ok = try executeSort(items, disp_name, stdout, stderr);

    stdout.flush() catch return 1;
    stderr.flush() catch {};
    return if (ok) 0 else 1;
}
