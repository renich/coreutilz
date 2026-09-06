#!/usr/bin/bash
set -euo pipefail
IFS=$'\n\t'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

check_formatting() {
    printf '==> Checking Zig code formatting (zig fmt --check)...\n'
    zig fmt --check "${REPO_ROOT}/src" "${REPO_ROOT}/tests" "${REPO_ROOT}/build.zig"
    printf '\e[32mPASS\e[0m: Code formatting is pristine.\n'
}

check_ast() {
    printf '==> Performing Zig AST syntax and structure validation (zig ast-check)...\n'
    local ast_failures=0
    local zig_file
    while IFS= read -r zig_file; do
        if ! zig ast-check "${zig_file}"; then
            printf '\e[31mFAIL\e[0m: AST check failed for %s\n' "${zig_file}" >&2
            ast_failures=$((ast_failures + 1))
        fi
    done < <(find "${REPO_ROOT}/src" "${REPO_ROOT}/tests" -name "*.zig" | sort)

    if [[ ${ast_failures} -gt 0 ]]; then
        printf '\e[31mERROR\e[0m: %d file(s) failed AST validation.\n' "${ast_failures}" >&2
        return 1
    fi
    printf '\e[32mPASS\e[0m: All Zig source files passed AST check.\n'
}

check_architecture() {
    printf '==> Verifying command architecture standards...\n'
    local arch_failures=0
    local cmd_file
    local base

    for cmd_file in "${REPO_ROOT}/src/commands/"*.zig; do
        base="$(basename "${cmd_file}")"
        if ! grep -q 'pub const name:' "${cmd_file}"; then
            printf '\e[31mFAIL\e[0m: %s missing "pub const name"\n' "${base}" >&2
            arch_failures=$((arch_failures + 1))
        fi
        if ! grep -q 'pub const version:' "${cmd_file}"; then
            printf '\e[31mFAIL\e[0m: %s missing "pub const version"\n' "${base}" >&2
            arch_failures=$((arch_failures + 1))
        fi
        if ! grep -qE 'pub fn run\(args: \[\]\[\]const u8, (_|allocator): std\.mem\.Allocator\)' "${cmd_file}"; then
            printf '\e[31mFAIL\e[0m: %s missing standard "pub fn run(args: [][]const u8, (allocator|_): std.mem.Allocator)" signature\n' "${base}" >&2
            arch_failures=$((arch_failures + 1))
        fi
    done

    if [[ ${arch_failures} -gt 0 ]]; then
        printf '\e[31mERROR\e[0m: %d command(s) violate architecture interface requirements.\n' "${arch_failures}" >&2
        return 1
    fi
    printf '\e[32mPASS\e[0m: All commands adhere to standardized interface contract.\n'
}

check_scripts() {
    printf '==> Validating repository Bash scripts with ShellCheck...\n'
    local script_file
    while IFS= read -r script_file; do
        if ! shellcheck "${script_file}"; then
            printf '\e[31mFAIL\e[0m: ShellCheck failed for %s\n' "${script_file}" >&2
            return 1
        fi
    done < <(find "${REPO_ROOT}/scripts" -name "*.bash" | sort)
    printf '\e[32mPASS\e[0m: All repository Bash scripts comply with strict standards.\n'
}

main() {
    check_formatting
    check_ast
    check_architecture
    check_scripts
    printf '\n\e[32mSUCCESS\e[0m: All lint and static analysis gates passed!\n'
}

main "$@"
