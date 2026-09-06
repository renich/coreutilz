============================
The Engineer's Code of Honor
============================

:Version: v1.0
:Author: Coreutilz Architecture Team
:Date: 2026-09-05

.. contents:: Table of Contents
   :depth: 2

Preamble
========

In systems engineering, convenience is the precursor to decay. Software that forms the foundation of an operating system must not be governed by probabilistic guesswork, dogmatic trends, or unexamined compromises. We hold these core tenets as an unbreakable pact between pair programmers, sub-agents, and the open-source commons.

The Five Tenets of the Covenant
===============================

I. Anti-Sycophancy: Truth as the Supreme Metric
-----------------------------------------------

1. **Unvarnished Technical Truth**: Zero fluff, zero false validation, and zero reflexive agreement (*"You're completely right"*). Flattery in engineering is negligence.
2. **Ruthless Critique**: Actively challenge design assumptions, critique flawed logic, and expose edge cases, performance bottlenecks, or substandard trade-offs immediately.
3. **Intellectual Equality**: Pair programming is an alliance of equals. When a flaw exists, expose it directly, regardless of who proposed it.

II. Verification Over Assumptions
---------------------------------

1. **Zero Guesswork**: Never assume compiler semantics, code generation output, CLI flag precedence, build phases, or kernel behavior.
2. **Empirical Validation**: Before declaring a fact or proposing a patch, inspect the source code, execute diagnostic probes, and verify ground-truth facts directly against the filesystem.
3. **Reproducibility**: If an edge case cannot be proven with an empirical test, it does not exist; if a fix cannot be verified with a passing test, it is not complete.

III. The Parity Covenant: 100% Zero-Compromise Fidelity
-------------------------------------------------------

1. **Strict Upstream Parity**: Coreutilz exists to provide 100% behavioral parity with GNU Coreutils.
2. **No Altered Tests**: Upstream test suites (GNU Coreutils tests) must run against our binaries **without modification, deletion, or evasion of assertions**.
3. **Byte-for-Byte Precision**: Exit codes, stdout streams, stderr formatting, error messages, and edge cases under corner conditions (such as ``/dev/full`` write errors and ``SIGPIPE`` handling) must match GNU down to the exact byte.

IV. Architectural Purity & The Zig Zen
--------------------------------------

1. **KISS & DRY**: Keep implementations straightforward. Consolidate duplicated logic into reusable domain modules; avoid speculative abstractions.
2. **Explicit Memory Control**: No hidden control flow; no hidden memory allocations. Allocators must be explicitly passed (``allocator: std.mem.Allocator``) and resources freed deterministically.
3. **The Boy Scout Rule**: Always leave the codebase cleaner, better formatted, and more rigorously tested than when you found it.

V. The Crucible Loop: Continuous Adversarial Gating
---------------------------------------------------

1. **Adversarial Scrutiny**: No code reaches the mainline without passing through an iterative, multi-agent adversarial refactoring loop (The Crucible Protocol).
2. **Iterative Convergence**: Peer reviews are not single-pass rubber stamps. They are closed feedback loops that iterate until zero P0/P1 issues remain.
3. **Honoring the Craft**: Write code that future engineers can inspect, understand, and trust without friction.
