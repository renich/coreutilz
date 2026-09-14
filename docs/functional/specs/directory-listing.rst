============================================
Functional Specification: Directory Listing
============================================

:Domain: File System Inspection
:Target Utilities: ``ls``, ``dir``, ``vdir``
:Specification ID: ``SPEC-FUNC-LS``

.. contents:: Table of Contents
   :depth: 2
   :backlinks: none

1. Overview
===========

The Directory Listing suite (``ls``, ``dir``, ``vdir``) provides deterministic inspection, filtering, sorting, and formatting of file system directory contents and individual file operands. The three commands share an identical core inspection engine with distinct default formatting behaviors:

* ``ls``: Multi-column formatted output when stdout is connected to a terminal; single-column newline-delimited output when piped or redirected.
* ``dir``: Multi-column formatted output (equivalent to ``ls -C -b``) by default, regardless of stdout redirection.
* ``vdir``: Long detailed listing format (equivalent to ``ls -l -b``) by default, regardless of stdout redirection.

2. Functional Requirements
==========================

[FUNC-LS-001] Operand Ingestion & Default Target
------------------------------------------------
* If zero operands are passed on the command line, the utility MUST target the current working directory (``.``).
* If one or more operands are passed, the utility MUST process all specified paths in command-line argument order.
* File operands MUST be displayed before directory contents when sorting groups, matching standard GNU Coreutils ordering.

[FUNC-LS-002] Entry Filtering & Hidden Files
--------------------------------------------
* **Default**: The utility MUST omit any directory entry whose name begins with a period (``.``).
* **[FUNC-LS-002a] All Entries (``-a``, ``--all``)**: The utility MUST list all directory entries, explicitly including ``.`` and ``..``.
* **[FUNC-LS-002b] Almost All Entries (``-A``, ``--almost-all``)**: The utility MUST list all entries beginning with ``.``, but MUST omit the literal directory entries ``.`` and ``..``.
* **[FUNC-LS-002c] Directory Self-Listing (``-d``, ``--directory``)**: When an operand is a directory, the utility MUST list the directory name itself rather than inspecting its contents.

[FUNC-LS-003] Detailed Long Listing (``-l``)
--------------------------------------------
Under the long listing mode, every entry MUST be formatted across the following mandatory columns:

1. **File Type and Permissions**: A 10-character string formatted via POSIX standard permissions:
   * First character denotes type: ``-`` (regular file), ``d`` (directory), ``l`` (symbolic link), ``c`` (character device), ``b`` (block device), ``p`` (FIFO pipe), ``s`` (UNIX domain socket).
   * Characters 2-10 represent owner, group, and other read/write/execute/setuid/setgid/sticky bits.
2. **Hard Link Count**: Decimal count of hard links pointing to the inode.
3. **Owner Username**: The resolved username corresponding to the file UID. If ``-n`` (``--numeric-uid-gid``) is specified or UID resolution fails, the numeric UID MUST be displayed. If ``-g`` is specified, owner username MUST be omitted.
4. **Group Name**: The resolved group name corresponding to the file GID. If ``-n`` (``--numeric-uid-gid``) is specified or GID resolution fails, the numeric GID MUST be displayed. If ``-o`` is specified, group name MUST be omitted.
5. **File Size**: Size in bytes by default. If ``-h`` (``--human-readable``) is specified, sizes MUST be scaled using binary power prefixes (e.g., ``1K``, ``234M``, ``2G``).
6. **Modification Timestamp**: Formatted using the standard GNU abbreviated month and day with timestamp (``b d HH:MM`` for recent dates within 6 months, or ``b d  Y`` for older dates). If ``--full-time`` is specified, output ISO 8601 full timestamp with nanoseconds.
7. **File Name**: Entry name. For symbolic links, the entry MUST append `` -> <target>`` displaying the dereferenced link target.

[FUNC-LS-004] Output Layout & Formatting Modes
----------------------------------------------
* **[FUNC-LS-004a] Single Column (``-1``)**: Entries MUST be separated by a single newline character (``\n``).
* **[FUNC-LS-004b] Multi-Column Down Columns (``-C``)**: Entries MUST be arranged in vertically aligned columns calculated from terminal width (default 80 columns).
* **[FUNC-LS-004c] Multi-Column Across Rows (``-x``)**: Entries MUST be arranged in horizontally sorted rows across columns.
* **[FUNC-LS-004d] Comma-Separated Stream (``-m``)**: Entries MUST be formatted as a comma-separated list wrapping across lines within terminal width.
* **[FUNC-LS-004e] Quoted Names (``-Q``, ``--quote-name``)**: Entry names MUST be enclosed in double quotes (``"name"``).

[FUNC-LS-005] Sorting Disciplines
---------------------------------
* **Default**: Entries MUST be sorted alphabetically by filename using byte collation order.
* **[FUNC-LS-005a] Time Sort (``-t``)**: Entries MUST be sorted by modification time, newest entries first.
* **[FUNC-LS-005b] Size Sort (``-S``)**: Entries MUST be sorted by file size, largest entries first.
* **[FUNC-LS-005c] Extension Sort (``-X``)**: Entries MUST be sorted alphabetically by file extension.
* **[FUNC-LS-005d] Natural Version Sort (``-v``)**: Entries containing numeric version segments MUST be sorted naturally (e.g., ``v1.2`` before ``v1.10``).
* **[FUNC-LS-005e] Reverse Sort (``-r``, ``--reverse``)**: The selected sorting order MUST be inverted.
* **[FUNC-LS-005f] Unsorted Directory Order (``-U``)**: Entries MUST be output in the raw order returned by the file system without sorting.

[FUNC-LS-006] Recursive Traversal (``-R``, ``--recursive``)
-----------------------------------------------------------
* When ``-R`` is specified, subdirectories encountered MUST be recursively traversed and listed.
* Each subdirectory listing MUST be preceded by an empty line and the directory header: ``<path>:``.

[FUNC-LS-007] File Metadata Indicators
---------------------------------------
* **[FUNC-LS-007a] Inode Numbers (``-i``, ``--inode``)**: The file inode number MUST be printed before each file entry.
* **[FUNC-LS-007b] Block Allocation Size (``-s``, ``--size``)**: The allocated disk block count (in 1024-byte blocks) MUST be printed before each file entry.
* **[FUNC-LS-007c] Classification Characters (``-F``, ``--classify``)**: Append type indicators to filenames:
  * Directories: ``/``
  * Executable files: ``*``
  * Symbolic links: ``@``
  * FIFO pipes: ``|``
  * Sockets: ``=``
* **[FUNC-LS-007d] Slash Directory Indicator (``-p``)**: Append ``/`` exclusively to directory entries.

[FUNC-LS-008] Exit Codes & Diagnostic Semantics
-----------------------------------------------
* **Exit 0**: All files and directories were inspected and listed successfully.
* **Exit 1**: Minor errors occurred (e.g., access was denied to a subdirectory during traversal, but other targets succeeded).
* **Exit 2**: Serious trouble occurred (e.g., invalid CLI option specified, or an explicit command-line operand was non-existent).
* Diagnostic error messages MUST be written to standard error in the exact GNU format:
  ``ls: cannot access '<path>': <strerror>``.
