=============================================================
Functional Specification: Storage & Device Primitives
=============================================================

:Domain: Storage & Device Primitives
:Target Utilities: ``mkfifo``, ``mknod``, ``chown``, ``chgrp``, ``df``, ``du``
:Specification ID: ``SPEC-FUNC-STORAGE-DEVICE``

.. contents:: Table of Contents
   :depth: 2
   :backlinks: none

1. Overview
===========

The Storage & Device Primitives suite provides POSIX-compliant and GNU Coreutils-compatible utilities for creating special device nodes and named pipes (FIFOs), modifying file and directory ownership and group attribution across directory hierarchies, and inspecting disk space utilization and filesystem mount statistics.

Each utility conforms to GNU Coreutils behavioral semantics, exit statuses, error formats, and standard option handling (including ``--help`` and ``--version``).

2. Functional Requirements: ``mkfifo``
======================================

[FUNC-MKFIFO-001] Named Pipe Creation & Mode Assignment
-------------------------------------------------------
* The utility MUST accept one or more path operands designating the named pipe (FIFO) nodes to create.
* If zero operands are passed, the utility MUST emit ``mkfifo: missing operand`` to standard error, suggest ``Try 'mkfifo --help' for more information.``, and exit with status 1.
* By default, FIFOs MUST be created with permissions mode ``0666`` (``a=rw``) masked by the current process umask.
* When ``-m MODE`` (``--mode=MODE``) is specified:
  - Permissions MUST be parsed according to POSIX octal or symbolic mode syntax.
  - If ``MODE`` attempts to set bits outside file permission bits (``0777`` / ``S_IRWXUGO``), such as setuid, setgid, or sticky bits, the utility MUST emit ``mkfifo: mode must specify only file permission bits`` and exit with status 1 without creating any files.
  - Upon successful creation with ``-m``, permissions MUST be explicitly updated to ``MODE`` via ``chmod``/``fchmod`` semantics so umask does not restrict the explicitly requested mode.
* When creation fails for any operand, the utility MUST emit ``mkfifo: cannot create fifo '<path>': <error>`` to standard error, set exit status to 1, and continue processing remaining operands.
* *Fulfills Technical Reference*: ``[TECH-MKFIFO-001]``

[FUNC-MKFIFO-002] Security Context Options
------------------------------------------
* Options ``-Z`` and ``--context[=CTX]`` MUST be accepted for SELinux/SMACK security context setting.
* On environments lacking SELinux/SMACK context creation support, specifying a context emits an appropriate non-fatal warning matching GNU behavior.
* *Fulfills Technical Reference*: ``[TECH-MKFIFO-002]``

3. Functional Requirements: ``mknod``
=====================================

[FUNC-MKNOD-001] Operand Validation & Device Types
--------------------------------------------------
* The utility MUST accept: ``mknod [OPTION]... NAME TYPE [MAJOR MINOR]``.
* Operands requirements:
  - When ``TYPE`` is ``b`` (block special file), ``c`` or ``u`` (character special file), exactly 4 operands (``NAME TYPE MAJOR MINOR``) MUST be provided.
  - When ``TYPE`` is ``p`` (FIFO), exactly 2 operands (``NAME TYPE``) MUST be provided.
  - If 0 or 1 operands are given: emit ``mknod: missing operand`` and exit 1.
  - If 2 operands are given but ``TYPE`` is ``b``, ``c``, or ``u``: emit ``mknod: missing operand after '<arg>'``, followed by ``Special files require major and minor device numbers.``, and exit 1.
  - If 4 operands are given but ``TYPE`` is ``p``: emit ``mknod: extra operand '<arg>'``, followed by ``Fifos do not have major and minor device numbers.``, and exit 1.
  - If ``TYPE`` is none of ``b``, ``c``, ``u``, or ``p``: emit ``mknod: invalid device type '<arg>'`` and exit 1.
* *Fulfills Technical Reference*: ``[TECH-MKNOD-001]``

[FUNC-MKNOD-002] Major/Minor Number Resolution & Mode Assignment
----------------------------------------------------------------
* Major and minor numbers MUST be parsed as integers supporting:
  - Hexadecimal when prefixed with ``0x`` or ``0X``.
  - Octal when prefixed with ``0``.
  - Decimal otherwise.
* Invalid or overflowing numbers MUST emit ``mknod: invalid major device number '<arg>'`` or ``mknod: invalid minor device number '<arg>'`` and exit 1.
* Device nodes MUST be created using the system ``mknod`` syscall with the combined device number constructed via ``makedev(major, minor)``.
* Option ``-m MODE`` (``--mode=MODE``) MUST validate file permission bits (rejecting setuid/setgid/sticky bits) identically to ``mkfifo``.
* *Fulfills Technical Reference*: ``[TECH-MKNOD-002]``

4. Functional Requirements: ``chown`` & ``chgrp``
=================================================

[FUNC-CHOWN-001] User and Group Specifier Resolution
----------------------------------------------------
* ``chown`` accepts an owner and/or group specifier formatted as ``[OWNER][:[GROUP]]`` or ``[OWNER][.[GROUP]]``.
  - If ``OWNER`` is given: resolve via system user database (``getpwnam``) or parse as numeric UID if not found.
  - If ``GROUP`` is given: resolve via system group database (``getgrnam``) or parse as numeric GID if not found.
  - If ``OWNER:`` (colon without group) is given: group is implicitly set to the login group of ``OWNER``.
  - If empty specifier ``""`` is given: neither owner nor group is modified, operation succeeds without error.
  - Unknown user or group names MUST emit ``chown: invalid user: '<spec>'`` or ``chown: invalid group: '<spec>'`` and exit 1.
* ``chgrp`` accepts a group specifier formatted as ``GROUP`` (or numeric GID).
* When ``--reference=RFILE`` is specified:
  - The ownership (and/or group) of each operand file MUST be updated to match the owner and group IDs of ``RFILE``.
  - If ``RFILE`` cannot be statted, emit ``chown: failed to get attributes of '<file>': <error>`` and exit 1.
* When ``--from=CURRENT_OWNER:CURRENT_GROUP`` is specified:
  - The utility MUST only apply changes to files whose current UID and/or GID match the filter constraints.
* *Fulfills Technical Reference*: ``[TECH-CHOWN-001]``

[FUNC-CHOWN-002] Symlink Dereferencing & Traversals
---------------------------------------------------
* By default for non-recursive execution, symlink targets are dereferenced unless ``-h`` / ``--no-dereference`` is specified.
* When ``-h`` (``--no-dereference``) is active:
  - Ownership is modified directly on the symbolic link itself via ``lchown``.
* When ``-R`` (``--recursive``) is active:
  - Traversal is controlled via POSIX flags ``-H``, ``-L``, and ``-P`` (default ``-P``: do not traverse symlinks).
  - Combining ``-R`` with ``--dereference`` requires either ``-H`` or ``-L``; otherwise emit ``chown: -R --dereference requires either -H or -L`` and exit 1.
* *Fulfills Technical Reference*: ``[TECH-CHOWN-002]``

[FUNC-CHOWN-003] Safety Failsafe: Preserve Root
-----------------------------------------------
* When ``--preserve-root`` is active (or combined with ``-R``):
  - Attempting to recursively modify ``/`` or any symlink resolving to ``/`` MUST be aborted with:
    ``chown: it is dangerous to operate recursively on '/'`` (or ``'d/slink-to-root' (same as '/')``)
    ``chown: use --no-preserve-root to override this failsafe``
    and exit status 1.
* Option ``--no-preserve-root`` disables this check.
* *Fulfills Technical Reference*: ``[TECH-CHOWN-003]``

[FUNC-CHOWN-004] Diagnostic Verbosity & Error Suppression
---------------------------------------------------------
* ``-c``, ``--changes``: Report only when an actual change in ownership occurs.
* ``-v``, ``--verbose``: Report status for every processed file:
  - ``changed ownership of '<file>' from <old> to <new>``
  - ``ownership of '<file>' retained as <curr>``
  - ``failed to change ownership of '<file>' to <new>``
  - In ``chgrp``, messages substitute "ownership" with "group".
* ``-f``, ``--silent``, ``--quiet``: Suppress error diagnostics for files that cannot be changed.
* *Fulfills Technical Reference*: ``[TECH-CHOWN-004]``

5. Functional Requirements: ``df``
==================================

[FUNC-DF-001] Filesystem Discovery & Selection
----------------------------------------------
* When zero file operands are provided:
  - The utility MUST inspect all mounted filesystems listed in ``/proc/mounts`` (or system mount table).
  - Pseudo/dummy filesystems (e.g. ``proc``, ``sysfs``, ``devpts``, filesystems with 0 total blocks) MUST be excluded by default unless ``-a`` (``--all``) is specified.
* When one or more file operands are provided:
  - The utility MUST locate the mount point and report usage specifically for the filesystem containing each specified operand.
* Option ``-l`` (``--local``): Limit listing to local filesystems (omitting network shares like NFS, CIFS, etc.).
* Option ``-t TYPE`` (``--type=TYPE``): Restrict output to filesystems matching type ``TYPE``.
* Option ``-x TYPE`` (``--exclude-type=TYPE``): Exclude filesystems matching type ``TYPE``.
* If no filesystems match the selection criteria and ``--total`` is requested, emit ``df: no file systems processed`` and exit 1.
* *Fulfills Technical Reference*: ``[TECH-DF-001]``

[FUNC-DF-002] Block Scaling & Human-Readable Units
--------------------------------------------------
* Default block size MUST be 1024 bytes (``1K-blocks``), or 512 bytes if ``POSIXLY_CORRECT`` is set.
* Option ``-k``: Set block size to 1024 bytes (1 KiB).
* Option ``-m``: Set block size to 1,048,576 bytes (1 MiB).
* Option ``-B SIZE`` (``--block-size=SIZE``): Scale sizes by arbitrary integer or unit size (e.g., ``1K``, ``1M``, ``1G``, ``4096``).
* Option ``-h`` (``--human-readable``): Print sizes in powers of 1024 (e.g., ``1K``, ``234M``, ``2G``).
* Option ``-H`` (``--si``): Print sizes in powers of 1000 (e.g., ``1k``, ``234M``, ``2G``).
* *Fulfills Technical Reference*: ``[TECH-DF-002]``

[FUNC-DF-003] Output Formatting & Field Selection
-------------------------------------------------
* **Standard Format**: Columns: ``Filesystem``, ``1K-blocks``, ``Used``, ``Available``, ``Use%``, ``Mounted on``.
* **Type Inclusion (``-T``, ``--print-type``)**: Inserts ``Type`` column immediately after ``Filesystem``.
* **Inodes Mode (``-i``, ``--inodes``)**: Replaces block metrics with ``Inodes``, ``IUsed``, ``IFree``, ``IUse%``.
* **POSIX Portability (``-P``, ``--portability``)**: Formats header as ``Filesystem 1024-blocks Used Available Capacity Mounted on`` on a single line per filesystem.
* **Custom Fields (``--output[=FIELDS]``)**:
  - Field tokens: ``source``, ``fstype``, ``itotal``, ``iused``, ``iavail``, ``ipcent``, ``size``, ``used``, ``avail``, ``pcent``, ``file``, ``target``.
  - Mutually exclusive with ``-i``, ``-P``, and ``-T``.
  - Reject duplicate fields in ``FIELDS`` with ``df: option --output: field '<f>' used more than once``.
  - If ``--output`` is specified without argument, all 12 fields are printed.
* **Grand Total (``--total``)**:
  - Computes and appends an aggregate total line across all processed filesystems.
* *Fulfills Technical Reference*: ``[TECH-DF-003]``

6. Functional Requirements: ``du``
==================================

[FUNC-DU-001] Directory Tree Traversal & Disk Usage Calculation
---------------------------------------------------------------
* The utility MUST traverse each file or directory operand (default ``.``).
* By default, disk usage is calculated based on allocated filesystem blocks (``st_blocks * 512`` bytes), displayed in 1024-byte block units.
* When ``--apparent-size`` is specified: use apparent file length (``st_size``) instead of block allocation.
* When ``-b`` (``--bytes``) is specified: equivalent to ``--apparent-size --block-size=1``.
* Hard Link Deduplication: Files with multiple links (``st_nlink > 1``) MUST be counted only once per traversal unless ``-l`` (``--count-links``) is active.
* Cycle Detection: Hard link cycles or directory mount loops MUST be tracked via ``(st_dev, st_ino)`` sets to prevent infinite traversal.
* *Fulfills Technical Reference*: ``[TECH-DU-001]``

[FUNC-DU-002] Traversal Scope & Output Filtering
------------------------------------------------
* **[FUNC-DU-002a] File Output (``-a``, ``--all``)**: Output usage for all individual files in addition to directories.
* **[FUNC-DU-002b] Summarize Only (``-s``, ``--summarize``)**: Output only the grand total for each command-line operand.
* **[FUNC-DU-002c] Max Depth (``-d N``, ``--max-depth=N``)**: Output usage only for entries at depth $\le N$. (Depth 0 is equivalent to ``-s``).
* **[FUNC-DU-002d] Separate Directories (``-S``, ``--separate-dirs``)**: Do not include subdirectory sizes in a parent directory's total.
* **[FUNC-DU-002e] Grand Total (``-c``, ``--total``)**: Emit a trailing grand total line: ``<size>\ttotal``.
* **[FUNC-DU-002f] One File System (``-x``, ``--one-file-system``)**: Skip directories situated on different filesystem devices (``st_dev != root_st_dev``).
* **[FUNC-DU-002g] Size Threshold (``-t SIZE``, ``--threshold=SIZE``)**: Exclude entries smaller than ``SIZE`` if positive, or greater than ``SIZE`` if negative.
* **[FUNC-DU-002h] Exclusions (``--exclude=PATTERN``, ``-X FILE``)**: Omit paths matching wildcard glob patterns.
* **[FUNC-DU-002i] Null Termination (``-0``, ``--null``)**: Terminate output lines with NUL byte instead of newline.
* **[FUNC-DU-002j] File List Ingestion (``--files0-from=FILE``)**: Read NUL-terminated operands from ``FILE`` (or standard input if ``-``).
* *Fulfills Technical Reference*: ``[TECH-DU-002]``
