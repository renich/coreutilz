const std = @import("std");

const help_text =
    \\Usage: du [OPTION]... [FILE]...
    \\  or:  du [OPTION]... --files0-from=F
    \\Summarize device usage of the set of FILEs, recursively for directories.
    \\
    \\Mandatory arguments to long options are mandatory for short options too.
    \\  -0, --null            end each output line with 0 byte rather than newline
    \\  -a, --all             write counts for all files, not just directories
    \\      --apparent-size   print apparent sizes rather than device usage
    \\  -B, --block-size=SIZE  scale sizes by SIZE before printing them
    \\  -b, --bytes           equivalent to '--apparent-size --block-size=1'
    \\  -c, --total           produce a grand total
    \\  -D, --dereference-args  dereference only symlinks that are listed on the command line
    \\  -d, --max-depth=N     print the total for a directory only if it is N or fewer
    \\                          levels below the command line argument
    \\      --files0-from=F   summarize device usage of the NUL-terminated file names
    \\                          specified in file F; if F is -, then read names from stdin
    \\  -H                    equivalent to --dereference-args (-D)
    \\  -h, --human-readable  print sizes in human readable format (e.g., 1K 234M 2G)
    \\      --inodes          list inode usage information instead of block usage
    \\  -k                    like --block-size=1K
    \\  -L, --dereference     dereference all symbolic links
    \\  -l, --count-links     count sizes many times if hard linked
    \\  -m                    like --block-size=1M
    \\  -P, --no-dereference  don't follow any symbolic links (this is the default)
    \\  -S, --separate-dirs   for directories do not include size of subdirectories
    \\      --si              like -h, but use powers of 1000 not 1024
    \\  -s, --summarize       display only a total for each argument
    \\  -t, --threshold=SIZE  exclude entries smaller than SIZE if positive,
    \\                          or greater than SIZE if negative
    \\      --time            show time of the last modification of any file
    \\      --time=WORD       show time as WORD: atime, access, use, ctime, status
    \\      --time-style=STYLE  show times using STYLE: full-iso, long-iso, iso
    \\  -X, --exclude-from=FILE  exclude files that match any pattern in FILE
    \\      --exclude=PATTERN exclude files that match PATTERN
    \\  -x, --one-file-system    skip directories on different file systems
    \\      --help            display this help and exit
    \\      --version         output version information and exit
    \\
;

const version_text =
    \\du (coreutilz) 0.1.0
    \\Copyright (C) 2026 Free Software Foundation, Inc.
    \\License GPLv3+: GNU GPL version 3 or later <https://gnu.org/licenses/gpl.html>.
    \\This is free software: you are free to change and redistribute it.
    \\There is NO WARRANTY, to the extent permitted by law.
    \\
;

pub fn printHelp(stdout: anytype) !void {
    try stdout.writeAll(help_text);
}

pub fn printVersion(stdout: anytype) !void {
    try stdout.writeAll(version_text);
}
