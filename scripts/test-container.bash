#!/usr/bin/bash
set -euo pipefail
IFS=$'\n\t'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly BIN_DIR="${REPO_ROOT}/zig-out/bin"

CONTAINER_IMAGE="localhost/coreutilz:latest"
TEST_MODE="all"
BUILD_FIRST=0

usage() {
    cat <<'EOF'
Usage: ./scripts/test-container.bash [OPTIONS]

Deterministic integration and permutation test runner for Coreutilz inside Podman.

Options:
  -i, --image <IMAGE>   Specify container image (default: localhost/coreutilz:latest)
  -m, --mode <MODE>     Test mode: all, direct, multicall, symlink, functional (default: all)
  -b, --build           Rebuild container image before running tests
  -h, --help            Display this help message and exit
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -i|--image)
            CONTAINER_IMAGE="$2"
            shift 2
            ;;
        -m|--mode)
            TEST_MODE="$2"
            shift 2
            ;;
        -b|--build)
            BUILD_FIRST=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            printf 'Error: Unknown option "%s"\n' "$1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if ! command -v podman >/dev/null 2>&1; then
    printf 'Error: podman binary not found in PATH.\n' >&2
    exit 1
fi

if [[ ${BUILD_FIRST} -eq 1 ]]; then
    printf '==> Building Coreutilz binaries...\n'
    zig build -Doptimize=ReleaseFast
    printf '==> Building container image %s...\n' "${CONTAINER_IMAGE}"
    podman build -t "${CONTAINER_IMAGE}" -f "${REPO_ROOT}/Containerfile" "${REPO_ROOT}"
fi

# Ensure container image exists
if ! podman image exists "${CONTAINER_IMAGE}" 2>/dev/null; then
    if [[ "${CONTAINER_IMAGE}" == "localhost/coreutilz:latest" ]]; then
        printf '==> Container image %s not found. Building now...\n' "${CONTAINER_IMAGE}"
        if [[ ! -d "${BIN_DIR}" ]]; then
            zig build -Doptimize=ReleaseFast
        fi
        podman build -t "${CONTAINER_IMAGE}" -f "${REPO_ROOT}/Containerfile" "${REPO_ROOT}"
    else
        printf '==> Pulling container image %s...\n' "${CONTAINER_IMAGE}"
        podman pull "${CONTAINER_IMAGE}"
    fi
fi

printf '==================================================\n'
printf 'Coreutilz: Deterministic Container Permutation Test\n'
printf 'Image: %s\n' "${CONTAINER_IMAGE}"
printf 'Mode:  %s\n' "${TEST_MODE}"
printf '==================================================\n'

container_test_runner() {
    cat <<RUNNER_EOF
#!/usr/bin/bash
set -euo pipefail
IFS=$'\n\t'

readonly TEST_MODE="${TEST_MODE}"
readonly GNU_BIN_DIR="/usr/bin"

# Locate Coreutilz binaries
if [[ -x "/usr/local/bin/coreutilz" ]]; then
    readonly ZIG_BIN_DIR="/usr/local/bin"
elif [[ -x "/opt/coreutilz/bin/coreutilz" ]]; then
    readonly ZIG_BIN_DIR="/opt/coreutilz/bin"
else
    printf 'Error: Coreutilz binaries not found in container.\n' >&2
    exit 1
fi

readonly SYMLINK_DIR="/tmp/coreutilz-symlinks"
mkdir -p "\${SYMLINK_DIR}"

pass_count=0
fail_count=0

record_pass() {
    pass_count=\$((pass_count + 1))
}

record_fail() {
    local msg="\$1"
    printf '  \e[31mFAIL\e[0m: %s\n' "\${msg}"
    fail_count=\$((fail_count + 1))
}

compare_rc() {
    local name="\$1"
    local desc="\$2"
    local zig_cmd="\$3"
    local gnu_cmd="\$4"

    local zig_rc=0
    local gnu_rc=0

    set +e
    eval "\${zig_cmd}" >/dev/null 2>&1
    zig_rc=\$?
    eval "\${gnu_cmd}" >/dev/null 2>&1
    gnu_rc=\$?
    set -e

    if [[ \${zig_rc} -eq \${gnu_rc} ]]; then
        record_pass
        return 0
    else
        record_fail "\${name} [\${desc}] -> Exit code mismatch: zig=\${zig_rc}, gnu=\${gnu_rc}"
        return 1
    fi
}

compare_full() {
    local cmd="\$1"
    local bin="\$2"

    if [[ ! -x "\${GNU_BIN_DIR}/\${cmd}" ]]; then
        return 0
    fi

    local zig_rc=0
    local gnu_rc=0

    set +e
    "\${bin}" --help >/dev/full 2>/dev/null
    zig_rc=\$?
    "\${GNU_BIN_DIR}/\${cmd}" --help >/dev/full 2>/dev/null
    gnu_rc=\$?
    set -e

    if [[ \${zig_rc} -eq \${gnu_rc} ]]; then
        record_pass
        return 0
    else
        record_fail "\${cmd} [/dev/full] -> Exit code mismatch: zig=\${zig_rc}, gnu=\${gnu_rc}"
        return 1
    fi
}

compare_output() {
    local desc="\$1"
    local zig_cmd="\$2"
    local gnu_cmd="\$3"

    local zig_out=""
    local gnu_out=""
    local zig_rc=0
    local gnu_rc=0

    set +e
    zig_out=\$(eval "\${zig_cmd}" 2>&1)
    zig_rc=\$?
    gnu_out=\$(eval "\${gnu_cmd}" 2>&1)
    gnu_rc=\$?
    set -e

    if [[ \${zig_rc} -ne \${gnu_rc} ]]; then
        record_fail "\${desc} -> Exit code mismatch: zig=\${zig_rc}, gnu=\${gnu_rc}"
        return 1
    fi

    if [[ "\${zig_out}" != "\${gnu_out}" ]]; then
        record_fail "\${desc} -> Output mismatch:\nZIG:\n\${zig_out}\nGNU:\n\${gnu_out}"
        return 1
    fi

    record_pass
    return 0
}

# Collect commands
commands=()
for b in "\${ZIG_BIN_DIR}"/*; do
    if [[ -x "\${b}" && ! -d "\${b}" ]]; then
        base="\$(basename "\${b}")"
        if [[ "\${base}" != "coreutilz" && "\${base}" != "getlimits" ]]; then
            commands+=("\${base}")
            # Setup symlinks
            ln -sf "\${ZIG_BIN_DIR}/coreutilz" "\${SYMLINK_DIR}/\${base}"
        fi
    fi
done

total_commands=\${#commands[@]}
printf 'Discovered %d Coreutilz commands in %s\n\n' "\${total_commands}" "\${ZIG_BIN_DIR}"

# 1. DIRECT BINARY PERMUTATIONS
if [[ "\${TEST_MODE}" == "all" || "\${TEST_MODE}" == "direct" ]]; then
    printf '==> Phase 1: Standalone Direct Binary Permutations...\n'
    for cmd in "\${commands[@]}"; do
        [[ ! -x "\${GNU_BIN_DIR}/\${cmd}" ]] && continue

        compare_rc "\${cmd}" "direct:--help" "\${ZIG_BIN_DIR}/\${cmd} --help" "\${GNU_BIN_DIR}/\${cmd} --help" || true
        compare_rc "\${cmd}" "direct:--version" "\${ZIG_BIN_DIR}/\${cmd} --version" "\${GNU_BIN_DIR}/\${cmd} --version" || true
        compare_rc "\${cmd}" "direct:invalid-opt" "\${ZIG_BIN_DIR}/\${cmd} --invalid-opt-xyz-999" "\${GNU_BIN_DIR}/\${cmd} --invalid-opt-xyz-999" || true
        compare_full "\${cmd}" "\${ZIG_BIN_DIR}/\${cmd}" || true

        case "\${cmd}" in
            cat|head|wc|stat|chmod|rm|rmdir|touch|truncate|readlink)
                compare_rc "\${cmd}" "direct:nonexistent" "\${ZIG_BIN_DIR}/\${cmd} /tmp/nonexistent_file_xyz_12345" "\${GNU_BIN_DIR}/\${cmd} /tmp/nonexistent_file_xyz_12345" || true
                ;;
        esac
    done
fi

# 2. MULTICALL DISPATCH PERMUTATIONS
if [[ "\${TEST_MODE}" == "all" || "\${TEST_MODE}" == "multicall" ]]; then
    printf '\n==> Phase 2: Multicall Binary (coreutilz <cmd>) Permutations...\n'
    # Verify coreutilz itself
    compare_rc "coreutilz" "multicall:--help" "\${ZIG_BIN_DIR}/coreutilz --help" "true" || true
    compare_rc "coreutilz" "multicall:--version" "\${ZIG_BIN_DIR}/coreutilz --version" "true" || true

    for cmd in "\${commands[@]}"; do
        [[ ! -x "\${GNU_BIN_DIR}/\${cmd}" ]] && continue

        compare_rc "\${cmd}" "multicall:--help" "\${ZIG_BIN_DIR}/coreutilz \${cmd} --help" "\${GNU_BIN_DIR}/\${cmd} --help" || true
        compare_rc "\${cmd}" "multicall:--version" "\${ZIG_BIN_DIR}/coreutilz \${cmd} --version" "\${GNU_BIN_DIR}/\${cmd} --version" || true
        compare_rc "\${cmd}" "multicall:invalid-opt" "\${ZIG_BIN_DIR}/coreutilz \${cmd} --invalid-opt-xyz-999" "\${GNU_BIN_DIR}/\${cmd} --invalid-opt-xyz-999" || true
    done
fi

# 3. SYMLINK DISPATCH PERMUTATIONS
if [[ "\${TEST_MODE}" == "all" || "\${TEST_MODE}" == "symlink" ]]; then
    printf '\n==> Phase 3: Symlink Multicall (<symlink> -> coreutilz) Permutations...\n'
    for cmd in "\${commands[@]}"; do
        [[ ! -x "\${GNU_BIN_DIR}/\${cmd}" ]] && continue

        compare_rc "\${cmd}" "symlink:--help" "\${SYMLINK_DIR}/\${cmd} --help" "\${GNU_BIN_DIR}/\${cmd} --help" || true
        compare_rc "\${cmd}" "symlink:--version" "\${SYMLINK_DIR}/\${cmd} --version" "\${GNU_BIN_DIR}/\${cmd} --version" || true
        compare_rc "\${cmd}" "symlink:invalid-opt" "\${SYMLINK_DIR}/\${cmd} --invalid-opt-xyz-999" "\${GNU_BIN_DIR}/\${cmd} --invalid-opt-xyz-999" || true
    done
fi

# 4. FUNCTIONAL PARITY SUITE
if [[ "\${TEST_MODE}" == "all" || "\${TEST_MODE}" == "functional" ]]; then
    printf '\n==> Phase 4: Deterministic Functional Parity Checks...\n'

    # echo
    compare_output "echo:simple text" "\${ZIG_BIN_DIR}/echo 'hello world'" "\${GNU_BIN_DIR}/echo 'hello world'" || true
    compare_output "echo:-n flag" "\${ZIG_BIN_DIR}/echo -n 'hello world'" "\${GNU_BIN_DIR}/echo -n 'hello world'" || true
    compare_output "echo:-e escapes" "\${ZIG_BIN_DIR}/echo -e 'line1\tcol2\nline2'" "\${GNU_BIN_DIR}/echo -e 'line1\tcol2\nline2'" || true

    # true & false
    compare_rc "true" "functional:exit 0" "\${ZIG_BIN_DIR}/true" "\${GNU_BIN_DIR}/true" || true
    compare_rc "false" "functional:exit 1" "\${ZIG_BIN_DIR}/false" "\${GNU_BIN_DIR}/false" || true

    # seq
    compare_output "seq:single arg" "\${ZIG_BIN_DIR}/seq 5" "\${GNU_BIN_DIR}/seq 5" || true
    compare_output "seq:range" "\${ZIG_BIN_DIR}/seq 2 7" "\${GNU_BIN_DIR}/seq 2 7" || true
    compare_output "seq:step" "\${ZIG_BIN_DIR}/seq 1 2 9" "\${GNU_BIN_DIR}/seq 1 2 9" || true
    compare_output "seq:negative step" "\${ZIG_BIN_DIR}/seq 10 -2 2" "\${GNU_BIN_DIR}/seq 10 -2 2" || true

    # pwd
    compare_output "pwd:basic" "\${ZIG_BIN_DIR}/pwd" "\${GNU_BIN_DIR}/pwd" || true

    # basename & dirname
    compare_output "basename:path" "\${ZIG_BIN_DIR}/basename /usr/local/bin/coreutilz" "\${GNU_BIN_DIR}/basename /usr/local/bin/coreutilz" || true
    compare_output "basename:suffix" "\${ZIG_BIN_DIR}/basename /path/to/archive.tar.gz .tar.gz" "\${GNU_BIN_DIR}/basename /path/to/archive.tar.gz .tar.gz" || true
    compare_output "dirname:path" "\${ZIG_BIN_DIR}/dirname /usr/local/bin/coreutilz" "\${GNU_BIN_DIR}/dirname /usr/local/bin/coreutilz" || true

    # cut & paste
    compare_output "cut:fields" "\${ZIG_BIN_DIR}/cut -d: -f1,3 /etc/passwd | head -n 5" "\${GNU_BIN_DIR}/cut -d: -f1,3 /etc/passwd | head -n 5" || true
    compare_output "paste:delimiter" "\${ZIG_BIN_DIR}/seq 3 | \${ZIG_BIN_DIR}/paste -d, -s" "\${GNU_BIN_DIR}/seq 3 | \${GNU_BIN_DIR}/paste -d, -s" || true

    # head & wc
    compare_output "head:lines" "\${ZIG_BIN_DIR}/head -n 3 /etc/os-release" "\${GNU_BIN_DIR}/head -n 3 /etc/os-release" || true
    compare_output "wc:lines stdin" "\${ZIG_BIN_DIR}/wc -l < /etc/os-release" "\${GNU_BIN_DIR}/wc -l < /etc/os-release" || true
    compare_output "wc:words stdin" "\${ZIG_BIN_DIR}/wc -w < /etc/os-release" "\${GNU_BIN_DIR}/wc -w < /etc/os-release" || true
    compare_output "wc:bytes stdin" "\${ZIG_BIN_DIR}/wc -c < /etc/os-release" "\${GNU_BIN_DIR}/wc -c < /etc/os-release" || true

    # file ops: touch, stat, chmod, truncate, rm
    test_file="/tmp/coreutilz_test_parity_\$\$"
    "\${ZIG_BIN_DIR}/touch" "\${test_file}"
    compare_output "stat:size after touch" "\${ZIG_BIN_DIR}/stat -c %s \${test_file}" "\${GNU_BIN_DIR}/stat -c %s \${test_file}" || true
    "\${ZIG_BIN_DIR}/truncate" -s 1024 "\${test_file}"
    compare_output "stat:size after truncate" "\${ZIG_BIN_DIR}/stat -c %s \${test_file}" "\${GNU_BIN_DIR}/stat -c %s \${test_file}" || true
    "\${ZIG_BIN_DIR}/chmod" 0644 "\${test_file}"
    compare_output "stat:mode after chmod" "\${ZIG_BIN_DIR}/stat -c %a \${test_file}" "\${GNU_BIN_DIR}/stat -c %a \${test_file}" || true
    "\${ZIG_BIN_DIR}/rm" -f "\${test_file}"

    # directory ops: mkdir, rmdir
    test_dir="/tmp/coreutilz_test_dir_\$\$"
    "\${ZIG_BIN_DIR}/mkdir" -p "\${test_dir}/subdir"
    "\${ZIG_BIN_DIR}/rmdir" "\${test_dir}/subdir"
    "\${ZIG_BIN_DIR}/rmdir" "\${test_dir}"

    # text sorting & grouping: sort, uniq, comm, tac, shuf
    compare_output "sort:basic" "printf 'c\na\nb\n' | \${ZIG_BIN_DIR}/sort" "printf 'c\na\nb\n' | \${GNU_BIN_DIR}/sort" || true
    compare_output "sort:numeric" "printf '10\n2\n1\n' | \${ZIG_BIN_DIR}/sort -n" "printf '10\n2\n1\n' | \${GNU_BIN_DIR}/sort -n" || true
    compare_output "uniq:count" "printf 'a\na\nb\n' | \${ZIG_BIN_DIR}/uniq -c" "printf 'a\na\nb\n' | \${GNU_BIN_DIR}/uniq -c" || true
    printf 'a\nb\n' > /tmp/comm_test1_\$\$
    printf 'b\nc\n' > /tmp/comm_test2_\$\$
    compare_output "comm:basic" "\${ZIG_BIN_DIR}/comm /tmp/comm_test1_\$\$ /tmp/comm_test2_\$\$" "\${GNU_BIN_DIR}/comm /tmp/comm_test1_\$\$ /tmp/comm_test2_\$\$" || true
    rm -f /tmp/comm_test1_\$\$ /tmp/comm_test2_\$\$
    compare_output "tac:reverse" "printf 'line1\nline2\nline3\n' | \${ZIG_BIN_DIR}/tac" "printf 'line1\nline2\nline3\n' | \${GNU_BIN_DIR}/tac" || true
    compare_output "shuf:count" "\${ZIG_BIN_DIR}/seq 10 | \${ZIG_BIN_DIR}/shuf -n 3 | \${ZIG_BIN_DIR}/wc -l" "printf '3\n'" || true
fi

printf '\n==================================================\n'
printf 'CONTAINER INTEGRATION TEST SUMMARY:\n'
printf 'Total Permutations Passed: %d\n' "\${pass_count}"
printf 'Total Permutations Failed: %d\n' "\${fail_count}"
printf '==================================================\n'

if [[ \${fail_count} -gt 0 ]]; then
    exit 1
fi
exit 0
RUNNER_EOF
}

main() {
    local exit_code=0
    local -a podman_args=("--rm" "-i" "-e" "LC_ALL=C")

    # If testing localhost/coreutilz:latest, binaries are already baked in /usr/local/bin.
    # Otherwise, mount host zig-out/bin to /opt/coreutilz/bin:ro.
    if [[ "${CONTAINER_IMAGE}" != "localhost/coreutilz:latest" ]]; then
        podman_args+=("-v" "${BIN_DIR}:/opt/coreutilz/bin:ro")
    fi

    container_test_runner | podman run "${podman_args[@]}" "${CONTAINER_IMAGE}" /bin/bash || exit_code=$?
    exit "${exit_code}"
}

main "$@"
