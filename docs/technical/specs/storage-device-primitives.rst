==========================================================
Technical Blueprint: Storage & Device Primitives
==========================================================

:Domain: Storage & Device Primitives
:Target Utilities: ``mkfifo``, ``mknod``, ``chown``, ``chgrp``, ``df``, ``du``
:Specification ID: ``SPEC-TECH-STORAGE-DEVICE``
:Functional Reference: ``SPEC-FUNC-STORAGE-DEVICE``

.. contents:: Table of Contents
   :depth: 2
   :backlinks: none

1. Architectural Overview
=========================

The Storage & Device Primitives suite implements low-level POSIX and Linux system operations governing filesystem object creation, ownership management, and capacity inspection.

Engineering constraints strictly adhered to:
* Every source file MUST not exceed 300 lines ceiling.
* Every function MUST not exceed 40 lines of core logic.
* Branch nesting depth MUST not exceed 3 levels.
* Command execution MUST follow the standard Coreutilz entrypoint runner contract (``runner.runWrapper``).
* Memory management MUST be leak-free, validated under ``std.testing.allocator``.

2. Technical Architecture: ``mkfifo`` & ``mknod``
=================================================

Module Decomposition
--------------------
* ``src/commands/mkfifo.zig``: CLI runner, mode validation, FIFO creation.
* ``src/commands/mknod.zig``: CLI runner, device type dispatch, major/minor parsing, special file creation.

[TECH-MKFIFO-001] FIFO Creation & Mode Enforcement
--------------------------------------------------
* *Fulfills*: ``[FUNC-MKFIFO-001]``
* Named pipe creation is performed via POSIX ``mkfifo(path, mode)``.
* Mode string parsing leverages ``src/utils/mode.zig``.
* The parsed mode is verified to ensure only file permission bits (``0777``) are set; presence of setuid/setgid/sticky bits immediately triggers an error prior to creation.
* If a mode was explicitly requested via ``-m``, post-creation permission is updated with ``chmod``/``fchmod`` to override default umask restrictions.

[TECH-MKNOD-001] Device Number Parsing & Node Creation
------------------------------------------------------
* *Fulfills*: ``[FUNC-MKNOD-001]``, ``[FUNC-MKNOD-002]``
* Major and minor numbers are parsed with base detection (``0x`` hex, ``0`` octal, decimal).
* Device number is constructed using Linux ``makedev(major, minor)``:
  ``((major & 0xfff) << 8) | ((major & ~0xfff) << 32) | (minor & 0xff) | ((minor & ~0xff) << 12)``.
* Block nodes (``b``) use ``S_IFBLK``, character nodes (``c``, ``u``) use ``S_IFCHR``, and FIFOs (``p``) use ``S_IFIFO``.
* Syscall ``mknod(path, mode | type, dev)`` creates the special node.

3. Technical Architecture: ``chown`` & ``chgrp``
================================================

Module Decomposition
--------------------
* ``src/commands/chown.zig``: CLI runner, spec parsing, operand dispatch for chown.
* ``src/commands/chgrp.zig``: CLI runner for chgrp (delegates to common ownership engine).
* ``src/commands/chown/common.zig``: Shared ownership options, user/group lookup, recursion engine.
* ``src/commands/chown/spec.zig``: User and group specifier parsing (``user:group``, ``user.group``).

[TECH-CHOWN-001] Specifier Resolution
-------------------------------------
* *Fulfills*: ``[FUNC-CHOWN-001]``
* ``spec.zig`` parses strings of the form ``[USER][:[GROUP]]`` and ``[USER][.[GROUP]]``.
* Looks up username via ``getpwnam_r`` (or ``getpwnam``) and group via ``getgrnam_r`` (or ``getgrnam``), falling back to integer IDs.
* When ``USER:`` is provided, the primary GID from ``passwd.pw_gid`` is automatically resolved.

[TECH-CHOWN-002] Traversal, Dereferencing & Failsafes
----------------------------------------------------
* *Fulfills*: ``[FUNC-CHOWN-002]``, ``[FUNC-CHOWN-003]``, ``[FUNC-CHOWN-004]``
* Non-recursive mode uses ``chown`` or ``lchown`` depending on ``-h`` (``--no-dereference``).
* Recursive mode walks directory hierarchies with cycle detection using an arena-backed hash set of ``(dev, ino)``.
* ``--preserve-root`` validates against root inode (``/``) and symlinks targeting ``/``, aborting with fatal diagnostics before any mutation occurs.

4. Technical Architecture: ``df``
=================================

Module Decomposition
--------------------
* ``src/commands/df.zig``: CLI runner, mount table ingestion, filtering, column calculation, table formatting.
* ``src/commands/df/mounts.zig``: Mount point discovery, reading ``/proc/mounts``, resolving target mount entries.
* ``src/commands/df/format.zig``: Column width calculation, field extraction (standard, POSIX, inodes, custom).

[TECH-DF-001] Mount Point & Filesystem Discovery
------------------------------------------------
* *Fulfills*: ``[FUNC-DF-001]``
* Reads mount table via ``setmntent``/``getmntent_r`` on ``/proc/mounts``.
* For each mount, queries filesystem statistics via ``statvfs``.
* Filters pseudo filesystems (dummy mounts with 0 blocks) unless ``-a`` is provided.
* For specific file operands, matches the longest mount point prefix or matches device IDs (``st_dev``).

[TECH-DF-002] Metrics Calculation & Unit Scaling
------------------------------------------------
* *Fulfills*: ``[FUNC-DF-002]``, ``[FUNC-DF-003]``
* Used space: ``total_blocks - free_blocks_for_root``.
* Available space: ``available_blocks_for_unprivileged``.
* Percentage calculation: ``used * 100 / (used + available) + ceiling_adjustment``.
* Block scaling supports power-of-two (``-h``) and power-of-ten (``-H``) units, as well as arbitrary block sizes (``-B``).

5. Technical Architecture: ``du``
=================================

Module Decomposition
--------------------
* ``src/commands/du.zig``: CLI runner, operand dispatch, total reporting.
* ``src/commands/du/options.zig``: CLI argument parser, thresholds, glob exclusion compilation.
* ``src/commands/du/traverse.zig``: Recursive traversal engine, hard link deduplication, cycle detection.

[TECH-DU-001] Disk Usage Traversal & Deduplication
--------------------------------------------------
* *Fulfills*: ``[FUNC-DU-001]``, ``[FUNC-DU-002]``
* Uses depth-first recursive walk.
* Normal usage measures allocated blocks: ``st_blocks * 512`` bytes. Apparent size measures ``st_size``.
* Hard links are tracked via hash map ``std.AutoHashMap(struct { dev: u64, ino: u64 }, void)``; multi-link files are counted only once unless ``-l`` is set.
* Respects ``--max-depth``, ``--separate-dirs``, ``--one-file-system``, and wildcard glob exclusions.
