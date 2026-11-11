#!/usr/bin/env bats
# Run: bats tests/zsh_cache.bats
# Needs: bats-core, zsh on PATH.

setup() {
    TEST_DIR="${BATS_TEST_TMPDIR}"
    CACHE_LIB="${BATS_TEST_DIRNAME}/../stow/.config/zsh/scripts/cache.zsh"
    export ZSH_INIT_CACHE_DIR="${TEST_DIR}/cache"
    export CALLS_FILE="${TEST_DIR}/calls"
    export XDG_CACHE_HOME="${TEST_DIR}/xdg"

    mkdir -p "${TEST_DIR}/bin"
    PATH="${TEST_DIR}/bin:${PATH}"

    # Fake tool: counts its runs, prints an init script that echoes its args.
    cat > "${TEST_DIR}/bin/faketool" <<'EOF'
#!/usr/bin/env bash
echo run >> "${CALLS_FILE}"
echo "echo loaded ${*}"
EOF
    cat > "${TEST_DIR}/bin/brokentool" <<'EOF'
#!/usr/bin/env bash
echo run >> "${CALLS_FILE}"
exit 1
EOF
    chmod +x "${TEST_DIR}/bin/faketool" "${TEST_DIR}/bin/brokentool"
}

# Runs zsh with only cache.zsh loaded, then the given zsh code.
run_zsh() {
    run zsh -f -c "source '${CACHE_LIB}'; ${1}"
}

calls() {
    [[ -f "${CALLS_FILE}" ]] || { echo 0; return; }
    wc -l < "${CALLS_FILE}" | tr -d ' '
}

@test "source_cached: builds the cache on first use and sources it" {
    run_zsh "source_cached fake faketool init"
    [ "${status}" -eq 0 ]
    [ "${output}" = "loaded init" ]
    [ -s "${ZSH_INIT_CACHE_DIR}/fake.zsh" ]
    [ "$(calls)" -eq 1 ]
}

@test "source_cached: reuses a fresh cache without running the tool" {
    cases=("first" "second" "third")
    for index in "${cases[@]}"; do
        run_zsh "source_cached fake faketool init"
        [ "${output}" = "loaded init" ]
    done
    [ "$(calls)" -eq 1 ]
}

@test "source_cached: rebuilds when the arguments change" {
    run_zsh "source_cached fake faketool init"
    run_zsh "source_cached fake faketool init --other"
    [ "${output}" = "loaded init --other" ]
    [ "$(calls)" -eq 2 ]
}

@test "source_cached: rebuilds when the cache file is empty" {
    run_zsh "source_cached fake faketool init"
    : > "${ZSH_INIT_CACHE_DIR}/fake.zsh"
    run_zsh "source_cached fake faketool init"
    [ "${output}" = "loaded init" ]
    [ "$(calls)" -eq 2 ]
}

@test "source_cached: does not cache output of a failing tool" {
    run_zsh "source_cached broken brokentool init"
    [ ! -e "${ZSH_INIT_CACHE_DIR}/broken.zsh" ]
    [ ! -e "${ZSH_INIT_CACHE_DIR}/broken.zsh.stamp" ]
}

@test "source_cached: skips a tool that is not installed" {
    run_zsh "source_cached missing no-such-tool-xyz init"
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
    [ ! -e "${ZSH_INIT_CACHE_DIR}/missing.zsh" ]
}

@test "clear_init_cache: removes cached scripts and stamps" {
    run_zsh "source_cached fake faketool init; clear_init_cache"
    [ ! -e "${ZSH_INIT_CACHE_DIR}/fake.zsh" ]
    [ ! -e "${ZSH_INIT_CACHE_DIR}/fake.zsh.stamp" ]
}
