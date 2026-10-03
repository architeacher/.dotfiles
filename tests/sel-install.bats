#!/usr/bin/env bats
# Run: bats tests/sel-install.bats
# Needs: bats-core, rg on PATH.

setup() {
    REPO_DIR="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
    TEST_DIR="$(mktemp -d)"

    # main normally creates TMP_DIR; tests call the staging functions directly.
    TMP_DIR="${TEST_DIR}/staged"
    mkdir -p "${TMP_DIR}"

    # sel-install resolves scripts/install.sh and .envrc relative to the cwd.
    ln -s "${REPO_DIR}/scripts" "${TEST_DIR}/scripts"
    printf 'PROFILE="private"\n' > "${TEST_DIR}/.envrc"
    cd "${TEST_DIR}"

    # shellcheck disable=SC1091
    source "${REPO_DIR}/scripts/sel-install.sh"

    SELECTED_ARGS=()
    unset DRY_RUN
}

teardown() {
    rm -rf "${TEST_DIR}"
}

# --- strip_main_call -------------------------------------------------------

@test "strip_main_call: replaces self-exec calls with a no-op, keeps other lines" {
    local cases=(
        'main "$@"|:'
        '    main "$@"|    :'
        'domain "$@"|domain "$@"'
        'main_helper "$@"|main_helper "$@"'
    ) \
        entry \
        input \
        expected

    for entry in "${cases[@]}"; do
        input="${entry%%|*}"
        expected="${entry#*|}"
        printf '%s\n' "${input}" > "${TEST_DIR}/case.sh"

        run strip_main_call "${TEST_DIR}/case.sh"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${expected}" ]
    done
}

# --- stage_installer -------------------------------------------------------

@test "stage_installer: staged root install.sh is valid bash" {
    local staged
    staged="$(stage_installer "scripts/install.sh")"

    run bash -n "${staged}"
    [ "${status}" -eq 0 ]
}

@test "stage_installer: staged nested installer is valid bash" {
    local staged
    staged="$(stage_installer "${REPO_DIR}/stow/.config/bat/scripts/install.sh")"

    run bash -n "${staged}"
    [ "${status}" -eq 0 ]
}

# --- run_selected_function -------------------------------------------------

@test "run_selected_function: runs a root install.sh function without parse_args" {
    SELECTED_ARGS=(true)

    run run_selected_function "run_cmd" "scripts/install.sh"
    [ "${status}" -eq 0 ]
}

@test "run_selected_function: DRY_RUN from the environment is respected" {
    DRY_RUN="true"
    SELECTED_ARGS=(false)

    run run_selected_function "run_cmd" "scripts/install.sh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"DRY RUN: false"* ]]
}
