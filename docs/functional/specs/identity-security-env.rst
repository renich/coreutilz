=============================================================
Functional Specification: Identity, Security & Environment
=============================================================

:Domain: Identity, Security & Environment
:Target Utilities: ``id``, ``groups``, ``who``, ``users``, ``pinky``, ``uname``, ``arch``, ``chcon``, ``runcon``
:Specification ID: ``SPEC-FUNC-ID-SEC-ENV``

.. contents:: Table of Contents
   :depth: 2
   :backlinks: none

1. Overview
===========

The Identity, Security & Environment suite provides user/group identity inspection, login accounting, system architecture and kernel reporting, and SELinux security context inspection and enforcement.

2. Functional Requirements: ``id``
==================================

[FUNC-ID-001] User & Group Identity Inspection
----------------------------------------------
* Print real and effective user ID (UID), group ID (GID), and supplementary group memberships.
* **Default Output Format**:
  ``uid=UID(username) gid=GID(groupname) groups=GID(groupname),... [context=CONTEXT]``
* **Filtering Flags**:
  - ``-u, --user``: Print only effective UID (or real UID if combined with ``-r``).
  - ``-g, --group``: Print only effective GID (or real GID if combined with ``-r``).
  - ``-G, --groups``: Print all group IDs (effective, real, and supplementary).
  - ``-n, --name``: Print user/group name instead of numeric ID (used with ``-u``, ``-g``, ``-G``).
  - ``-r, --real``: Print real ID instead of effective ID (used with ``-u``, ``-g``, ``-G``).
  - ``-z, --zero``: Delimit output entries with NUL byte (0x00) instead of whitespace.
  - ``-Z, --context``: Print only security context.
* **Operands**:
  - Optional ``[USER]`` operand. If specified, report identity for the named user.
* **Exit Status**:
  - Exit code 0 on success.
  - Exit code 1 if user is not found or conflicting/invalid options are supplied.

3. Functional Requirements: ``groups``
======================================

[FUNC-GROUPS-001] Supplementary Group Membership
------------------------------------------------
* Print the groups to which the current user or specified user(s) belong.
* **Invocation Modes**:
  - No arguments: Print space-separated list of group names for the current process.
  - ``[USER]...``: Print ``username : group1 group2 ...`` for each specified user.
* **Exit Status**:
  - Exit code 0 on success.
  - Exit code 1 if any specified user does not exist.

4. Functional Requirements: ``who``
===================================

[FUNC-WHO-001] Active Logged-in Session Reporting
-------------------------------------------------
* Query the system login accounting database (``utmp``/``utmpx``) and report currently logged-in users.
* **Options**:
  - ``-a, --all``: Same as ``-b -d --login -p -r -t -T -u``.
  - ``-b, --boot``: Time of last system boot.
  - ``-d, --dead``: Print dead processes.
  - ``-H, --heading``: Print line of column headings.
  - ``-l, --login``: Print system login processes.
  - ``-m``: Only hostname and user associated with stdin (equivalent to ``who am i``).
  - ``-p, --process``: Print active processes spawned by init.
  - ``-q, --count``: All login names and number of users logged on.
  - ``-r, --runlevel``: Print current runlevel.
  - ``-s, --short``: Print only name, line, and time (default).
  - ``-t, --time``: Print last system clock change.
  - ``-u, --users``: List users logged in with idle time.
  - ``-w, -T, --mesg``: Add user message status as ``+`` (writable), ``-`` (non-writable), or ``?``.
* **Two-argument invocation**:
  - ``who am i`` or ``who mom likes``: equivalent to ``who -m``.

5. Functional Requirements: ``users``
=====================================

[FUNC-USERS-001] Current Login Names Listing
--------------------------------------------
* Output space-separated, alphabetically sorted list of login names for users currently logged on.
* Optional ``[FILE]`` argument to specify an alternate utmp/utmpx accounting file.
* Terminate line with a single newline character.

6. Functional Requirements: ``pinky``
=====================================

[FUNC-PINKY-001] Lightweight Finger Information
-----------------------------------------------
* Print brief summary of logged-in users or detailed profile for specified users.
* **Short Format (default)**:
  - Columns: Login name, Full Name, TTY, Idle time, Login time, Where (remote host).
  - Options to omit fields: ``-f`` (heading), ``-w`` (full name), ``-i`` (idle), ``-q`` (idle, office, phone).
* **Long Format (``-l``)**:
  - Multi-line profile per user including Directory, Shell, Plan (``~/.plan``), and Project (``~/.project``).
  - Suppression options: ``-b`` (home/shell), ``-h`` (project), ``-p`` (plan).

7. Functional Requirements: ``uname``
=====================================

[FUNC-UNAME-001] System & Architecture Information
--------------------------------------------------
* Query system identification via ``uname(2)`` and format requested fields.
* **Field Selectors**:
  - ``-s, --kernel-name``: Kernel name (default if no flags).
  - ``-n, --nodename``: Network node hostname.
  - ``-r, --kernel-release``: Kernel release version.
  - ``-v, --kernel-version``: Kernel build version/timestamp.
  - ``-m, --machine``: Machine hardware architecture.
  - ``-p, --processor``: Processor type (or ``unknown``/machine).
  - ``-i, --hardware-platform``: Hardware platform (or ``unknown``/machine).
  - ``-o, --operating-system``: Operating system name (e.g. ``GNU/Linux``).
  - ``-a, --all``: Equivalent to ``-snrvmpo`` (or all recognized fields in order).

8. Functional Requirements: ``arch``
====================================

[FUNC-ARCH-001] Machine Architecture Shorthand
----------------------------------------------
* Equivalent to ``uname -m``. Output machine architecture string followed by a newline.
* Accept standard ``--help`` and ``--version`` flags.

9. Functional Requirements: ``chcon``
=====================================

[FUNC-CHCON-001] Security Context Mutation
------------------------------------------
* Change the SELinux security context of each specified ``FILE...``.
* **Context Specification**:
  - Full context string as positional operand (when options not used).
  - Component overrides: ``-u, --user=USER``, ``-r, --role=ROLE``, ``-t, --type=TYPE``, ``-l, --range=RANGE``.
  - ``--reference=RFILE``: Use security context of ``RFILE``.
* **Traversal & Dereferencing**:
  - ``-R, --recursive``: Recursively modify files and directories.
  - ``-H``, ``-L``, ``-P``: Command-line symlink dereference options.
  - ``--dereference``: Follow symbolic links (default).
  - ``-h, --no-dereference``: Affect symbolic links directly rather than targets.
* **Safety & Diagnostics**:
  - ``--preserve-root``: Fail and refuse to operate recursively on ``/``.
  - ``-c, --changes``: Verbose reporting only when a change is made.
  - ``-v, --verbose``: Output a diagnostic for every file processed.

10. Functional Requirements: ``runcon``
======================================

[FUNC-RUNCON-001] Context-Transitioned Process Execution
--------------------------------------------------------
* Run ``COMMAND [ARG]...`` in a specified SELinux security context.
* **Syntax Variants**:
  - ``runcon CONTEXT COMMAND [ARG]...``
  - ``runcon [-c] [-u USER] [-r ROLE] [-t TYPE] [-l RANGE] COMMAND [ARG]...``
* **Exit Status**:
  - Exit status of ``COMMAND`` if successfully executed.
  - Exit code 125 if ``runcon`` encounters configuration errors, invalid arguments, or SELinux transition failures.
  - Exit code 126 if ``COMMAND`` is found but cannot be invoked.
  - Exit code 127 if ``COMMAND`` cannot be found.
