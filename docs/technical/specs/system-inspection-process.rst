============================================================
Phase 5 Batch J: System Inspection & Process Control Tech Spec
============================================================

:Version: v1.0
:Author: Coreutilz Development Team
:Date: 2026-10-02

Architecture & Implementation
=============================

1. ``src/commands/sum.zig``
---------------------------
- **Algorithm Engine**: Leverages BSD and System V 16-bit summation algorithms from ``src/commands/cksum/sum.zig``.
- **Block Calculation**:
  - BSD: ``blocks = (bytes + 1023) / 1024``
  - SysV: ``blocks = (bytes + 511) / 512``
- **Streaming & Memory**:
  - Fixed 16KB stack I/O buffer per stream; zero unbounded allocations.
  - Formatted streaming output via ``std.Io.File.Writer``.
  - Strict ``stdout.flush() catch return 1;`` flush guarantee.

2. ``src/commands/kill.zig``
----------------------------
- **Signal Resolution Engine**:
  - Translates names: ``HUP``, ``INT``, ``QUIT``, ``KILL``, ``TERM``, etc., with optional ``SIG`` prefix and uppercase/capitalized normalization.
  - Translates numeric codes: Direct signal integers, shell exit statuses (masked with ``0x7f`` or ``0xff`` to match ksh/bash conventions).
  - Handles real-time signals: ``SIGRTMIN`` to ``SIGRTMAX`` and ``RTMIN+N`` / ``RTMAX-N``.
- **Process Signaling**:
  - Direct syscall dispatch via ``std.c.kill(pid, signum)``.
  - Negative PIDs identify process groups.

3. ``src/commands/uptime.zig``
------------------------------
- **Session Accounting**:
  - Inspects glibc/POSIX ``utmpx`` database via ``c.setutxent()`` / ``c.getutxent()`` / ``c.endutxent()``.
  - Filters active user sessions where ``ut_type == c.USER_PROCESS``.
- **Boot Time & Elapsed Duration**:
  - Extracts ``BOOT_TIME`` from ``utmpx``; fallback to ``c.sysinfo(&info)`` when not present.
  - Computes days, hours, and minutes elapsed since boot.
- **Load Averages**:
  - Obtains system 1, 5, and 15-minute load averages via ``c.getloadavg()`` or parsing ``/proc/loadavg``.
