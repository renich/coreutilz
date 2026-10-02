======================================================
Technical Specification: Execution, Process & System State
======================================================

:Domain: Execution, Process & System State
:Target Utilities: ``timeout``, ``nice``, ``nohup``, ``stdbuf``, ``stty``, ``date``, ``chroot``
:Specification ID: ``SPEC-TECH-EXEC-SYS``

.. contents:: Table of Contents
   :depth: 2
   :backlinks: none

1. Architecture & Memory Management
===================================

Every utility in the Execution, Process & System State suite leverages POSIX and Linux kernel syscalls via libc bindings (``c.fork``, ``c.execvp``, ``c.waitpid``, ``c.kill``, ``c.setpriority``, ``c.getpriority``, ``c.tcgetattr``, ``c.tcsetattr``, ``c.ioctl``, ``c.clock_gettime``, ``c.clock_settime``, ``c.chroot``, ``c.chdir``, ``c.setgroups``, ``c.setgid``, ``c.setuid``).

* **Memory Safety & Leaks**: Explicit allocators (``std.mem.Allocator``) manage all heap allocations; every allocation is freed prior to command execution or process exit.
* **Process Lifecycle**: Subprocess fork/exec loops properly handle signal inheritance, process group separation, and zombie process reaping (``waitpid``).
* **Line Ceiling & Modularity**: Source files strictly conform to the 300 lines per file ceiling and 40 lines per function.

2. Module Decomposition
=======================

[TECH-TIMEOUT-001] Subprocess Watchdog Engine
---------------------------------------------
* Implemented in ``src/commands/timeout.zig``.
* Subprocess spawned via ``c.fork()`` / ``c.execvp()``.
* Parent process establishes timer or alarm via ``timer_create`` / ``c.nanosleep`` / signal polling, forwarding signals (``SIGINT``, ``SIGTERM``, ``SIGHUP``, ``SIGQUIT``) to the child process group unless ``--foreground``.
* Tracks exit status using ``c.waitpid()`` with ``WIFEXITED`` and ``WIFSIGNALED`` macro equivalents.
* Emits diagnostic message on stderr if ``-v, --verbose`` is requested.

[TECH-NICE-001] Scheduling Priority Dispatcher
----------------------------------------------
* Implemented in ``src/commands/nice.zig``.
* Queries existing priority using ``c.getpriority(c.PRIO_PROCESS, 0)``.
* Applies requested nice adjustment with ``c.setpriority(c.PRIO_PROCESS, 0, new_prio)``.
* Invokes target command via ``c.execvp()``.

[TECH-NOHUP-001] Hangup Shield & Stream Redirection
---------------------------------------------------
* Implemented in ``src/commands/nohup.zig``.
* Sets ``c.signal(c.SIGHUP, c.SIG_IGN)``.
* Checks if standard file descriptors are TTYs using ``c.isatty()``.
* Reopens stdin from ``/dev/null`` and stdout/stderr to ``nohup.out`` or ``$HOME/nohup.out`` with ``c.open()`` and ``c.dup2()``.
* Invokes target command via ``c.execvp()``.

[TECH-STDBUF-001] Libstdbuf Loader & Env Injector
-------------------------------------------------
* Implemented in ``src/commands/stdbuf.zig``.
* Formats environment variables: ``_STDBUF_I``, ``_STDBUF_O``, ``_STDBUF_E``.
* Locates or populates ``LD_PRELOAD`` with ``libstdbuf.so`` path.
* Executes target executable via ``c.execvp()``.

[TECH-STTY-001] Terminal Line Settings Controller
-------------------------------------------------
* Implemented in ``src/commands/stty.zig`` (and ``src/commands/stty/`` submodules).
* Uses ``c.tcgetattr()`` and ``c.tcsetattr()`` on file descriptor 0 or ``-F DEVICE``.
* Decodes baud rate, terminal modes (c_iflag, c_oflag, c_cflag, c_lflag), control characters (c_cc).
* Formats human-readable output (``-a``), hex configuration string (``-g``), or updates termios settings according to arguments.
* Queries terminal dimensions using ``c.ioctl(fd, c.TIOCGWINSZ, &ws)``.

[TECH-DATE-001] Chronological Formatter & Parser
------------------------------------------------
* Implemented in ``src/commands/date.zig`` (and ``src/commands/date/`` submodules).
* Obtains timestamps using ``c.clock_gettime(c.CLOCK_REALTIME, &ts)`` or parses user string.
* Date parsing engine supports ISO 8601, epoch seconds (``@SEC``), and relative date markers.
* Emits formatted strings using ``c.strftime()`` or custom formatting engine for ``%N`` nanosecond resolution.
* System time adjustment via ``c.clock_settime()`` when ``-s`` is passed.

[TECH-CHROOT-001] Root Directory Containment
--------------------------------------------
* Implemented in ``src/commands/chroot.zig``.
* Resolves target user and group IDs via ``c.getpwnam()``, ``c.getgrnam()``.
* Executes ``c.chroot()``, sets supplementary groups with ``c.setgroups()``, changes GID and UID with ``c.setgid()`` and ``c.setuid()``.
* Changes working directory with ``c.chdir("/")`` unless ``--skip-chdir``.
* Executes specified command or default interactive shell via ``c.execvp()``.
