pub fn printChgrpHelp(stdout: anytype) !void {
    try stdout.print(
        \\Usage: chgrp [OPTION]... GROUP FILE...
        \\  or:  chgrp [OPTION]... --reference=RFILE FILE...
        \\Change the group of each FILE to GROUP.
        \\With --reference, change the group of each FILE to that of RFILE.
        \\
        \\  -c, --changes          like verbose but report only when a change is made
        \\  -f, --silent, --quiet  suppress most error messages
        \\  -v, --verbose          output a diagnostic for every file processed
        \\      --dereference      affect the referent of each symbolic link (default)
        \\  -h, --no-dereference   affect symbolic links instead of any referenced file
        \\      --preserve-root    fail to operate recursively on '/'
        \\      --no-preserve-root do not treat '/' specially (the default)
        \\      --reference=RFILE  use RFILE's group rather than specifying a GROUP value
        \\  -R, --recursive        operate on files and directories recursively
        \\  -H                     if a command-line argument is a symbolic link to a
        \\                           directory, traverse it
        \\  -L                     traverse every symbolic link to a directory encountered
        \\  -P                     do not traverse any symbolic links (default)
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
    , .{});
}

pub fn printChownHelp(stdout: anytype) !void {
    try stdout.print(
        \\Usage: chown [OPTION]... [OWNER][:[GROUP]] FILE...
        \\  or:  chown [OPTION]... --reference=RFILE FILE...
        \\Change the owner and/or group of each FILE to OWNER and/or GROUP.
        \\With --reference, change the owner and group of each FILE to those of RFILE.
        \\
        \\  -c, --changes          like verbose but report only when a change is made
        \\  -f, --silent, --quiet  suppress most error messages
        \\  -v, --verbose          output a diagnostic for every file processed
        \\      --dereference      affect the referent of each symbolic link (default)
        \\  -h, --no-dereference   affect symbolic links instead of any referenced file
        \\      --preserve-root    fail to operate recursively on '/'
        \\      --no-preserve-root do not treat '/' specially (the default)
        \\      --reference=RFILE  use RFILE's owner and group rather than specifying
        \\                           OWNER:GROUP values
        \\  -R, --recursive        operate on files and directories recursively
        \\  -H                     if a command-line argument is a symbolic link to a
        \\                           directory, traverse it
        \\  -L                     traverse every symbolic link to a directory encountered
        \\  -P                     do not traverse any symbolic links (default)
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
    , .{});
}
