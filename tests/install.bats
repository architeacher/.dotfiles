#!/usr/bin/env bats
# Run: bats tests/install.bats
# Needs: bats-core, fd, rg on PATH (or the mocks/ dir added to PATH, see setup()).

setup() {
    TEST_DIR="$(mktemp -d)"
    ln -s "${BATS_TEST_DIRNAME}/../scripts/install.sh" "${TEST_DIR}/install.sh"
    ln -s "${BATS_TEST_DIRNAME}/../scripts/common.sh" "${TEST_DIR}/common.sh"
    ln -s "${BATS_TEST_DIRNAME}/../scripts/logger.sh" "${TEST_DIR}/logger.sh"
    ln -s "${BATS_TEST_DIRNAME}/../scripts/progress.sh" "${TEST_DIR}/progress.sh"

    # Mocks first on PATH, so fake brew/git/stow win over real ones.
    PATH="${BATS_TEST_DIRNAME}/mocks:${PATH}"

    # shellcheck disable=SC1091
    source "${TEST_DIR}/install.sh"

    # The exit handler rings, notifies and speaks: not for real during a test run.
    ring_bell() { :; }
    notify() { :; }
    speak() { :; }

    FIXTURES="${BATS_TEST_DIRNAME}/fixtures/stow"

    mkdir -p "${FIXTURES}/.home-pkg-a/scripts" \
             "${FIXTURES}/.config"/{pkg-a,pkg-b}/scripts

    # parse_args normally sets these before any other function runs;
    # tests that call a function directly need the same defaults.
    DRY_RUN="false"
    ASSUME_YES="false"
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

# --- init_defaults ---------------------------------------------------------

@test "init_defaults: fills unset variables and keeps preset ones" {
    local cases=(
        "ENV_FILE||.envrc"
        "ENV_FILE|custom.envrc|custom.envrc"
        "PROFILE||private"
        "PROFILE|work|work"
        "DISABLED_PACKAGES||"
        "DISABLED_FILE||"
        "DRY_RUN||false"
        "DRY_RUN|true|true"
        "ASSUME_YES||false"
        "ASSUME_YES|true|true"
        "LOG_LEVEL||${_log_level}"
        "LOG_LEVEL|7|7"
    ) \
        entry \
        name \
        preset \
        expected

    for entry in "${cases[@]}"; do
        IFS='|' read -r name preset expected <<< "${entry}"

        unset "${name}"
        [ -z "${preset}" ] || printf -v "${name}" '%s' "${preset}"

        init_defaults
        [ "${!name}" == "${expected}" ]
    done
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

@test "parse_args: -y sets ASSUME_YES=true, without it the question stays" {
    unset ASSUME_YES

    parse_args -n
    [ "${ASSUME_YES}" == "false" ]

    OPTIND=1
    parse_args -y
    [ "${ASSUME_YES}" == "true" ]
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
    [[ "${output}" == *"DRY RUN: stow --adopt somepath"* ]]
    [[ "${output}" != *"./somepath"* ]]
}

# stow adopts real files from the home dir. Over a tracked link that would copy a secret into the repo.
@test "refuse_adopting_over_links: stops on a real file where the repository has a link" {
    # what sits in the home dir at the link's place|expected status
    local cases=("file|1" "link|0" "nothing|0") \
        entry \
        kind

    # Stands in for git ls-files -s -z: one regular file, one link.
    git() {
        printf '100644 abc 0\tpkg/plain\0'
        printf '120000 abc 0\tpkg/.netrc\0'
    }

    for entry in "${cases[@]}"; do
        kind="${entry%%|*}"
        HOME="${TEST_DIR}/home-${kind}"
        mkdir -p "${HOME}"
        printf 'plain\n' > "${HOME}/plain"

        case "${kind}" in
            file) printf 'secret\n' > "${HOME}/.netrc" ;;
            link) ln -s /dev/null "${HOME}/.netrc" ;;
        esac

        run refuse_adopting_over_links "./pkg/"
        [ "${status}" -eq "${entry#*|}" ]
    done

    git() {
        return 1
    }

    run refuse_adopting_over_links "pkg"
    [ "${status}" -ne 0 ]
}

# `run` calls the function without errexit, like a caller that uses it in a condition.
@test "stow_config: does not stow when the link check fails" {
    git() {
        printf '120000 abc 0\tpkg/.netrc\0'
    }

    DRY_RUN="true"
    mkdir -p "${HOME}"
    printf 'secret\n' > "${HOME}/.netrc"

    run stow_config "./pkg/"
    [ "${status}" -ne 0 ]
    [[ "${output}" != *"DRY RUN: stow"* ]]
}

# --- stow/.ssh/scripts/install.sh -------------------------------------------

# Stands in for ssh-keygen: writes the key file, like a real run that overwrites.
ssh-keygen() {
    local file=""

    while [[ "$#" -gt 0 ]]; do
        [[ "${1}" == "-f" ]] && file="${2}"
        shift
    done

    printf 'new\n' > "${file}"
}

run_ssh_installer() {
    # shellcheck disable=SC1091
    ( source "${BATS_TEST_DIRNAME}/../stow/.ssh/scripts/install.sh" )
}

@test "ssh installer: overwrites an existing key only under FORCE_REINSTALL, creates a missing one" {
    # FORCE_REINSTALL|the existing key afterwards
    local cases=("true|new" "false|old") \
        entry \
        force

    GIT_EMAIL="me@example.com"
    PASS_PHRASE="secret"

    for entry in "${cases[@]}"; do
        force="${entry%%|*}"
        FORCE_REINSTALL="${force}"
        HOME="${TEST_DIR}/home-${force}"
        mkdir -p "${HOME}/.ssh"
        printf 'old\n' > "${HOME}/.ssh/id_ed25519"

        run run_ssh_installer
        [ "${status}" -eq 0 ]
        [ "$(cat "${HOME}/.ssh/id_ed25519")" == "${entry#*|}" ]
        [ "$(cat "${HOME}/.ssh/id_rsa")" == "new" ]
    done
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
    [[ "${output}" == *"-y installs without asking"* ]]
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

@test "at_exit: says the success message aloud, and only on success" {
    speak() { echo "spoken: ${1}"; }
    script_cleanup() { :; }
    DRY_RUN="false"

    run at_exit EXIT 0
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"spoken: "*"Congratulations, you can now chillax!"* ]]

    exit_status=3
    run at_exit EXIT 3
    [ "${status}" -eq 3 ]
    [[ "${output}" != *"spoken: "* ]]

    run at_exit INT 0
    [[ "${output}" != *"spoken: "* ]]
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

@test "at_exit: stops the progress line on exit and on a signal, not on ERR" {
    progress_stop() { echo "progress stopped"; }
    DRY_RUN="true"

    local cases=(
        "EXIT|0|yes"
        "INT|130|yes"
        "ERR|1|no"
    ) \
    entry signal code stopped

    for entry in "${cases[@]}"; do
        IFS='|' read -r signal code stopped <<< "${entry}"

        run at_exit "${signal}" "${code}"

        if [[ "${stopped}" == "yes" ]]; then
            [[ "${output}" == *"progress stopped"* ]] || { echo "${signal}: line not stopped"; return 1; }
        else
            [[ "${output}" != *"progress stopped"* ]] || { echo "${signal}: line stopped"; return 1; }
        fi
    done
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

@test "prepare: a decline ends the run with status 0, before the config and the directories" {
    confirm_install() { return 1; }
    create_dirs() { echo "directories created"; }
    cd "${TEST_DIR}"
    touch .envrc

    run prepare -n
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"Nothing installed."* ]]
    [[ "${output}" != *"Config:"* ]]
    [[ "${output}" != *"directories created"* ]]
}

@test "prepare: shows the logo of the repository" {
    DRY_RUN="false"
    touch "${TEST_DIR}/.envrc"
    cd "${BATS_TEST_DIRNAME}/.."

    run prepare -e "${TEST_DIR}/.envrc" -n
    [ "${status}" -eq 0 ]
    # A missing logo would make the pattern below match anything.
    [ -s assets/logo-blocks.txt ]
    [[ "${output}" == *"$(sed 's/^/  /' assets/logo-blocks.txt)"* ]]
}

@test "prepare: with -f style typo still uses default ENV_FILE" {
    DRY_RUN="false"
    cd "${TEST_DIR}"
    touch .envrc
    # Dry: prepare sets the exit handler, which would run the brew cleanup for real.
    run prepare -n
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"ENV_FILE=.envrc"* ]]
}

@test "main: is the plain sequence of prepare, install, services and wallpapers" {
    prepare() { echo "prepare $*"; }
    install() { echo "install"; }
    start_services() { echo "services"; }
    set_wallpapers() { echo "wallpapers"; }
    cd "${TEST_DIR}"
    mkdir -p wallpapers

    run main -n
    [ "${status}" -eq 0 ]
    [ "${output}" == "prepare -n${LOG_NEWLINE}install${LOG_NEWLINE}services${LOG_NEWLINE}wallpapers" ]
}

# The percentage on the progress line is the steps done over the steps announced.
@test "install: announces as many steps as it runs" {
    progress_steps() { echo "announced ${1}"; }
    progress_run() { echo "step"; }

    run install
    [ "${status}" -eq 0 ]
    [ "${lines[0]}" == "announced $(( ${#lines[@]} - 1 ))" ]
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

@test "confirm_install: asks with the install and the do-nothing choice" {
    progress_confirm() { printf '%s|' "$@"; }

    run confirm_install
    [ "${status}" -eq 0 ]
    [ "${output}" == "Choose an action:|Install .dotfiles|Do nothing|" ]
}

@test "confirm_install: -y says yes and nothing is asked" {
    progress_confirm() { echo "asked"; return 1; }
    ASSUME_YES="true"

    run confirm_install
    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "main: with -y the installation starts without a question" {
    progress_confirm() { echo "asked"; return 1; }
    install() { echo "installing"; }
    start_services() { :; }
    set_wallpapers() { :; }
    cd "${TEST_DIR}"
    touch .envrc
    mkdir -p wallpapers

    run main -n -y
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"installing"* ]]
    [[ "${output}" != *"asked"* ]]
}

@test "main: the exit handler is off while asking and on again after a yes" {
    confirm_install() { printf 'asking:'; trap -p EXIT; printf '|\n'; }
    install() { printf 'installing:'; trap -p EXIT; printf '|\n'; }
    start_services() { :; }
    set_wallpapers() { :; }
    cd "${TEST_DIR}"
    touch .envrc
    mkdir -p wallpapers

    run main -n
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"asking:|"* ]]
    [[ "${output}" == *"installing:trap -- 'at_exit EXIT "* ]]
}

@test "main: asks before it prints the config or creates a directory" {
    confirm_install() { echo "asked"; }
    create_dirs() { echo "directories created"; }
    install() { :; }
    start_services() { :; }
    set_wallpapers() { :; }
    cd "${TEST_DIR}"
    touch .envrc
    mkdir -p wallpapers

    run main -n
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"asked"*"Config:"* ]]
    [[ "${output}" != *"Config:"*"asked"* ]]
    [[ "${output}" == *"asked"*"directories created"* ]]
    [[ "${output}" != *"directories created"*"asked"* ]]
}

@test "main: installs and creates nothing and skips the exit handler when declined" {
    confirm_install() { return 1; }
    XDG_STATE_HOME="${TEST_DIR}/state"
    cd "${TEST_DIR}"
    touch .envrc
    mkdir -p wallpapers stow/.config/homebrew

    run main -n
    [ "${status}" -eq 0 ]
    [ ! -e "${XDG_STATE_HOME}" ]
    [[ "${output}" == *"Nothing installed."* ]]
    [[ "${output}" != *"Config:"* ]]
    [[ "${output}" != *"Installing Homebrew"* ]]
    [[ "${output}" != *"brew autoremove"* ]]
    [[ "${output}" != *"Congratulations"* ]]
}

@test "main: before the install starts nothing is cleaned up and a failure exits non-zero" {
    # arguments|expected status
    local cases=("-n -h|0" "-n -e ${TEST_DIR}/missing-envrc|1") \
        entry

    cd "${TEST_DIR}"

    for entry in "${cases[@]}"; do
        # shellcheck disable=SC2086 # the arguments are split on purpose.
        run main ${entry%|*}
        [ "${status}" -eq "${entry##*|}" ]
        [[ "${output}" != *"brew autoremove"* ]]
        [[ "${output}" != *"Congratulations"* ]]
    done
}
