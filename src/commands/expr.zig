const std = @import("std");
const eval = @import("expr/eval.zig");

pub const name: []const u8 = "expr";
pub const version: []const u8 = "0.1.0";

const Val = eval.Val;

fn Parser(comptime Writer: type) type {
    return struct {
        const Self = @This();
        tokens: []const []const u8,
        pos: usize = 0,
        alloc: std.mem.Allocator,
        stderr: Writer,

        fn peek(self: *Self) ?[]const u8 {
            return if (self.pos < self.tokens.len) self.tokens[self.pos] else null;
        }

        fn next(self: *Self) ?[]const u8 {
            const t = self.peek();
            if (t != null) self.pos += 1;
            return t;
        }

        fn requireMore(self: *Self) anyerror!void {
            if (self.pos >= self.tokens.len) {
                const prev = if (self.pos > 0) self.tokens[self.pos - 1] else "";
                self.stderr.print("expr: syntax error: missing argument after '{s}'\n", .{prev}) catch {};
                return error.Handled;
            }
        }

        fn parseParen(self: *Self, evaluate: bool) anyerror!Val {
            const inner = try self.parseExpr(evaluate);
            if (self.pos >= self.tokens.len) {
                const prev = if (self.pos > 0) self.tokens[self.pos - 1] else "";
                self.stderr.print("expr: syntax error: expecting ')' after '{s}'\n", .{prev}) catch {};
                return error.Handled;
            }
            const close = self.next().?;
            if (!std.mem.eql(u8, close, ")")) {
                self.stderr.print("expr: syntax error: expecting ')' instead of '{s}'\n", .{close}) catch {};
                return error.Handled;
            }
            return inner;
        }

        fn parseSubstr(self: *Self, evaluate: bool) anyerror!Val {
            try self.requireMore();
            const s = self.next().?;
            try self.requireMore();
            const p_tok = self.next().?;
            try self.requireMore();
            const l_tok = self.next().?;
            const pos_1 = std.fmt.parseInt(usize, p_tok, 10) catch return error.SyntaxError;
            const len = std.fmt.parseInt(usize, l_tok, 10) catch return error.SyntaxError;
            if (!evaluate) return Val{ .str = "" };
            if (pos_1 == 0 or pos_1 > s.len) return Val{ .str = "" };
            const start = pos_1 - 1;
            const end = @min(s.len, start + len);
            return Val{ .str = s[start..end] };
        }

        fn parsePrimary(self: *Self, evaluate: bool) anyerror!Val {
            try self.requireMore();
            const tok = self.next().?;
            if (std.mem.eql(u8, tok, "(")) return self.parseParen(evaluate);
            if (std.mem.eql(u8, tok, ")")) {
                self.stderr.print("expr: syntax error: unexpected ')'\n", .{}) catch {};
                return error.Handled;
            }
            if (std.mem.eql(u8, tok, "length")) {
                try self.requireMore();
                const arg = self.next().?;
                if (!evaluate) return Val{ .str = "0" };
                return Val{ .str = try std.fmt.allocPrint(self.alloc, "{d}", .{arg.len}) };
            }
            if (std.mem.eql(u8, tok, "substr")) return self.parseSubstr(evaluate);
            return Val{ .str = tok };
        }

        fn parseMatch(self: *Self, evaluate: bool) anyerror!Val {
            var left = try self.parsePrimary(evaluate);
            while (self.peek()) |op| {
                if (std.mem.eql(u8, op, ":")) {
                    _ = self.next();
                    try self.requireMore();
                    const right = (try self.parsePrimary(evaluate)).str;
                    if (evaluate) left = try eval.matchRegex(left.str, right, self.alloc, self.stderr);
                } else break;
            }
            return left;
        }

        fn parseMul(self: *Self, evaluate: bool) anyerror!Val {
            var left = try self.parseMatch(evaluate);
            while (self.peek()) |op| {
                if (std.mem.eql(u8, op, "*") or std.mem.eql(u8, op, "/") or std.mem.eql(u8, op, "%")) {
                    _ = self.next();
                    try self.requireMore();
                    const right = try self.parseMatch(evaluate);
                    if (evaluate) left = try eval.evalArith(op, left.str, right.str, self.alloc, self.stderr);
                } else break;
            }
            return left;
        }

        fn parseAdd(self: *Self, evaluate: bool) anyerror!Val {
            var left = try self.parseMul(evaluate);
            while (self.peek()) |op| {
                if (std.mem.eql(u8, op, "+") or std.mem.eql(u8, op, "-")) {
                    _ = self.next();
                    try self.requireMore();
                    const right = try self.parseMul(evaluate);
                    if (evaluate) left = try eval.evalArith(op, left.str, right.str, self.alloc, self.stderr);
                } else break;
            }
            return left;
        }

        fn parseRel(self: *Self, evaluate: bool) anyerror!Val {
            var left = try self.parseAdd(evaluate);
            const ops = [_][]const u8{ "=", "==", "!=", "<", "<=", ">", ">=" };
            while (self.peek()) |op| {
                var matched = false;
                for (ops) |o| if (std.mem.eql(u8, op, o)) {
                    matched = true;
                    break;
                };
                if (!matched) break;
                _ = self.next();
                try self.requireMore();
                const right = try self.parseAdd(evaluate);
                if (evaluate) left = try eval.evalRel(op, left.str, right.str, self.alloc);
            }
            return left;
        }

        fn parseAnd(self: *Self, evaluate: bool) anyerror!Val {
            var left = try self.parseRel(evaluate);
            while (self.peek()) |op| {
                if (std.mem.eql(u8, op, "&")) {
                    _ = self.next();
                    try self.requireMore();
                    const next_eval = evaluate and !Val.isZeroOrNull(left.str);
                    const right = try self.parseRel(next_eval);
                    if (evaluate) {
                        if (!Val.isZeroOrNull(left.str) and !Val.isZeroOrNull(right.str)) {} else left = Val{ .str = "0" };
                    }
                } else break;
            }
            return left;
        }

        fn parseOr(self: *Self, evaluate: bool) anyerror!Val {
            var left = try self.parseAnd(evaluate);
            while (self.peek()) |op| {
                if (std.mem.eql(u8, op, "|")) {
                    _ = self.next();
                    try self.requireMore();
                    const next_eval = evaluate and Val.isZeroOrNull(left.str);
                    const right = try self.parseAnd(next_eval);
                    if (evaluate) {
                        if (!Val.isZeroOrNull(left.str)) {
                            // left is kept
                        } else if (!Val.isZeroOrNull(right.str)) {
                            left = right;
                        } else {
                            left = Val{ .str = "0" };
                        }
                    }
                } else break;
            }
            return left;
        }

        fn parseExpr(self: *Self, evaluate: bool) anyerror!Val {
            return self.parseOr(evaluate);
        }
    };
}

fn checkHelpVersion(args: [][]const u8, stdout: anytype) ?u8 {
    if (args.len == 2) {
        if (std.mem.eql(u8, args[1], "--help")) {
            stdout.print("Usage: expr EXPRESSION\n  or:  expr OPTION\nPrint the value of EXPRESSION to standard output.\n", .{}) catch return 3;
            stdout.flush() catch return 3;
            return 0;
        } else if (std.mem.eql(u8, args[1], "--version")) {
            stdout.print("expr (coreutilz) {s}\n", .{version}) catch return 3;
            stdout.flush() catch return 3;
            return 0;
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

    if (checkHelpVersion(args, stdout)) |rc| return rc;

    var tokens = if (args.len > 1) args[1..] else &[_][]const u8{};
    if (tokens.len > 0 and std.mem.eql(u8, tokens[0], "--")) tokens = tokens[1..];
    if (tokens.len == 0) {
        stderr.print("expr: missing operand\nTry 'expr --help' for more information.\n", .{}) catch {};
        stderr.flush() catch {};
        return 2;
    }

    const P = Parser(@TypeOf(stderr));
    var parser = P{ .tokens = tokens, .alloc = allocator, .stderr = stderr };
    const res = parser.parseExpr(true) catch |err| {
        if (err != error.Handled) stderr.print("expr: syntax error\n", .{}) catch {};
        stderr.flush() catch {};
        return 2;
    };
    if (parser.pos < parser.tokens.len) {
        stderr.print("expr: syntax error: unexpected argument '{s}'\n", .{parser.tokens[parser.pos]}) catch {};
        stderr.flush() catch {};
        return 2;
    }
    try stdout.print("{s}\n", .{res.str});
    stdout.flush() catch return 3;
    return if (Val.isZeroOrNull(res.str)) 1 else 0;
}
