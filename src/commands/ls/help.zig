const std = @import("std");

fn printUsage(writer: anytype, prog_name: []const u8) !void {
    try writer.print(
        \\Usage: {s} [OPTION]... [FILE]...
        \\List information about the FILEs (the current directory by default).
        \\Sort entries alphabetically if none of -cftuvSUX nor --sort is specified.
        \\
        \\Mandatory arguments to long options are mandatory for short options too.
        \\
    , .{prog_name});
}

fn printPrimaryOptions(writer: anytype) !void {
    try writer.writeAll(
        \\  -a, --all                  do not ignore entries starting with .
        \\  -A, --almost-all           do not list implied . and ..
        \\  -B, --ignore-backups       do not list implied entries ending with ~
        \\  -c                         with -lt: sort by, and show, ctime
        \\  -C                         list entries by columns
        \\  -d, --directory            list directories themselves, not their contents
        \\  -D, --dired                generate output designed for Emacs' dired mode
        \\  -F, --classify             append indicator (one of */=>@|) to entries
        \\      --file-type            likewise, except do not append '*'
        \\      --full-time            like -l --time-style=full-iso
        \\  -g                         like -l, but do not list owner
        \\      --group-directories-first
        \\                             group directories before files
        \\  -h, --human-readable       with -l and -s, print sizes like 1K 234M 2G etc.
        \\  -H, --dereference-command-line
        \\                             follow symbolic links listed on the command line
        \\  -i, --inode                print the index number of each file
        \\  -k, --kibibytes            default to 1024-byte blocks for disk usage
        \\  -l                         use a long listing format
        \\  -L, --dereference          when showing file information for a symbolic
        \\                             link, show info for the file the link references
        \\  -m                         fill width with a comma separated list of entries
        \\  -n, --numeric-uid-gid      like -l, but list numeric user and group IDs
        \\  -o                         like -l, but do not list group information
        \\  -p                         append / indicator to directories
        \\
    );
}

fn printSecondaryOptions(writer: anytype) !void {
    try writer.writeAll(
        \\  -q, --hide-control-chars   print ? instead of nongraphic characters
        \\  -Q, --quote-name           enclose entry names in double quotes
        \\      --quoting-style=WORD   use quoting style WORD for entry names
        \\  -r, --reverse              reverse order while sorting
        \\  -R, --recursive            list subdirectories recursively
        \\  -s, --size                 print the allocated size of each file, in blocks
        \\  -S                         sort by file size, largest first
        \\      --sort=WORD            sort by WORD instead of name: none (-U), size (-S),
        \\                             time (-t), version (-v), extension (-X), width
        \\      --time-style=TIME_STYLE
        \\                             time/date format with -l
        \\  -t                         sort by time, newest first; see --time
        \\  -T, --tabsize=COLS         assume tab stops at each COLS instead of 8
        \\  -u                         with -lt: sort by, and show, access time
        \\  -U                         do not sort; list entries in directory order
        \\  -v                         natural sort of (version) numbers within text
        \\  -w, --width=COLS           set output width to COLS.  0 means no limit
        \\  -x                         list entries by lines instead of by columns
        \\  -X                         sort alphabetically by entry extension
        \\  -1                         list one file per line
        \\  -z, --zero                 end each output line with NUL, not newline
        \\      --help     display this help and exit
        \\      --version  output version information and exit
        \\
        \\GNU coreutils online help: <https://www.gnu.org/software/coreutils/>
        \\
    );
}

pub fn printHelp(writer: anytype, prog_name: []const u8) !void {
    try printUsage(writer, prog_name);
    try printPrimaryOptions(writer);
    try printSecondaryOptions(writer);
}
