#!/usr/bin/env bats
# Run: bats tests/install.bats
# Needs: bats-core, fd, rg on PATH (or the mocks/ dir added to PATH, see setup()).

setup() {
    TEST_DIR="$(mktemp -d)"
    ln -s "${BATS_TEST_DIRNAME}/../scripts/install.sh" "${TEST_DIR}/install.sh"
    ln -s "${BATS_TEST_DIRNAME}/../scripts/common.sh" "${TEST_DIR}/common.sh"
    ln -s "${BATS_TEST_DIRNAME}/../scripts/logger.sh" "${TEST_DIR}/logger.sh"

    # Mocks first on PATH, so fake brew/git/stow win over real ones.
    PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"

    # shellcheck disable=SC1091
    source "${TEST_DIR}/install.sh"

    FIXTURES="${BATS_TEST_DIRNAME}/fixtures/stow"

    mkdir -p "${FIXTURES}/.home-pkg-a/scripts" \
             "${FIXTURES}/.config"/{pkg-a,pkg-b}/scripts

    # parse_args normally sets these before any other function runs;
    # tests that call a function directly need the same defaults.
    DRY_RUN="false"
    DISABLED_PACKAGES=""
    DISABLED_FILE=""
    XDG_CONFIG_HOME="${TEST_DIR}/config"
    HOME="${TEST_DIR}/home"
    FORCE_REINSTALL="false"
    PROFILE="private"
    ENV_FILE=".envrc"
}

teardown() {
    rm -rf "${TEST_DIR}" "${FIXTURES}"
}

# --- package_dir / package_name --------------------------------------------
# Fixtures: stow/.home-pkg-a (top level), stow/.config/pkg-a, stow/.config/pkg-b
# (nested one level deeper under a non-package container dir).

@test "package_dir: top-level package resolves directly under input_dir" {
    run package_dir "./stow/.home-pkg-a/scripts/install.sh"
    [ "${status}" -eq 0 ]
    [ "${output}" == "./stow/.home-pkg-a" ]
}

@test "package_dir: package nested under .config keeps the container in the path" {
    run package_dir "./stow/.config/pkg-a/scripts/install.sh"
    [ "${status}" -eq 0 ]
    [ "${output}" == "./stow/.config/pkg-a" ]
}

@test "package_dir: works with an already-clean (no ./) path" {
    run package_dir "stow/.config/pkg-b/scripts/install.sh"
    [ "${output}" == "stow/.config/pkg-b" ]
}

@test "package_name: top-level package" {
    run package_name "./stow/.home-pkg-a/scripts/install.sh"
    [ "${status}" -eq 0 ]
    [ "${output}" == ".home-pkg-a" ]
}

@test "package_name: package nested under .config" {
    run package_name "./stow/.config/pkg-a/scripts/install.sh"
    [ "${status}" -eq 0 ]
    [ "${output}" == "pkg-a" ]
}

@test "package_name: nesting depth doesn't matter, only the immediate parent does" {
    run package_name "./stow/.config/pkg-b/scripts/install.sh"
    [ "${output}" == "pkg-b" ]
}

# --- disabled_reason ----------------------------------------------------
# Takes the package's own directory now, not input_dir + name.

@test "disabled_reason: cli list disables package" {
    DISABLED_PACKAGES="git,k9s"
    DISABLED_FILE=""
    run disabled_reason "${FIXTURES}/.home-pkg-a" "git" "${FIXTURES}"
    [ "${status}" -eq 0 ]
    [ "${output}" == "cli" ]
}

@test "disabled_reason: cli list does not match partial name" {
    DISABLED_PACKAGES="git"
    run disabled_reason "${FIXTURES}/.home-pkg-a" "nv" "${FIXTURES}"
    [ "${status}" -eq 1 ]
}

@test "disabled_reason: local marker file disables a top-level package" {
    DISABLED_PACKAGES=""
    DISABLED_FILE=""
    touch "${FIXTURES}/.home-pkg-a/.install-local-disabled"
    run disabled_reason "${FIXTURES}/.home-pkg-a" ".home-pkg-a" "${FIXTURES}"
    rm -f "${FIXTURES}/.home-pkg-a/.install-local-disabled"
    [ "${status}" -eq 0 ]
    [ "${output}" == "local" ]
}

@test "disabled_reason: local marker file disables a package nested under .config" {
    DISABLED_PACKAGES=""
    DISABLED_FILE=""
    touch "${FIXTURES}/.config/pkg-a/.install-local-disabled"
    run disabled_reason "${FIXTURES}/.config/pkg-a" "pkg-a" "${FIXTURES}"
    rm -f "${FIXTURES}/.config/pkg-a/.install-local-disabled"
    [ "${status}" -eq 0 ]
    [ "${output}" == "local" ]
}

@test "disabled_reason: global file disables package" {
    DISABLED_PACKAGES=""
    DISABLED_FILE="${TEST_DIR}/global-list"
    printf 'pkg-b\n' > "${DISABLED_FILE}"
    run disabled_reason "${FIXTURES}/.config/pkg-b" "pkg-b" "${FIXTURES}"
    [ "${status}" -eq 0 ]
    [ "${output}" == "global" ]
}

@test "disabled_reason: global file exact match only, no substring" {
    DISABLED_PACKAGES=""
    DISABLED_FILE="${TEST_DIR}/global-list"
    printf 'pkg\n' > "${DISABLED_FILE}"
    run disabled_reason "${FIXTURES}/.config/pkg-b" "pkg-b" "${FIXTURES}"
    [ "${status}" -eq 1 ]
}

@test "disabled_reason: with DISABLED_FILE unset, default resolves inside input_dir, not cwd" {
    DISABLED_PACKAGES=""
    DISABLED_FILE=""
    printf 'pkg-b\n' > "${FIXTURES}/.install-global-disabled"
    run disabled_reason "${FIXTURES}/.config/pkg-b" "pkg-b" "${FIXTURES}"
    rm -f "${FIXTURES}/.install-global-disabled"
    [ "${status}" -eq 0 ]
    [ "${output}" == "global" ]
}

@test "disabled_reason: a real global file sitting in cwd is NOT picked up by default" {
    DISABLED_PACKAGES=""
    DISABLED_FILE=""
    cd "${TEST_DIR}"
    printf 'pkg-b\n' > ".install-global-disabled"
    run disabled_reason "${FIXTURES}/.config/pkg-b" "pkg-b" "${FIXTURES}"
    [ "${status}" -eq 1 ]
}

@test "disabled_reason: comma-separated names on one line in the global file do not match" {
    DISABLED_PACKAGES=""
    DISABLED_FILE="${TEST_DIR}/global-list"
    printf 'pkg-a,pkg-b\n' > "${DISABLED_FILE}"
    run disabled_reason "${FIXTURES}/.config/pkg-b" "pkg-b" "${FIXTURES}"
    [ "${status}" -eq 1 ]
}

@test "disabled_reason: enabled package returns 1, empty output" {
    DISABLED_PACKAGES=""
    DISABLED_FILE="${TEST_DIR}/does-not-exist"
    run disabled_reason "${FIXTURES}/.home-pkg-a" ".home-pkg-a" "${FIXTURES}"
    [ "${status}" -eq 1 ]
    [ -z "${output}" ]
}

# --- run() ----------------------------------------------------------------

@test "run_cmd: executes the command when DRY_RUN is false" {
    DRY_RUN="false"
    run run_cmd echo "hello"
    [ "${status}" -eq 0 ]
    [ "${output}" == "hello" ]
}

@test "run_cmd: only logs when DRY_RUN is true, does not execute" {
    DRY_RUN="true"
    marker="${TEST_DIR}/should-not-exist"
    run run_cmd touch "${marker}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"DRY RUN: touch ${marker}"* ]]
    [ ! -f "${marker}" ]
}

@test "run_cmd: propagates failure exit code when not dry run" {
    DRY_RUN="false"
    run run_cmd false
    [ "${status}" -ne 0 ]
}

# --- create_dirs / declare_global_vars ------------------------------------

@test "declare_global_vars: sets XDG defaults when unset" {
    unset XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME ZDOTDIR GNUPGHOME
    HOME="${TEST_DIR}/home"
    declare_global_vars
    [ "${XDG_CONFIG_HOME}" == "${HOME}/.config" ]
    [ "${XDG_STATE_HOME}" == "${HOME}/.local/state" ]
    [ "${ZDOTDIR}" == "${XDG_CONFIG_HOME}/zsh" ]
}

@test "declare_global_vars: respects pre-set XDG_CONFIG_HOME" {
    XDG_CONFIG_HOME="/custom/config"
    declare_global_vars
    [ "${XDG_CONFIG_HOME}" == "/custom/config" ]
}

@test "create_dirs: creates the zsh sessions directory" {
    XDG_STATE_HOME="${TEST_DIR}/state"
    create_dirs
    [ -d "${XDG_STATE_HOME}/zsh/sessions" ]
}

# --- parse_args / validate_args --------------------------------------------

@test "parse_args: defaults ENV_FILE and PROFILE" {
    parse_args
    [ "${ENV_FILE}" == ".envrc" ]
    [ "${PROFILE}" == "private" ]
    [ "${DRY_RUN}" == "false" ]
}

@test "parse_args: -n sets DRY_RUN=true" {
    parse_args -n
    [ "${DRY_RUN}" == "true" ]
}

@test "parse_args: -d sets DISABLED_PACKAGES" {
    parse_args -d "git,k9s"
    [ "${DISABLED_PACKAGES}" == "git,k9s" ]
}

@test "parse_args: -e overrides ENV_FILE" {
    parse_args -e "custom.envrc"
    [ "${ENV_FILE}" == "custom.envrc" ]
}

@test "validate_args: passes when ENV_FILE is set" {
    ENV_FILE=".envrc"
    run validate_args
    [ "${status}" -eq 0 ]
}

@test "validate_args: aborts when ENV_FILE is unset" {
    unset ENV_FILE
    run validate_args
    [ "${status}" -ne 0 ]
}

# --- print_config (smoke test: no crash, key lines present) ---------------

@test "print_config: prints resolved settings" {
    ENV_FILE=".envrc"; PROFILE="private"; LOG_LEVEL="6"
    DRY_RUN="true"; DISABLED_PACKAGES="git"; DISABLED_FILE=""
    run print_config
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"DRY_RUN=true"* ]]
    [[ "${output}" == *"DISABLED_PACKAGES=git"* ]]
}

# --- run_installers (integration, uses fixture packages + mocked fd) ------

@test "run_installers: runs enabled packages, skips disabled ones, across nesting depths" {
    DISABLED_PACKAGES="pkg-b"
    DISABLED_FILE=""
    cat > "${FIXTURES}/.home-pkg-a/scripts/install.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "ran .home-pkg-a"
SCRIPT
    cat > "${FIXTURES}/.config/pkg-a/scripts/install.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "ran pkg-a"
SCRIPT
    cat > "${FIXTURES}/.config/pkg-b/scripts/install.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "ran pkg-b"
SCRIPT
    chmod +x "${FIXTURES}/.home-pkg-a/scripts/install.sh" \
        "${FIXTURES}/.config/pkg-a/scripts/install.sh" \
        "${FIXTURES}/.config/pkg-b/scripts/install.sh"

    run run_installers "${FIXTURES}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"ran .home-pkg-a"* ]]
    [[ "${output}" == *"ran pkg-a"* ]]
    [[ "${output}" != *"ran pkg-b"* ]]
    [[ "${output}" == *"Skipped (cli): pkg-b"* ]]
}

@test "run_installers: missing input dir returns 1" {
    run run_installers "${TEST_DIR}/does-not-exist"
    [ "${status}" -eq 1 ]
}

@test "run_installers: resolves and can disable a package nested under .config" {
    DISABLED_PACKAGES="homebrew"
    DISABLED_FILE=""
    mkdir -p "${FIXTURES}/.config/homebrew/scripts"
    cat > "${FIXTURES}/.config/homebrew/scripts/install.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "ran homebrew"
SCRIPT
    chmod +x "${FIXTURES}/.config/homebrew/scripts/install.sh"

    run run_installers "${FIXTURES}"
    rm -rf "${FIXTURES}/.config/homebrew"
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"ran homebrew"* ]]
    [[ "${output}" == *"Skipped (cli): homebrew"* ]]
}

@test "run_installers: dry run does not execute installers" {
    DRY_RUN="true"
    DISABLED_PACKAGES=""
    cat > "${FIXTURES}/.config/pkg-a/scripts/install.sh" <<'SCRIPT'
#!/usr/bin/env bash
echo "ran pkg-a"
SCRIPT
    chmod +x "${FIXTURES}/.config/pkg-a/scripts/install.sh"

    run run_installers "${FIXTURES}"
    [[ "${output}" != *"ran pkg-a"* ]]
    [[ "${output}" == *"DRY RUN: would run"* ]]
}

# --- install_home_brew / install_home_brew_deps (mocked, dry run) --------

@test "install_home_brew: skips install when brew already present" {
    FORCE_REINSTALL="false"
    run install_home_brew
    [[ "${output}" == *"already installed"* ]]
}

@test "install_home_brew_deps: dry run logs bundle command, no real brew call" {
    DRY_RUN="true"
    FORCE_REINSTALL="false"
    mkdir -p "${TEST_DIR}/homebrew"
    touch "${TEST_DIR}/homebrew/Brewfile"
    PROFILE="private"
    run install_home_brew_deps "${TEST_DIR}/homebrew"
    [[ "${output}" == *"DRY RUN: brew up"* ]]
    [[ "${output}" == *"DRY RUN: brew bundle --file"* ]]
}

# --- install_theme (mocked git/rsync via mocks/, dry run) ------------------

@test "install_theme: skips when target dir already has files and not forcing" {
    FORCE_REINSTALL="false"
    target="${TEST_DIR}/existing-theme"
    mkdir -p "${target}"
    touch "${target}/file"
    run install_theme "https://example.com/theme.git" "${target}"
    [[ "${output}" == *"Theme already exists"* ]]
}

@test "install_theme: dry run does not clone" {
    DRY_RUN="true"
    FORCE_REINSTALL="false"
    target="${TEST_DIR}/new-theme"
    run install_theme "https://example.com/theme.git" "${target}"
    [[ "${output}" == *"DRY RUN: git clone"* ]]
}

# --- stow_config ------------------------------------------------------------

@test "stow_config: strips leading ./ from dir before stowing" {
    DRY_RUN="true"
    run stow_config "./somepath"
    [[ "${output}" == *"DRY RUN: stow --adopt"*"somepath"* ]]
    [[ "${output}" != *"./somepath"* ]]
}

# --- start_services / script_cleanup (dry run smoke tests) ----------------

@test "start_services: dry run logs skhd call" {
    DRY_RUN="true"
    run start_services
    [[ "${output}" == *"DRY RUN: skhd --start-service"* ]]
}

@test "script_cleanup: dry run logs brew cleanup, still deletes cleanup_list note" {
    DRY_RUN="true"
    cleanup_list=("${TEST_DIR}/tmp-clone")
    mkdir -p "${cleanup_list[0]}"
    run script_cleanup
    [[ "${output}" == *"DRY RUN: brew autoremove"* ]]
    [[ "${output}" == *"DRY RUN: rm -rf ${cleanup_list[0]}"* ]]
}

@test "script_cleanup: no-op when cleanup_list is empty" {
    DRY_RUN="false"
    cleanup_list=()
    run script_cleanup
    [ "${status}" -eq 0 ]
}

# --- set_wallpapers ---------------------------------------------------------

@test "set_wallpapers: warns and returns 0 when dir missing" {
    run set_wallpapers "${TEST_DIR}/no-such-dir"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"does not exist"* ]]
}

# --- usage -------------------------------------------------------------

@test "usage: prints help and exits 0" {
    run usage "install.sh"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Usage: install.sh"* ]]
    [[ "${output}" == *"-n dry run"* ]]
}

# --- install_warp_themes / install_zsh_fast_syntax_highlighting_themes / install_apps_themes ---

@test "install_warp_themes: dry run logs both clones, no real git call" {
    DRY_RUN="true"
    FORCE_REINSTALL="false"
    run install_warp_themes
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"DRY RUN: git clone --depth 1 --filter=blob:none --sparse https://github.com/catppuccin/warp.git"* ]]
    [[ "${output}" == *"DRY RUN: git clone --depth 1 --filter=blob:none --sparse https://github.com/thanhsonng/rose-pine-warp.git"* ]]
}

@test "install_zsh_fast_syntax_highlighting_themes: dry run logs clone and fast-theme, no real zsh call" {
    DRY_RUN="true"
    FORCE_REINSTALL="false"
    run install_zsh_fast_syntax_highlighting_themes
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"DRY RUN: git clone"*"catppuccin/zsh-fsh.git"* ]]
    [[ "${output}" == *"DRY RUN: zsh -c"* ]]
}

@test "install_apps_themes: runs both theme installers" {
    DRY_RUN="true"
    FORCE_REINSTALL="false"
    run install_apps_themes
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"catppuccin/warp.git"* ]]
    [[ "${output}" == *"catppuccin/zsh-fsh.git"* ]]
}

# --- update_submodules -----------------------------------------------------

@test "update_submodules: calls git submodule update (mocked)" {
    run update_submodules
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"[mock git] submodule update --init --rebase"* ]]
}

# --- set_wallpapers: happy path with a real file ---------------------------

@test "set_wallpapers: picks a file and calls osascript + open (dry run)" {
    DRY_RUN="true"
    wp_dir="${TEST_DIR}/wallpapers"
    mkdir -p "${wp_dir}"
    touch "${wp_dir}/a.png"
    run set_wallpapers "${wp_dir}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"DRY RUN: osascript"* ]]
    [[ "${output}" == *"DRY RUN: open"* ]]
}

# --- at_exit ----------------------------------------------------------------

@test "at_exit: ERR sets exit_status and logs the failing command" {
    exit_status=0
    run at_exit ERR 42 13 "some_cmd arg" "trace-line"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Command failed (exit 42) at line 13: some_cmd arg"* ]]
}

@test "at_exit: INT sets exit_status to 1 and logs a message" {
    run at_exit INT 0
    [ "${status}" -eq 1 ]
    [[ "${output}" == *"Try hard next time"* ]]
}

@test "at_exit: TERM behaves the same as INT" {
    run at_exit TERM 0
    [ "${status}" -eq 1 ]
}

@test "at_exit: EXIT with ret=0 runs cleanup and prints success" {
    DRY_RUN="true"
    cleanup_list=()
    run at_exit EXIT 0
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Congratulations"* ]]
}

@test "at_exit: EXIT with nonzero ret skips the success message" {
    DRY_RUN="true"
    cleanup_list=()
    exit_status=3
    run at_exit EXIT 3
    [ "${status}" -eq 3 ]
    [[ "${output}" != *"Congratulations"* ]]
}

# --- prepare / install / main (full-flow smoke tests, dry run + mocks) ----

@test "prepare: parses args, validates, and prints config without exiting" {
    DRY_RUN="false"
    cd "${TEST_DIR}"
    touch .envrc

    run prepare -e ".envrc" -n
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"DRY_RUN=true"* ]]
}

@test "prepare: with -f style typo still uses default ENV_FILE" {
    DRY_RUN="false"
    cd "${TEST_DIR}"
    touch .envrc
    run prepare
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"ENV_FILE=.envrc"* ]]
}

@test "install: runs brew, stow, run_installers and themes in sequence (dry run)" {
    DRY_RUN="true"
    cd "${TEST_DIR}"
    mkdir -p stow/.config/homebrew
    run install
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"already installed"* ]]
    [[ "${output}" == *"DRY RUN: stow --adopt"* ]]
    [[ "${output}" == *"DRY RUN: git clone"* ]]
}

@test "main: full flow with -n does not touch the real system" {
    cd "${TEST_DIR}"
    touch .envrc
    mkdir -p wallpapers stow/.config/homebrew
    run main -n
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Config:"* ]]
    [[ "${output}" == *"DRY_RUN=true"* ]]
}
