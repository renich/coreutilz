const std = @import("std");

pub const c = @cImport({
    @cDefine("_GNU_SOURCE", "1");
    @cInclude("ctype.h");
    @cInclude("dirent.h");
    @cInclude("errno.h");
    @cInclude("fcntl.h");
    @cInclude("fnmatch.h");
    @cInclude("getopt.h");
    @cInclude("grp.h");
    @cInclude("locale.h");
    @cInclude("poll.h");
    @cInclude("pwd.h");
    @cInclude("signal.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("sys/ioctl.h");
    @cInclude("sys/stat.h");
    @cInclude("sys/statvfs.h");
    @cInclude("sys/sysmacros.h");
    @cInclude("sys/types.h");
    @cInclude("time.h");
    @cInclude("unistd.h");
    @cInclude("wchar.h");
    @cInclude("wctype.h");
});
