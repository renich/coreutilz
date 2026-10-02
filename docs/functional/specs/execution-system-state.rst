========================================================
Functional Specification: Execution, Process & System State
========================================================

:Domain: Execution, Process & System State
:Target Utilities: ``timeout``, ``nice``, ``nohup``, ``stdbuf``, ``stty``, ``date``, ``chroot``
:Specification ID: ``SPEC-FUNC-EXEC-SYS``

.. contents:: Table of Contents
   :depth: 2
   :backlinks: none

1. Overview
===========

The Execution, Process & System State suite provides POSIX-compliant and GNU Coreutils-compatible utilities for managing child process lifecycles, execution scheduling priorities, terminal line disciplines, signal persistence, buffering control, system date and time queries/formatting, and filesystem root isolation.

2. Functional Requirements: ``timeout``
=======================================

[FUNC-TIMEOUT-001] Command Execution & Time Limit Enforcement
-------------------------------------------------------------
* Run specified ``COMMAND [ARG]...`` and kill it if still running after ``DURATION``.
* **Duration Parsing**:
  - Floating-point or integer duration with optional suffix: ``s`` (seconds, default), ``m`` (minutes), ``h`` (hours), ``d`` (days).
  - Multiple durations or zero duration handling.
* **Signal Controls**:
  - ``-s, --signal=SIGNAL``: Specify signal to send on timeout (default ``SIGTERM``). Accepts signal names (with or without ``SIG`` prefix) and numbers.
  - ``-k, --kill-after=DURATION``: If command is still running after timeout signal sent, send ``SIGKILL`` after secondary duration.
  - ``--preserve-status``: Exit with the child process exit status even if it timed out.
  - ``--foreground``: Do not create a separate process group; run command in foreground.
  - ``-v, --verbose``: Output diagnostic message to stderr when a signal is sent.
* **Exit Status**:
  - Exit code 124 if command times out and ``--preserve-status`` is not set.
  - Exit code 137 (128 + 9) if command timed out and was killed by ``SIGKILL`` via ``--kill-after``.
  - Exit code 125 if ``timeout`` itself encounters an internal error or invalid option.
  - Exit code 126 if command is found but cannot be invoked.
  - Exit code 127 if command cannot be found.
  - Exit code of ``COMMAND`` if it terminates before timeout expires.

3. Functional Requirements: ``nice``
====================================

[FUNC-NICE-001] Scheduling Priority Adjustment
----------------------------------------------
* Run ``COMMAND`` with an adjusted scheduling priority (niceness).
* With no arguments, display the current niceness of the calling process.
* **Adjustment Options**:
  - ``-n, --adjustment=N``: Add integer ``N`` to the current nice value (default 10).
  - Obsolete syntax: ``-N`` or ``+N`` accepted as first argument.
  - Priority ranges typically from -20 (highest) to 19 (lowest). Positive values decrease priority, negative values require privileges (``CAP_SYS_NICE``).
* **Exit Status**:
  - Exit status of ``COMMAND`` upon successful execution.
  - Exit code 126 if command cannot be invoked.
  - Exit code 127 if command cannot be found.
  - Exit code 125 if an invalid adjustment or invocation error occurs.

4. Functional Requirements: ``nohup``
=====================================

[FUNC-NOHUP-001] Immune Process Execution & Redirection
-------------------------------------------------------
* Run ``COMMAND`` with ``SIGHUP`` signal ignored.
* **I/O Redirections**:
  - If standard input is an interactive terminal, redirect stdin from ``/dev/null``.
  - If standard output is an interactive terminal, redirect stdout to append to ``nohup.out`` in the current directory; if that fails (e.g., read-only), redirect to ``$HOME/nohup.out``.
  - If standard error is an interactive terminal, redirect stderr to standard output.
  - Output notice to stderr when stdout/stderr are redirected to file.
* **Exit Status**:
  - Exit status of ``COMMAND``.
  - Exit code 126 if command is found but cannot be invoked.
  - Exit code 127 if command cannot be found.
  - Exit code 125 if nohup encounters an error.

5. Functional Requirements: ``stdbuf``
======================================

[FUNC-STDBUF-001] Stream Buffering Control
------------------------------------------
* Execute ``COMMAND`` with modified standard stream buffering modes.
* **Stream Options**:
  - ``-i, --input=MODE``: Adjust standard input stream buffering.
  - ``-o, --output=MODE``: Adjust standard output stream buffering.
  - ``-e, --error=MODE``: Adjust standard error stream buffering.
  - **Buffering Modes**:
    - ``0``: Unbuffered.
    - ``L``: Line buffered (valid only for output and error).
    - ``SIZE``: Fully buffered with specific buffer size (supports suffixes ``K``, ``M``, ``G``).
* Sets environment variables ``_STDBUF_I``, ``_STDBUF_O``, ``_STDBUF_E`` and ``LD_PRELOAD`` to invoke ``libstdbuf.so`` before execvp.

6. Functional Requirements: ``stty``
====================================

[FUNC-STTY-001] Terminal Line Settings
--------------------------------------
* Print or change terminal line characteristics on standard input or specified device.
* **Device Control**:
  - ``-F, --file=DEVICE``: Open and use specified device instead of standard input.
* **Display Modes**:
  - ``-a, --all``: Print all current terminal settings in human-readable tabular form.
  - ``-g, --save``: Print all current settings in an stty-readable hex string for restoring later.
  - Default (no args): Print speed and deviations from standard terminal settings.
* **Settings Modification**:
  - Special characters: ``erase CHAR``, ``intr CHAR``, ``kill CHAR``, ``eof CHAR``, ``quit CHAR``, ``start CHAR``, ``stop CHAR``, ``susp CHAR``.
  - Special modes: ``sane`` (reset to reasonable defaults), ``raw``, ``-raw``, ``echo``, ``-echo``, ``icanon``, ``-icanon``.
  - Window sizing: ``size`` (print rows and columns), ``rows N``, ``cols N`` / ``columns N``.
  - Baud rate: ``speed``, ``ispeed N``, ``ospeed N``.

7. Functional Requirements: ``date``
====================================

[FUNC-DATE-001] Date & Time Query, Formatting & Setting
-------------------------------------------------------
* Display current date and time in specified format or set system clock.
* **Format Control**:
  - Format string begins with ``+`` followed by conversion specifications (``%Y``, ``%m``, ``%d``, ``%H``, ``%M``, ``%S``, ``%s``, ``%z``, ``%Z``, ``%a``, ``%A``, ``%b``, ``%B``, ``%e``, ``%j``, ``%u``, ``%w``, ``%N``, ``%%``).
  - Default format: ``%a %b %e %H:%M:%S %Z %Y``.
* **Reference & Parsing**:
  - ``-d, --date=STRING``: Parse string and display time (supports ``@SECONDS`` epoch, ISO 8601 ``YYYY-MM-DD HH:MM:SS``, ``now``, ``today``, ``yesterday``, ``tomorrow``).
  - ``-u, --utc, --universal``: Output or set time in UTC / GMT.
  - ``-R, --rfc-email``: Output in RFC 5322 format (e.g. ``Fri, 02 Oct 2026 02:49:34 +0000``).
  - ``--rfc-3339=TIMESPEC``: Output in RFC 3339 format (``date``, ``seconds``, ``ns``).
  - ``-I[TIMESPEC], --iso-8601[=TIMESPEC]``: Output in ISO 8601 format.
  - ``-r, --reference=FILE``: Display the last modification time of ``FILE``.
  - ``-s, --set=STRING``: Set system time to described date (requires privileges).

8. Functional Requirements: ``chroot``
======================================

[FUNC-CHROOT-001] Filesystem Root Isolation
-------------------------------------------
* Run ``COMMAND`` with root directory set to ``NEWROOT``.
* If ``COMMAND`` is not supplied, run ``"${SHELL} -i"`` (or ``/bin/sh -i``).
* **Isolation & Privilege Controls**:
  - ``--userspec=USER:GROUP``: Change UID and GID to specified user and group before running command.
  - ``--groups=G_LIST``: Set supplementary groups as comma-separated list.
  - ``--skip-chdir``: Do not change working directory to ``/`` after chroot.
* **Exit Status**:
  - Exit code 125 if chroot or credential setup fails.
  - Exit code 126 if command found but cannot be invoked.
  - Exit code 127 if command cannot be found.
  - Exit status of ``COMMAND`` otherwise.
