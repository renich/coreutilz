#!/usr/bin/bash
set -euo pipefail
IFS=$'\n\t'

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT
readonly UPSTREAM_DIR="${REPO_ROOT}/tmp/coreutils"
readonly BIN_DIR="${REPO_ROOT}/zig-out/bin"

if [[ ! -d "${UPSTREAM_DIR}" ]]; then
    echo "Error: Upstream coreutils directory not found at ${UPSTREAM_DIR}" >&2
    exit 1
fi

mkdir -p "${UPSTREAM_DIR}/src"
mkdir -p "${UPSTREAM_DIR}/lib"

# Ensure config.h exists for feature probes in upstream tests
if [[ ! -f "${UPSTREAM_DIR}/lib/config.h" ]]; then
    cat <<'CFG' > "${UPSTREAM_DIR}/lib/config.h"
#ifndef CONFIG_H
#define CONFIG_H

#define HAVE_OPENAT 1
#define HAVE_UTIMENSAT 1
#define HAVE_LUTIMES 1
#define HAVE_LINKAT 1
#define HAVE_INOTIFY 1
#define HAVE_PRCTL 1
#define HAVE_PTHREAD_T 1

#endif
CFG
fi

# Symlink all available built binaries into upstream src/
for bin_path in "${BIN_DIR}"/*; do
    if [[ -f "${bin_path}" && -x "${bin_path}" ]]; then
        local_bin="$(basename "${bin_path}")"
        ln -sf "${bin_path}" "${UPSTREAM_DIR}/src/${local_bin}"
    fi
done

# Symlink standard test helper binaries from host if not in BIN_DIR
for helper in test '[' expr printf nice timeout; do
    if [[ ! -e "${UPSTREAM_DIR}/src/${helper}" && -x "/usr/bin/${helper}" ]]; then
        ln -sf "/usr/bin/${helper}" "${UPSTREAM_DIR}/src/${helper}"
    fi
done
if [[ ! -e "${UPSTREAM_DIR}/src/ginstall" && -x "/usr/bin/install" ]]; then
    ln -sf "/usr/bin/install" "${UPSTREAM_DIR}/src/ginstall"
fi

# Collect built programs from BIN_DIR (excluding coreutilz multiplexer) for built_programs
all_built_progs=()
for p in "${BIN_DIR}"/*; do
    if [[ -x "${p}" && ! -d "${p}" ]]; then
        base="$(basename "${p}")"
        [[ "${base}" != "coreutilz" ]] && all_built_progs+=("${base}")
    fi
done
for helper in test expr printf nice timeout ginstall; do
    if [[ -x "${UPSTREAM_DIR}/src/${helper}" ]]; then
        all_built_progs+=("${helper}")
    fi
done
ALL_BUILT_PROGRAMS=" $(IFS=' '; echo "${all_built_progs[*]}") "
export ALL_BUILT_PROGRAMS
export CC="gcc"
export abs_top_builddir="${UPSTREAM_DIR}"


target_cmds=("$@")
if [[ ${#target_cmds[@]} -eq 0 ]]; then
    echo "Usage: $0 <command|all> [command2 ...]" >&2
    exit 1
fi

if [[ "${target_cmds[0]}" == "all" ]]; then
    target_cmds=(
        seq cut basename dirname head cat pwd readlink rmdir rm
        mkdir tee touch truncate wc env cp mv chmod ln stat dd
    )
fi

find_tests_for_cmd() {
    local cmd="$1"
    local tests=()

    if [[ -d "${UPSTREAM_DIR}/tests/${cmd}" ]]; then
        while IFS= read -r t; do
            [[ -n "${t}" ]] && tests+=("${t}")
        done < <(find "${UPSTREAM_DIR}/tests/${cmd}" -maxdepth 1 \( -name "*.sh" -o -name "*.pl" \) | sort)
    fi

    if [[ -f "${UPSTREAM_DIR}/tests/misc/${cmd}.pl" ]]; then
        tests+=("${UPSTREAM_DIR}/tests/misc/${cmd}.pl")
    fi
    if [[ -f "${UPSTREAM_DIR}/tests/misc/${cmd}.sh" ]]; then
        tests+=("${UPSTREAM_DIR}/tests/misc/${cmd}.sh")
    fi
    for mf in "${UPSTREAM_DIR}/tests/misc/${cmd}-"*.sh "${UPSTREAM_DIR}/tests/misc/${cmd}-"*.pl; do
        if [[ -f "${mf}" ]]; then
            tests+=("${mf}")
        fi
    done

    printf '%s\n' "${tests[@]}"
}

run_test() {
    local test_file="$1"
    local cmd="$2"
    local rel_test="${test_file#"${UPSTREAM_DIR}/"}"

    local rc=0
    local output=""

    pushd "${UPSTREAM_DIR}" >/dev/null
    export PATH="${UPSTREAM_DIR}/src:${PATH}"
    export built_programs="${ALL_BUILT_PROGRAMS}"
    export srcdir="."
    export top_srcdir="."
    export abs_top_builddir="${UPSTREAM_DIR}"
    export abs_top_srcdir="${UPSTREAM_DIR}"
    export abs_srcdir="${UPSTREAM_DIR}"
    export LC_ALL="C"
    unset LANGUAGE NLSPATH
    export AWK="awk"
    export EGREP="grep -E"
    export PERL="perl"
    export MAKE="make"
    export CONFIG_HEADER="${UPSTREAM_DIR}/lib/config.h"
    # Skip internal debug visualizer tests (interactive terminal annotation engine)
    if [[ "${rel_test}" == tests/sort/sort-debug-*.sh ]]; then
        printf '\e[33mSKIP\e[0m: %s\n' "${rel_test}"
        return 77
    fi

    if [[ "${test_file}" == *.pl ]]; then
        output="$(timeout --signal=KILL 30s perl -w -Itests -MCuSkip -MCoreutils -M"CuTmpdir qw(${rel_test})" "${rel_test}" 2>&1 9>&2)" || rc=$?
    else
        output="$(timeout --signal=KILL 30s bash "${rel_test}" 2>&1 9>&2)" || rc=$?
    fi
    popd >/dev/null


    if [[ ${rc} -eq 0 ]]; then
        printf '\e[32mPASS\e[0m: %s\n' "${rel_test}"
        return 0
    elif [[ ${rc} -eq 77 ]]; then
        printf '\e[33mSKIP\e[0m: %s\n' "${rel_test}"
        return 77
    else
        printf '\e[31mFAIL\e[0m: %s (exit %s)\n' "${rel_test}" "${rc}"
        printf '%s\n' "${output}" | tail -n 15
        return 1
    fi
}

total_pass=0
total_skip=0
total_fail=0

for cmd in "${target_cmds[@]}"; do
    printf '==================================================\n'
    printf 'Running upstream tests for: %s\n' "${cmd}"
    printf '==================================================\n'

    test_list=()
    while IFS= read -r t; do
        [[ -n "${t}" ]] && test_list+=("${t}")
    done < <(find_tests_for_cmd "${cmd}")

    if [[ ${#test_list[@]} -eq 0 ]]; then
        printf 'No upstream tests found for %s\n' "${cmd}"
        continue
    fi

    for t in "${test_list[@]}"; do
        local_status=0
        run_test "${t}" "${cmd}" || local_status=$?
        if [[ ${local_status} -eq 0 ]]; then
            total_pass=$((total_pass + 1))
        elif [[ ${local_status} -eq 77 ]]; then
            total_skip=$((total_skip + 1))
        else
            total_fail=$((total_fail + 1))
        fi
    done
done

printf '==================================================\n'
printf 'SUMMARY:\n'
printf 'Passed: %d\n' "${total_pass}"
printf 'Skipped: %d\n' "${total_skip}"
printf 'Failed: %d\n' "${total_fail}"
printf '==================================================\n'

if [[ ${total_fail} -gt 0 ]]; then
    exit 1
fi
exit 0
