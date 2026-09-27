#!/usr/bin/env bash

set -Eeuo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

cleanup_list=()
exit_status=0

create_dirs() {
    local dirs=(
        "${XDG_STATE_HOME}/zsh/sessions"
    ) \
    dir

    for dir in "${!dirs[@]}"; do
        log_debug "Creating directory: ${dirs[${dir}]}"

        mkdir -p "${dirs[${dir}]}"
    done
}

declare_global_vars() {
    : "${XDG_CONFIG_HOME:=${HOME}/.config}"
    : "${XDG_DATA_HOME:=${HOME}/.local/share}"
    : "${XDG_STATE_HOME:=${HOME}/.local/state}"

    : "${ZDOTDIR:=${XDG_CONFIG_HOME}/zsh}"

    : "${GNUPGHOME="${XDG_DATA_HOME}/gnupg"}"

    export GNUPGHOME
}

# Runs a command or logs it under dry run.
run_cmd() {
    [[ "${DRY_RUN}" == "true" ]] && { log_notice "DRY RUN: $*"; return 0; }

    "$@"
}

install_home_brew() {
    log_info "Installing Homebrew for you."

    # @see: scripts/common.sh
    [[ "${FORCE_REINSTALL}" == "true" ]] || ! is_command brew > /dev/null 2>&1 && {
        local installer
        installer="$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || abort "Failed to download Homebrew installer."
        run_cmd bash -c "${installer}"

        eval "$(/opt/homebrew/bin/brew shellenv)"
        run_cmd sudo chmod 755 /opt/homebrew/share

        return 0
    }

    log_notice "Homebrew is already installed."
}

install_home_brew_deps() {
    local brew_dir="${1:-./stow/.config/homebrew}"

    log_info "Installing brew bundle dependencies from files under ${brew_dir}."

    local files=(
        "${brew_dir}/Brewfile"
        "${brew_dir}/Brewfile-${PROFILE}"
    )

    local opts=()
    if [[ "${FORCE_REINSTALL}" == "true" ]]
    then
        opts+=("-f")
    fi

    run_cmd brew up
    run_cmd brew upgrade

    local file
    for file in "${files[@]}"; do
        if [[ "${#opts[@]}" -eq 0 ]]; then
            log_debug "Installing dependencies from ${file}"
            run_cmd brew bundle --file "${file}" || continue
        else
            log_debug "Force installing dependencies from ${file}"
            run_cmd brew bundle --file "${file}" "${opts[@]}" || continue
        fi
    done
}

install_theme() {
    local themes_url="${1}" \
          target_dir="${2}" \
          src_path="${3:-themes}"

    log_debug "Installing themes to ${target_dir}"

    [[ "${FORCE_REINSTALL}" != "true" ]] && [[ "$(ls -A "${target_dir}" 2>/dev/null)" ]] && {
        log_notice "Theme already exists"

        return 0
    }

    local temp_dir
    temp_dir="$(mktemp -d)"

    log_debug "Cloning ${themes_url}"

    run_cmd git clone --depth 1 --filter=blob:none --sparse "${themes_url}" "${temp_dir}" || {
        abort "Failed to clone the theme ${themes_url}."
    }

    cd "${temp_dir}"
        run_cmd git sparse-checkout set "${src_path}"

        mkdir -p "${target_dir}"

        log_debug "Synchronizing from ${temp_dir}/${src_path} to ${target_dir}"

        local patterns="(^\.git|\.md$|^assets$|^changelog$|^license$)"
        run_cmd rsync -arv \
              --exclude-from=<(
                    fd -HI \
                       --type d \
                       --type f \
                       --prune \
                       "${patterns}" \
                       --base-directory "${temp_dir}/${src_path}"
              ) \
             --remove-source-files "${temp_dir}/${src_path}/" "${target_dir}"
    cd -

    cleanup_list+=("${temp_dir}")
}

install_warp_themes() {
    log_info "Installing warp themes."

    install_theme "https://github.com/catppuccin/warp.git" "${HOME}/.warp/themes"
    install_theme "https://github.com/thanhsonng/rose-pine-warp.git" "${HOME}/.warp/themes" "."
}

install_zsh_fast_syntax_highlighting_themes() {
    log_info "Installing zsh_fast_syntax_highlighting themes."

    install_theme "https://github.com/catppuccin/zsh-fsh.git" "${XDG_CONFIG_HOME}/fsh"

    run_cmd zsh -c 'source ${HOME}/.zshenv && fast-theme XDG:catppuccin-macchiato 2>/dev/null' || return 0
}

install_apps_themes() {
    install_warp_themes
    install_zsh_fast_syntax_highlighting_themes
}

set_wallpapers() {
    local wallpapers_dir="${1}"

    [[ ! -d "${wallpapers_dir}" ]] && {
        log_warning "Directory ${wallpapers_dir} does not exist."

        return 0
    }

    local wallpaper
    wallpaper="$(fd -e bmp -e gif -e jpg -e jpeg -e png . "${wallpapers_dir}" | shuf -n 1)"
    [[ -f "${wallpaper}" ]] && {
#         osascript -e "tell application \"Finder\" to set desktop picture to POSIX file \"${wallpaper}\""
         run_cmd osascript -e "tell application \"System Events\" to set picture of every desktop to POSIX file \"${wallpaper}\""
         log_info "Wallpaper is set to ${wallpaper}."
    }

    run_cmd open "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"
#    osascript <<EOF
#        tell application "System Preferences"
#            activate
#            reveal pane id "com.apple.Wallpaper-Settings.extension"
#        end tell
#EOF
}

start_services() {
    run_cmd skhd --start-service
}

stow_config() {
    local dir="${1:-./stow/config}"

    case "${dir}" in
        ./*)
            # Removing the ./ from the beginning, as it would be rejected by the stow command.
            dir="${dir:2}"
        ;;
    esac

    log_info "Stowing files under ${dir} directory."

    run_cmd stow --adopt "${dir}"
}

# Todo: Remove this.
update_submodules() {
    git submodule update --init --rebase
}

usage() {
    local this="${1}"

    cat <<HELP
${this}: install Mac software for the first time
Usage: ${this} [-e] environment file path [-d] disabled packages [-f] disabled file [-n] dry run [-h] help [-l] log level [-x] verbose mode
    -e sets the environment file path.
    -d comma list of packages to skip, e.g. git,k9s.
    -f global file with one package per line to skip.
    -n dry run, prints actions without running them.
    -h to get help about the usage.
    -l sets the log priority: 2 => critical, 3 => error, 6 => info, 7 => debug.
    -x to see the executed statements.
HELP

    exit 0
}

parse_args() {
    ENV_FILE="${ENV_FILE:-.envrc}"
    PROFILE="${PROFILE:-private}"
    DISABLED_PACKAGES="${DISABLED_PACKAGES:-}"
    DISABLED_FILE="${DISABLED_FILE:-}"
    DRY_RUN="${DRY_RUN:-false}"

    local arg
    while getopts "e:l:p:d:f:nh?x" arg; do
        case "${arg}" in
            e) ENV_FILE="${OPTARG}" ;;
            l) LOG_LEVEL="${OPTARG}" ;;
            p) PROFILE="${OPTARG}" ;;
            d) DISABLED_PACKAGES="${OPTARG}" ;;
            f) DISABLED_FILE="${OPTARG}" ;;
            n) DRY_RUN="true" ;;
            h | \?) usage "${0}" ;;
            x) set -x ;;
        esac
    done
    shift $((OPTIND - 1))

    LOG_LEVEL="${LOG_LEVEL:-${_log_level}}"

    log_set_level "$((LOG_LEVEL))"
}

script_cleanup() {
    eval "$(/opt/homebrew/bin/brew shellenv)"

    run_cmd brew autoremove -v
    run_cmd brew cleanup --prune=all || log_warning "brew cleanup failed, continuing"

    [[ "${#cleanup_list[@]}" -eq 0 ]] && return 0

    local item
    for item in "${cleanup_list[@]}"; do
        log_notice "Deleting directory ${item}"
        run_cmd rm -rf "${item}"
    done
}

validate_args() {
    [[ -z "${ENV_FILE+x}" ]] && abort 'Missing -e {{ENV_FILE}}' || return 0
}

at_exit() {
    local signal="${1}" \
          ret="${2}" \
          line_no="${3:-}" \
          cmd="${4:-}" \
          stack_trace="${5:-}"

    case "${signal}" in
        ERR)
            log_error "Command failed (exit ${ret}) at line ${line_no}: ${cmd}\n Stack trace:\n${stack_trace}"
            exit_status="${ret}"

            return
        ;;
        INT | TERM | QUIT)
            log_critical "\n🦇 Bat luck out there!\n😥 Try hard next time."
            exit_status=1
        ;;
        EXIT)
            script_cleanup
            [[ "${ret}" == 0 ]] && {
                log_info "\n✨ Congratulations, you can now chillax!\n😎 May the odds be in your favour."
            }
        ;;
    esac

    run_cmd ring_bell
    run_cmd notify "Installation is finished with status: ${exit_status}"

    exit "${exit_status}"
}

print_config() {
    log_info "Config:"
    log_info "  ENV_FILE=${ENV_FILE}"
    log_info "  PROFILE=${PROFILE}"
    log_info "  LOG_LEVEL=${LOG_LEVEL}"
    log_info "  DRY_RUN=${DRY_RUN}"
    log_info "  DISABLED_PACKAGES=${DISABLED_PACKAGES:-<none>}"
    log_info "  DISABLED_FILE=${DISABLED_FILE:-./stow/.install-global-disabled}"
}

prepare() {
    # @see: scripts/common.sh
    validate_bash
    trap_with_arg at_exit ERR EXIT INT QUIT TERM

    parse_args "$@"
    validate_args

    # @see: scripts/common.sh
    include_env_vars "${ENV_FILE}"
    declare_global_vars

    create_dirs
    print_config
}

# Package name from the installer path.
package_name() {
    local input_dir="${1#./}" \
          install_script="${2#./}" \
          rel
    case "${install_script}" in
        "${input_dir}"/*)
            rel="${install_script:${#input_dir}+1}"
        ;;
        *)
            rel="${install_script}"
        ;;
    esac

    printf '%s\n' "${rel%%/*}"
}

# Package directory: whatever directly contains scripts/install.sh,
# regardless of nesting (stow/nvim, stow/.config/nvim, stow/.ssh, ...).
package_dir() {
    dirname "$(dirname "${1}")"
}

# Package name: the last path segment of its directory.
package_name() {
    local dir
    dir="$(package_dir "${1}")"

    printf '%s\n' "${dir##*/}"
}

# Prints the reason and returns 0 when disabled.
disabled_reason() {
    local pkg_dir="${1}" \
          pkg="${2}" \
          input_dir="${3}"

    local global="${DISABLED_FILE:-${input_dir}/.install-global-disabled}"

    [[ ",${DISABLED_PACKAGES}," == *",${pkg},"* ]] && { printf 'cli\n'; return 0; }
    [[ -f "${pkg_dir}/.install-local-disabled" ]] && { printf 'local\n'; return 0; }
    [[ -f "${global}" ]] && rg -qxF -- "${pkg}" "${global}" && { printf 'global\n'; return 0; }

    return 1
}

run_installers() {
     local input_dir="${1:-./stow}" \
           scripts_pattern="${2:-.*/scripts/install\.sh$}" \
           install_script \
           pkg \
           pkg_dir \
           reason \
           status

     if [[ ! -d "${input_dir}" ]]; then
         log_error "input dir '${input_dir}' not found" >&2

         return 1
     fi

     while IFS= read -r -d '' install_script; do
         pkg="$(package_name "${install_script}")"
         pkg_dir="$(package_dir "${install_script}")"

         reason="$(disabled_reason "${pkg_dir}" "${pkg}" "${input_dir}")" && {
             log_notice "Skipped (${reason}): ${pkg}"
             continue
         }

         log_info "Running: ${install_script}"

         [[ "${DRY_RUN}" == "true" ]] && { log_notice "DRY RUN: would run ${install_script}"; continue; }

         # shellcheck disable=SC1090
         ( source "${install_script}" "$@" ) && status=0 || status=$?

         [[ ${status} -eq 0 ]] && {
             log_info "OK: ${install_script}"
             continue
         }

         log_error "FAILED (${status}): ${install_script}" >&2
     done < <(fd -t f -p -H -I -0 "${scripts_pattern}" "${input_dir}")
}

install() {
    install_home_brew
    install_home_brew_deps "./stow/.config/homebrew"

    # Stowing is necessary here, for the bat theme config file.
    stow_config "./stow"

    # shellcheck disable=SC2119
    run_installers "./stow"

    install_apps_themes
}

main() {
    prepare "$@"
    install

    start_services

    set_wallpapers "$(realpath "./wallpapers")"
}

if ! is_bash_sourced; then
    main "$@"
fi
