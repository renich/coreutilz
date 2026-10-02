const std = @import("std");

pub fn gcd(a: u512, b: u512) u512 {
    var u = a;
    var v = b;
    while (v != 0) {
        const t = u % v;
        u = v;
        v = t;
    }
    return u;
}

pub fn mulMod(a: u512, b: u512, m: u512) u512 {
    return @intCast((@as(u1024, a) * @as(u1024, b)) % @as(u1024, m));
}

pub fn powerMod(base: u512, exp: u512, m: u512) u512 {
    var res: u512 = 1;
    var b = base % m;
    var e = exp;
    while (e > 0) {
        if (e & 1 != 0) res = mulMod(res, b, m);
        b = mulMod(b, b, m);
        e >>= 1;
    }
    return res;
}

pub fn isPrime(n: u512) bool {
    if (n < 2) return false;
    if (n == 2 or n == 3 or n == 5 or n == 7) return true;
    if (n % 2 == 0 or n % 3 == 0 or n % 5 == 0 or n % 7 == 0) return false;
    var d = n - 1;
    var s: u32 = 0;
    while (d & 1 == 0) {
        d >>= 1;
        s += 1;
    }
    const bases = [_]u512{ 2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71 };
    for (bases) |a| {
        if (n <= a) break;
        var x = powerMod(a, d, n);
        if (x == 1 or x == n - 1) continue;
        var composite = true;
        var r: u32 = 1;
        while (r < s) : (r += 1) {
            x = mulMod(x, x, n);
            if (x == n - 1) {
                composite = false;
                break;
            }
        }
        if (composite) return false;
    }
    return true;
}

pub fn pollardRho(n: u512, seed: *u64) u512 {
    if (n % 2 == 0) return 2;
    if (n % 3 == 0) return 3;
    seed.* = seed.* *% 6364136223846793005 +% 1442695040888963407;
    var x = (@as(u512, seed.*) % (n - 2)) + 2;
    var y = x;
    seed.* = seed.* *% 6364136223846793005 +% 1442695040888963407;
    const c_val = (@as(u512, seed.*) % (n - 1)) + 1;
    var d: u512 = 1;
    var count: usize = 0;
    while (d == 1) {
        count += 1;
        if (count > 200000) return 0;
        x = (mulMod(x, x, n) + c_val) % n;
        y = (mulMod(y, y, n) + c_val) % n;
        y = (mulMod(y, y, n) + c_val) % n;
        const diff = if (x > y) x - y else y - x;
        d = gcd(diff, n);
        if (d == n) return 0;
    }
    return d;
}

fn factorRec(n: u512, factors: *std.ArrayListUnmanaged(u512), alloc: std.mem.Allocator, seed: *u64) !void {
    if (n <= 1) return;
    if (isPrime(n)) {
        try factors.append(alloc, n);
        return;
    }
    var d: u512 = 0;
    while (d == 0) {
        d = pollardRho(n, seed);
    }
    try factorRec(d, factors, alloc, seed);
    try factorRec(n / d, factors, alloc, seed);
}

fn isPrime64(n: u64) bool {
    if (n < 2) return false;
    if (n == 2 or n == 3 or n == 5 or n == 7) return true;
    if (n % 2 == 0 or n % 3 == 0 or n % 5 == 0 or n % 7 == 0) return false;
    var d = n - 1;
    var s: u32 = 0;
    while (d & 1 == 0) {
        d >>= 1;
        s += 1;
    }
    const bases = [_]u64{ 2, 325, 9375, 28178, 450775, 9780504, 1795265022 };
    for (bases) |a| {
        if (n <= a) break;
        var x: u64 = 1;
        var b = a % n;
        var e = d;
        while (e > 0) {
            if (e & 1 != 0) x = @intCast((@as(u128, x) * @as(u128, b)) % @as(u128, n));
            b = @intCast((@as(u128, b) * @as(u128, b)) % @as(u128, n));
            e >>= 1;
        }
        if (x == 1 or x == n - 1) continue;
        var composite = true;
        var r: u32 = 1;
        while (r < s) : (r += 1) {
            x = @intCast((@as(u128, x) * @as(u128, x)) % @as(u128, n));
            if (x == n - 1) {
                composite = false;
                break;
            }
        }
        if (composite) return false;
    }
    return true;
}

fn pollardRho64(n: u64, seed: *u64) u64 {
    if (n % 2 == 0) return 2;
    if (n % 3 == 0) return 3;
    seed.* = seed.* *% 6364136223846793005 +% 1442695040888963407;
    var x = (seed.* % (n - 2)) + 2;
    var y = x;
    seed.* = seed.* *% 6364136223846793005 +% 1442695040888963407;
    const c_val = (seed.* % (n - 1)) + 1;
    var d: u64 = 1;
    var count: usize = 0;
    while (d == 1) {
        count += 1;
        if (count > 200000) return 0;
        x = @intCast((@as(u128, x) * @as(u128, x) + c_val) % n);
        y = @intCast((@as(u128, y) * @as(u128, y) + c_val) % n);
        y = @intCast((@as(u128, y) * @as(u128, y) + c_val) % n);
        const diff = if (x > y) x - y else y - x;
        d = std.math.gcd(diff, n);
        if (d == n) return 0;
    }
    return d;
}

fn factorRec64(n: u64, factors: *std.ArrayListUnmanaged(u512), alloc: std.mem.Allocator, seed: *u64) !void {
    if (n <= 1) return;
    if (isPrime64(n)) {
        try factors.append(alloc, n);
        return;
    }
    var d: u64 = 0;
    while (d == 0) {
        d = pollardRho64(n, seed);
    }
    try factorRec64(d, factors, alloc, seed);
    try factorRec64(n / d, factors, alloc, seed);
}

fn factorNumber64(num: u64, factors: *std.ArrayListUnmanaged(u512), alloc: std.mem.Allocator, seed: *u64) !void {
    var rem = num;
    while (rem % 2 == 0) {
        try factors.append(alloc, 2);
        rem /= 2;
    }
    while (rem % 3 == 0) {
        try factors.append(alloc, 3);
        rem /= 3;
    }
    while (rem % 5 == 0) {
        try factors.append(alloc, 5);
        rem /= 5;
    }
    var p: u64 = 7;
    var step: u64 = 4;
    while (p * p <= rem and p <= 10000) {
        if (rem % p == 0) {
            try factors.append(alloc, p);
            rem /= p;
        } else {
            p += step;
            step = 6 - step;
        }
    }
    if (rem > 1) {
        if (p * p > rem) {
            try factors.append(alloc, rem);
        } else {
            try factorRec64(rem, factors, alloc, seed);
        }
    }
    std.mem.sort(u512, factors.items, {}, std.sort.asc(u512));
}

pub fn factorNumber(num: u512, factors: *std.ArrayListUnmanaged(u512), alloc: std.mem.Allocator, seed: *u64) !void {
    if (num <= 1) return;
    if (num <= std.math.maxInt(u64)) {
        return factorNumber64(@intCast(num), factors, alloc, seed);
    }
    var rem = num;
    while (rem % 2 == 0) {
        try factors.append(alloc, 2);
        rem /= 2;
    }
    while (rem % 3 == 0) {
        try factors.append(alloc, 3);
        rem /= 3;
    }
    while (rem % 5 == 0) {
        try factors.append(alloc, 5);
        rem /= 5;
    }
    var p: u512 = 7;
    var step: u512 = 4;
    while (p <= 1000 and p * p <= rem) {
        if (rem % p == 0) {
            try factors.append(alloc, p);
            rem /= p;
        } else {
            p += step;
            step = 6 - step;
        }
    }
    if (rem > 1) {
        try factorRec(rem, factors, alloc, seed);
    }
    std.mem.sort(u512, factors.items, {}, std.sort.asc(u512));
}
