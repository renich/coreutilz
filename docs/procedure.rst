=====================================================
Crucible & Echelon Engineering Development Procedure
=====================================================

:Version: v1.0
:Author: Coreutilz Architecture Team
:Date: 2026-09-05

.. contents:: Table of Contents
   :depth: 2

Overview
========

The Coreutilz development procedure is a strict, zero-trust, test-driven engineering lifecycle designed to enforce 100% behavioral parity with GNU Coreutils while maintaining architectural purity in Zig. 

Every feature, utility, refactor, or bugfix must progress through gated phases where **peer reviews are closed feedback loops** that continue iterating until zero defects remain.

Phase 1: Architectural Planning & Specification Loop
====================================================

No code or tests shall be written without an approved architectural plan.

1. **Plan Authoring**:
   - The Lead Architect (or developer) itemizes GNU utility behavior, options, flags, corner cases, and POSIX specifications.
   - Defines the module boundary, memory management strategy (allocators, scratch buffers), and syscall interface.

2. **Adversarial Plan Review Loop**:
   - **Extreme Adversary**: Attacks the plan. Hunts for missing POSIX corner cases, unbounded memory allocations, platform portability traps, and ambiguous specifications.
   - **Measured Adversary**: Adjudicates the attack report, filters theoretical edge cases, and delivers an authoritative checklist of actionable plan fixes.
   - **Fix & Re-Review**: The author updates the specification. This loop repeats until both adversaries and the Lead Architect sign off with **ZERO open findings**.

Phase 2: Test-Driven Development (TDD) Authoring Loop
=====================================================

Tests must be written and peer-reviewed **before** implementing the production code.

1. **Test Authoring**:

   - Author hermetic unit tests in ``tests/<cmd>_test.zig`` using ``std.testing.allocator`` to verify zero memory leaks.
   - Prepare upstream test harness integration in ``scripts/test-upstream.bash``.
   - Include adversarial test vectors:

     * Empty input, single-byte input, gigabyte input streams.
     * Write failures on ``/dev/full`` (verifying exact GNU exit status).
     * Broken pipes (``SIGPIPE`` / ``EPIPE``).
     * Dangling symlinks, symlink cycles, and recursive directory structures exceeding ``PATH_MAX``.
     * Missing, invalid, or mutually exclusive command-line options.

2. **Adversarial Test Review Loop**:

   - **Security QA & Extreme Adversary**: Audit the test suite. Verify test-to-spec traceability, edge-case coverage, and assertion integrity.
   - **Fix & Re-Review**: If edge cases are omitted or assertions are permissive, tests are hardened until the review loop passes with **ZERO open findings**.

Phase 3: Implementation & Micro-TDD
===================================

1. **Modular Implementation**:

   - Implement the utility in ``src/commands/<cmd>.zig`` exposing:

     .. code-block:: zig

        pub const name: []const u8 = "<cmd>";
        pub const version: []const u8 = "0.1.0";
        pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8

   - Strictly adhere to `The Zig Zen <docs/technical/style.rst>`_:

     * Pass allocators explicitly; never use hidden or global allocators.
     * Deallocate resources immediately using ``defer`` and ``errdefer``.
     * Eliminate ``catch unreachable`` from runtime I/O and allocation paths.
   - Follow `The Boy Scout Rule`: Clean up adjacent code, consolidate duplicates into ``src/utils/``.

Phase 4: The Crucible Code Review Loop
======================================

Once code compiles and passes local tests, it enters **The Crucible Protocol** (Protocolo Crisol):

.. code-block:: text

   ┌────────────────────────────────────────────────────────┐
   │ 1. Extreme Adversary Pass (Hyper-pedantic code attack)  │
   └───────────────────────────┬────────────────────────────┘
                               │
                               ▼
   ┌────────────────────────────────────────────────────────┐
   │ 2. Measured Adversary Pass (Pragmatic triage & audit)  │
   └───────────────────────────┬────────────────────────────┘
                               │
                               ▼
   ┌────────────────────────────────────────────────────────┐
   │ 3. Developer Fix & Micro-TDD Refactor                  │
   └───────────────────────────┬────────────────────────────┘
                               │
                               ▼
   ┌────────────────────────────────────────────────────────┐
   │ 4. Lead Architect Pass (SOLID, KISS, DRY review)       │
   └───────────────────────────┬────────────────────────────┘
                               │
                               ▼
   ┌────────────────────────────────────────────────────────┐
   │ 5. Security QA Verification & Static Analysis Gate     │
   └───────────────────────────┬────────────────────────────┘
                               │
         [Open Findings] ◄─────┴─────► [Clean Pass: 0 Findings]
                │                                    │
                ▼                                    ▼
         Repeat Steps 1-5                   Promote to Phase 5

* **Circuit Breaker**: The Crucible loop iterates until **zero P0 and zero P1 issues remain**. If convergence is not achieved after 3 iterations, the Lead Architect intervenes to resolve architectural divergence.

Phase 5: Final Validation & Gating
==================================

1. **Static Analysis & Lint Gate**:
   .. code-block:: bash

      zig build lint

   Enforces ``zig fmt --check``, ``zig ast-check`` across all files, interface signature compliance, and ShellCheck.

2. **Upstream GNU Test Suite Execution**:
   .. code-block:: bash

      ./scripts/test-upstream.bash <cmd>

   The command must achieve **100% pass rate** on all applicable upstream tests without modifying upstream test files.

3. **Deterministic Container Permutation Execution**:
   .. code-block:: bash

      ./scripts/test-container.bash

   Validates parity across permutations in an isolated Linux container.

Phase 6: Commit, Log, and Push
==============================

1. **PJP Ledger Recording**:
   - Log architectural decisions and milestones using ``ajourn log -m "..." -t "..."``.
   - Update project whiteboard with ``ajourn state --patch``.

2. **Git Hygiene & Commit Standards**:
   - Conventional Commits: ``type(scope): description``.
   - AI co-authorship and sign-off trailers.
   - Verified compilation on the tip of the commit.
