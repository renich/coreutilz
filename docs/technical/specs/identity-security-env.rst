===========================================================
Technical Specification: Identity, Security & Environment
===========================================================

:Domain: Identity, Security & Environment
:Target Utilities: ``id``, ``groups``, ``who``, ``users``, ``pinky``, ``uname``, ``arch``, ``chcon``, ``runcon``
:Specification ID: ``SPEC-TECH-ID-SEC-ENV``

.. contents:: Table of Contents
   :depth: 2
   :backlinks: none

1. Architecture & Design Principles
===================================

The Identity, Security & Environment module interfaces directly with Linux kernel identity primitives, the POSIX user/group database, session accounting databases (utmp/utmpx), and Linux Security Modules (SELinux context manipulation).

All utilities strictly enforce:
* Explicit memory allocations without leaks.
* Modularity: files capped at $\le 300$ lines, functions capped at $\le 40$ lines.
* Safe streaming writes through `std.Io.File.Writer` with robust flush error handling on `/dev/full`.

2. System API Bindings
======================

2.1 User & Group Identification (``id``, ``groups``)
----------------------------------------------------
* Uses standard glibc/POSIX functions from ``<unistd.h>``, ``<pwd.h>``, and ``<grp.h>``:
  - ``c.getuid()``, ``c.geteuid()``: Real and effective user IDs.
  - ``c.getgid()``, ``c.getegid()``: Real and effective group IDs.
  - ``c.getgroups(size, list)``: Supplementary group IDs.
  - ``c.getgrouplist(user, group, groups, &ngroups)``: Fetch all group memberships for a designated user.
  - ``c.getpwuid(uid)``, ``c.getpwnam(name)``: User name resolution.
  - ``c.getgrgid(gid)``, ``c.getgrnam(name)``: Group name resolution.
* SELinux context reading:
  - Resolves process context from ``/proc/self/attr/current`` or ``/proc/thread-self/attr/current``.

2.2 Session Accounting (``who``, ``users``, ``pinky``)
------------------------------------------------------
* Uses POSIX/XSI utmpx interfaces from ``<utmpx.h>``:
  - ``c.setutxent()``: Rewind utmpx file.
  - ``c.getutxent()``: Iterate session records.
  - ``c.endutxent()``: Close utmpx file.
* Types handled:
  - ``c.USER_PROCESS``: Active user login sessions.
  - ``c.BOOT_TIME``: System boot timestamp.
  - ``c.INIT_PROCESS``: Init-spawned processes.
  - ``c.DEAD_PROCESS``: Terminated session records.
  - ``c.RUN_LVL``: System runlevel records.
* TTY message permission inspection:
  - Uses ``c.stat(tty_path, &st)`` on `/dev/<ut_line>` to check write permission (`S_IWGRP` / `S_IWOTH`).

2.3 System & Architecture Queries (``uname``, ``arch``)
-------------------------------------------------------
* Uses ``c.uname(&uts)`` from ``<sys/utsname.h>``:
  - ``uts.sysname``: Kernel name (``Linux``).
  - ``uts.nodename``: Network node hostname.
  - ``uts.release``: Kernel release version.
  - ``uts.version``: Kernel build version and timestamp.
  - ``uts.machine``: Hardware machine architecture (``x86_64``, ``aarch64``, etc.).
* Standard GNU field ordering for ``uname -a``:
  - Kernel name, nodename, release, version, machine, processor, hardware platform, operating system.

2.4 SELinux Security Context Manipulation (``chcon``, ``runcon``)
-----------------------------------------------------------------
* Reading / writing security contexts:
  - Extended attribute interface: `c.getxattr`, `c.lgetxattr`, `c.setxattr`, `c.lsetxattr` with attribute name `security.selinux`.
  - Process execution context: `/proc/self/attr/exec` via file write before child invocation or `c.setexeccon`.
* Hierarchy recursion:
  - Traversal with loop detection and root protection (``--preserve-root``).
* Error reporting:
  - In SELinux-disabled environments, emits standard GNU diagnostic and exits with error code 1 (or 125 for `runcon`).
