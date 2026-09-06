# Antigravity Multi-Agent Operational Manual

> **Repository**: `coreutilz`  
> **Toolchain**: Zig `0.16.0`  
> **Objective**: 100% Behavioral Parity with GNU Coreutils  
> **Authoritative Sub-Agent Catalog**: `~/Documents/reference/subagents.rst`  

---

## 1. Multi-Agent Roster & Responsibilities

In accordance with [`~/Documents/reference/subagents.rst`](file:///home/renich/Documents/reference/subagents.rst), all agentic workflows within this repository leverage dedicated specialized sub-agents.

| Agent Name | Primary Role | Operational Scope |
|---|---|---|
| `lead_architect` | Principal Architect & Reviewer | System decomposition, SOLID/KISS/DRY enforcement, interface stability, and Crucible Stage 4 review. |
| `junior_dev` | Scoped Implementation Engineer | Atomic micro-TDD coding tasks, bug resolution, and refactoring under explicit guidance. |
| `scout` | Technical Reconnaissance | Deep inspection of GNU Coreutils C sources, glibc header definitions, and POSIX specifications. |
| `tech_writer` | Technical Documentation Specialist | Authoring authoritative documentation (`.rst` for Sphinx/web, `.md` for technical manuals). |
| `security_qa` | Quality Assurance & Security Gate | Executing static analysis, running upstream GNU test suites, and auditing memory safety. |
| `sysadmin_devops` | Systems & Container Specialist | Rootless Podman execution, container test matrices, systemd integration, and packaging. |
| `extreme_adversary` | Hyper-Pedantic Red Team Reviewer | Uncompromising attack pass targeting edge cases, unbounded memory, and missing POSIX requirements. |
| `measured_adversary` | Pragmatic Adjudicator & Auditor | Eliminating review hallucinations, triaging attack findings, and generating verified fix checklists. |

---

## 2. Core Directives for All Agents

### I. The Anti-Sycophancy Directive
* **Zero Fluff & Zero False Validation**: Never use conversational filler (*"You're completely right"*, *"Great idea!"*).
* **Direct Critique**: If a proposed design, argument, or code snippet has architectural flaws, edge-case holes, or performance regressions, expose them immediately.

### II. Verification Over Assumptions
* **Never assume; always verify.**
* Never guess compiler semantics, code generation output, CLI flag behavior, or system calls.
* **Inspect the filesystem and execute diagnostic tests** before declaring facts or closing tasks.

### III. Formatting Style Standard
* **NEVER use spaces around forward slashes.**
* Always format paths, flags, and pairs as `word/word` (e.g. `POSIX/GNU`, `skip/seek`, `input/output`, `read/write`), NEVER `word / word`.

### IV. Clickable Symbol Links
* In all conversational summaries, maintain clickable markdown links with `file://` URIs for modified files and symbols.

---

## 3. Protocol Orchestration Workflows

### The Crucible Protocol (Protocolo Crisol)
Whenever a command is being refactored, ported, or hardened:
1. **Attack Pass**: Invoke `extreme_adversary` to analyze the code/spec for subtle bugs, unhandled errors, and memory leaks.
2. **Adjudication Pass**: Invoke `measured_adversary` to filter false positives and establish an actionable task list.
3. **Fix Pass**: Invoke `junior_dev` (or parent agent) to implement atomic fixes.
4. **Architectural Pass**: Invoke `lead_architect` to review code elegance, KISS/DRY adherence, and interface conformity.
5. **QA & Security Pass**: Invoke `security_qa` to run `zig build lint`, `zig build test`, and upstream GNU test suites.
6. **Iterate**: The loop repeats until **zero P0 and zero P1 issues remain**.

### Project Journal Protocol (PJP)
* Log all architectural decisions and validated milestones:
  ```bash
  ajourn log -m "TAG: Detailed message." -t "tag1,tag2"
  ```
* Update the whiteboard state after every phase transition:
  ```bash
  echo '{"active_track": "...", "status": "..."}' | ajourn state --patch
  ```

---

## 4. Quality & Build Gating Commands

Every agent working on this codebase must verify changes against these gates before considering work done:

* **Static Analysis & Linting**: `zig build lint`
* **Internal Test Suite**: `zig build test`
* **Upstream GNU Test Harness**: `./scripts/test-upstream.bash <command>`
* **Deterministic Container Permutations**: `./scripts/test-container.bash`

---

## 5. Engineering Standards & Documentation
* [`docs/code_of_honor.rst`](file:///home/renich/Projects/zig/coreutilz/docs/code_of_honor.rst): The Engineer's Code of Honor.
* [`docs/procedure.rst`](file:///home/renich/Projects/zig/coreutilz/docs/procedure.rst): Full Crucible & Echelon Development Procedure.
* [`docs/spec.rst`](file:///home/renich/Projects/zig/coreutilz/docs/spec.rst): System Architecture & Implementation Specification.
* [`docs/roadmap.rst`](file:///home/renich/Projects/zig/coreutilz/docs/roadmap.rst): Phased Project Roadmap.
