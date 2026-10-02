=============================================================
Phase 5 Batch J: System Inspection & Process Control Func Spec
=============================================================

:Version: v1.0
:Author: Coreutilz Development Team
:Date: 2026-10-02

Overview
========

Phase 5 Batch J delivers the final tier of system inspection, checksum calculation, and process control utilities: ``sum``, ``kill``, and ``uptime``, achieving 100% behavioral and flag parity with GNU Coreutils.

Utilities
=========

1. ``sum`` - Checksum and Block Counter
---------------------------------------
Calculates 16-bit checksums and block counts for files or standard input.

- **Options**:
  - ``-r``: Use BSD 16-bit checksum algorithm with 1K (1024-byte) blocks (default).
  - ``-s``, ``--sysv``: Use System V 16-bit checksum algorithm with 512-byte blocks.
  - ``--help``: Display help and exit.
  - ``--version``: Display version and exit.
- **Output Formats**:
  - BSD format (file operand): ``%05d %5d %s\n`` (checksum, 1K blocks, filename).
  - BSD format (stdin operand): ``%05d %5d\n`` (checksum, 1K blocks).
  - System V format (file operand): ``%d %d %s\n`` (checksum, 512-byte blocks, filename).
  - System V format (stdin operand): ``%d %d\n`` (checksum, 512-byte blocks).
- **Exit Status**:
  - 0: All files processed successfully.
  - 1: An I/O error occurred on at least one input file or standard output.

2. ``kill`` - Process Signaling & Signal Table
---------------------------------------------
Sends signals to processes or process groups, lists available signals, or converts signal names and numbers.

- **Options**:
  - ``-s SIGNAL``, ``--signal=SIGNAL``, ``-SIGNAL``, ``-n SIGNAL``: Signal to send (name or number).
  - ``-l``, ``--list``: List all signals or convert signal name/number operands.
  - ``-t``, ``--table``, ``-L``: Display signal information table (number, name, description).
  - ``--help``, ``--version``: Diagnostics and version.
- **Operand Formats**:
  - PID: Positive integer for process ID, 0 for current process group, negative integer for process group.
  - Signal operands for ``-l``/``-t``: Signal numbers (including shell exit statuses ``128 + sig`` and ``256 + sig``) and signal names (with or without ``SIG`` prefix, uppercase or capitalized).
- **Exit Status**:
  - 0: All signals sent or listed successfully.
  - 1: Invalid option, invalid signal, or failure to signal process.

3. ``uptime`` - System Uptime & Load Averages
---------------------------------------------
Reports the current time, how long the system has been running, how many users are currently logged on, and the system load averages.

- **Options**:
  - ``-s``, ``--since``: Display the date and time since when the system has been up (``YYYY-MM-DD HH:MM:SS``).
  - ``--help``: Display help.
  - ``--version``: Display version.
- **Output Format**:
  - Standard: `` %H:%M:%S  up [X days, ]HH:MM,  N users,  load average: L1, L2, L3\n``.
- **Exit Status**:
  - 0: Success.
  - 1: Failure to read boot time, sessions, or load averages.
