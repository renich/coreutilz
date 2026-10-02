const std = @import("std");
const eval = @import("test/eval.zig");

pub const name: []const u8 = "test";
pub const version: []const u8 = "0.1.0";

const EvalError = eval.EvalError;

fn Parser(comptime Writer: type) type {
    return struct {
        const Self = @This();
        args: []const []const u8,
        pos: usize,
        prog: []const u8,
        stderr: Writer,

        fn beyond(self: *Self) EvalError {
            const last = if (self.args.len > 0) self.args[self.args.len - 1] else "";
            self.stderr.print("{s}: missing argument after '{s}'\n", .{ self.prog, last }) catch {};
            return error.Handled;
        }

        fn oneArg(self: *Self) bool {
            const val = self.args[self.pos].len > 0;
            self.pos += 1;
            return val;
        }

        fn twoArgs(self: *Self) EvalError!bool {
            if (self.pos >= self.args.len) return self.beyond();
            const a0 = self.args[self.pos];
            if (std.mem.eql(u8, a0, "!")) {
                self.pos += 1;
                return !self.oneArg();
            }
            if (a0.len == 2 and a0[0] == '-') {
                if (!eval.isUnaryOp(a0)) {
                    self.stderr.print("{s}: '{s}': unary operator expected\n", .{ self.prog, a0 }) catch {};
                    return error.Handled;
                }
                self.pos += 1;
                if (self.pos >= self.args.len) return self.beyond();
                const arg = self.args[self.pos];
                self.pos += 1;
                return eval.evalUnary(a0, arg) orelse false;
            }
            return self.beyond();
        }

        fn threeArgs(self: *Self) EvalError!bool {
            if (self.pos + 2 >= self.args.len) return self.beyond();
            const a0 = self.args[self.pos];
            const a1 = self.args[self.pos + 1];
            const a2 = self.args[self.pos + 2];
            if (eval.isBinaryOp(a1)) {
                self.pos += 3;
                const res = try eval.evalBinary(a1, a0, a2, self.prog, self.stderr);
                return res orelse false;
            }
            if (std.mem.eql(u8, a0, "!")) {
                self.pos += 1;
                return !(try self.twoArgs());
            }
            if (std.mem.eql(u8, a0, "(") and std.mem.eql(u8, a2, ")")) {
                self.pos += 1;
                const val = self.oneArg();
                self.pos += 1;
                return val;
            }
            if (std.mem.eql(u8, a1, "-a") or std.mem.eql(u8, a1, "-o")) {
                return self.expr();
            }
            self.stderr.print("{s}: '{s}': binary operator expected\n", .{ self.prog, a1 }) catch {};
            return error.Handled;
        }

        fn termParen(self: *Self) EvalError!bool {
            self.pos += 1;
            var nargs: usize = 1;
            while (self.pos + nargs < self.args.len and !std.mem.eql(u8, self.args[self.pos + nargs], ")")) : (nargs += 1) {
                if (nargs == 4) {
                    nargs = self.args.len - self.pos;
                    break;
                }
            }
            const value = try self.posixTest(nargs);
            if (self.pos >= self.args.len) {
                self.stderr.print("{s}: ')' expected\n", .{self.prog}) catch {};
                return error.Handled;
            }
            if (!std.mem.eql(u8, self.args[self.pos], ")")) {
                self.stderr.print("{s}: ')' expected, found '{s}'\n", .{ self.prog, self.args[self.pos] }) catch {};
                return error.Handled;
            }
            self.pos += 1;
            return value;
        }

        fn term(self: *Self) EvalError!bool {
            var negated = false;
            while (self.pos < self.args.len and std.mem.eql(u8, self.args[self.pos], "!")) {
                self.pos += 1;
                negated = !negated;
            }
            if (self.pos >= self.args.len) return self.beyond();

            var value: bool = false;
            if (std.mem.eql(u8, self.args[self.pos], "(")) {
                value = try self.termParen();
            } else if (self.args.len - self.pos >= 4 and std.mem.eql(u8, self.args[self.pos], "-l") and eval.isBinaryOp(self.args[self.pos + 2])) {
                var len_buf: [32]u8 = undefined;
                const l_str = std.fmt.bufPrint(&len_buf, "{d}", .{self.args[self.pos + 1].len}) catch return error.Syntax;
                const res = try eval.evalBinary(self.args[self.pos + 2], l_str, self.args[self.pos + 3], self.prog, self.stderr);
                value = res orelse false;
                self.pos += 4;
            } else if (self.args.len - self.pos >= 3 and eval.isBinaryOp(self.args[self.pos + 1])) {
                const res = try eval.evalBinary(self.args[self.pos + 1], self.args[self.pos], self.args[self.pos + 2], self.prog, self.stderr);
                value = res orelse false;
                self.pos += 3;
            } else if (self.args[self.pos].len == 2 and self.args[self.pos][0] == '-') {
                const op = self.args[self.pos];
                if (!eval.isUnaryOp(op)) {
                    self.stderr.print("{s}: '{s}': unary operator expected\n", .{ self.prog, op }) catch {};
                    return error.Handled;
                }
                self.pos += 1;
                if (self.pos >= self.args.len) return self.beyond();
                const arg = self.args[self.pos];
                self.pos += 1;
                value = eval.evalUnary(op, arg) orelse false;
            } else {
                value = self.oneArg();
            }
            return if (negated) !value else value;
        }

        fn andExpr(self: *Self) EvalError!bool {
            var val = try self.term();
            while (self.pos < self.args.len and std.mem.eql(u8, self.args[self.pos], "-a")) {
                self.pos += 1;
                const r = try self.term();
                val = val and r;
            }
            return val;
        }

        fn orExpr(self: *Self) EvalError!bool {
            var val = try self.andExpr();
            while (self.pos < self.args.len and std.mem.eql(u8, self.args[self.pos], "-o")) {
                self.pos += 1;
                const r = try self.andExpr();
                val = val or r;
            }
            return val;
        }

        fn expr(self: *Self) EvalError!bool {
            if (self.pos >= self.args.len) return self.beyond();
            return self.orExpr();
        }

        fn posixTest(self: *Self, nargs: usize) EvalError!bool {
            return switch (nargs) {
                0 => false,
                1 => self.oneArg(),
                2 => try self.twoArgs(),
                3 => try self.threeArgs(),
                4 => if (std.mem.eql(u8, self.args[self.pos], "!")) blk: {
                    self.pos += 1;
                    break :blk !(try self.threeArgs());
                } else if (std.mem.eql(u8, self.args[self.pos], "(") and std.mem.eql(u8, self.args[self.pos + 3], ")")) blk: {
                    self.pos += 1;
                    const v = try self.twoArgs();
                    self.pos += 1;
                    break :blk v;
                } else try self.expr(),
                else => try self.expr(),
            };
        }
    };
}

fn checkHelpVersion(args: []const []const u8, is_bracket: bool, stdout: anytype) bool {
    if (is_bracket and args.len == 2) {
        if (std.mem.eql(u8, args[1], "--help")) {
            stdout.print("Usage: test EXPRESSION\n  or:  test\n  or:  [ EXPRESSION ]\nExit with the status determined by EXPRESSION.\n", .{}) catch {};
            return true;
        }
        if (std.mem.eql(u8, args[1], "--version")) {
            stdout.print("test (coreutilz) {s}\n", .{version}) catch {};
            return true;
        }
    }
    return false;
}

fn parseAndEval(expr_args: []const []const u8, prog: []const u8, stderr: anytype) u8 {
    const P = Parser(@TypeOf(stderr));
    var parser = P{
        .args = expr_args,
        .pos = 0,
        .prog = prog,
        .stderr = stderr,
    };
    const res = parser.posixTest(expr_args.len) catch |err| switch (err) {
        error.Handled => return 2,
        error.Syntax => {
            stderr.print("{s}: syntax error\n", .{prog}) catch {};
            return 2;
        },
    };
    if (parser.pos != expr_args.len) {
        stderr.print("{s}: extra argument '{s}'\n", .{ prog, expr_args[parser.pos] }) catch {};
        return 2;
    }
    return if (res) 0 else 1;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    _ = allocator;
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    const prog = if (args.len > 0) std.fs.path.basename(args[0]) else "test";
    const is_bracket = std.mem.eql(u8, prog, "[");
    if (checkHelpVersion(args, is_bracket, stdout)) {
        stdout.flush() catch return 2;
        return 0;
    }

    var expr_args = if (args.len > 1) args[1..] else &[_][]const u8{};
    if (is_bracket) {
        if (expr_args.len == 0 or !std.mem.eql(u8, expr_args[expr_args.len - 1], "]")) {
            stderr.print("[: missing ']'\n", .{}) catch {};
            stderr.flush() catch {};
            return 2;
        }
        expr_args = expr_args[0 .. expr_args.len - 1];
    }
    if (expr_args.len == 0) return 1;

    const rc = parseAndEval(expr_args, prog, stderr);
    stderr.flush() catch {};
    return rc;
}
