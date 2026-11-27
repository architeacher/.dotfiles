#!/usr/bin/env bash

set -Eeuo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"
. "$(dirname "${BASH_SOURCE[0]}")/progress.sh"

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
    [[ "${DRY_RUN}" == "true" ]] && { log_notice "DRY RUN: ${LOG_CODE}$*${LOG_CODE}"; return 0; }

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

# Enables Touch ID for sudo via /etc/pam.d/sudo_local (macOS 14+).
enable_touch_id_sudo() {
    log_info "Enabling Touch ID for sudo."

    local template="/etc/pam.d/sudo_local.template" \
          target="/etc/pam.d/sudo_local" \
          reattach="/opt/homebrew/lib/pam/pam_reattach.so" \
          new

    [[ -f "${template}" ]] || { log_warning "Needs macOS 14+, skipping."; return 0; }

    [[ -f "${target}" ]] && {
        rg -q '^auth\s+sufficient\s+pam_tid\.so' "${target}" && {
            log_notice "Touch ID for sudo is already enabled."

            return 0
        }

        log_warning "${target} exists without pam_tid. Edit it by hand."

        return 0
    }

    new="$(mktemp)"
    cleanup_list+=("${new}")

    {
        # Needed for tmux and screen. Must come before pam_tid.
        [[ -f "${reattach}" ]] && printf 'auth       optional       %s\n' "${reattach}"
        sed 's/^#auth/auth/' "${template}"
    } > "${new}"

    log_info "Diff for ${target}:"
    diff -u /dev/null "${new}" || true

    run_cmd sudo install -m 444 -o root -g wheel "${new}" "${target}"
}

start_services() {
    run_cmd skhd --start-service
}

# stow adopts: a real file in the home dir moves over the package file. Over a tracked link
# that would put what the link points at, a decrypted secret, into this repository as plaintext.
# Fails when it cannot tell, so a caller never adopts unchecked.
refuse_adopting_over_links() {
    local package="${1#./}" \
          entry \
          file \
          path \
          blocked=0

    package="${package%/}"

    git ls-files -s -z -- "${package}" > /dev/null || {
        log_error "Cannot list the tracked files under ${package:-<empty>}, so nothing is stowed."

        return 1
    }

    while IFS= read -r -d '' entry; do
        [[ "${entry}" == 120000* ]] || continue

        file="${entry#*$'\t'}"
        path="${HOME}/${file#"${package}/"}"
        [[ -e "${path}" && ! -L "${path}" ]] || continue

        log_error "${path} is not a link, but the repository has a link there. Move it to where that link points."
        blocked=1
    done < <(git ls-files -s -z -- "${package}")

    [[ "${blocked}" -eq 0 ]]
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

    refuse_adopting_over_links "${dir}" || return 1
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
Usage: ${this} [-e] environment file path [-d] disabled packages [-f] disabled file [-n] dry run [-y] assume yes [-h] help [-l] log level [-x] verbose mode
    -d comma list of packages to skip, e.g. git,k9s.
    -e sets the environment file path.
    -f global file with one package per line to skip.
    -h to get help about the usage.
    -l sets the log priority: 2 => critical, 3 => error, 6 => info, 7 => debug.
    -n dry run, prints actions without running them.
    -p to set installation profile, e.g. private, work
    -x to see the executed statements.
    -y installs without asking for confirmation.
HELP

    exit 0
}

# Defaults every variable the installer functions read, keeping preset values,
# so entry points that skip parse_args (scripts/sel-install.sh) work under set -u.
init_defaults() {
    : "${ENV_FILE:=.envrc}"
    : "${PROFILE:=private}"
    : "${DISABLED_PACKAGES:=}"
    : "${DISABLED_FILE:=}"
    : "${DRY_RUN:=false}"
    : "${ASSUME_YES:=false}"
    : "${LOG_LEVEL:=${_log_level}}"
}

parse_args() {
    init_defaults

    local arg
    while getopts "e:l:p:d:f:nyh?x" arg; do
        case "${arg}" in
            d) DISABLED_PACKAGES="${OPTARG}" ;;
            e) ENV_FILE="${OPTARG}" ;;
            f) DISABLED_FILE="${OPTARG}" ;;
            l) LOG_LEVEL="${OPTARG}" ;;
            n) DRY_RUN="true" ;;
            p) PROFILE="${OPTARG}" ;;
            h | \?) usage "${0}" ;;
            x) set -x ;;
            y) ASSUME_YES="true" ;;
        esac
    done
    shift $((OPTIND - 1))

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
          stack_trace="${5:-}" \
          success="\n✨ Congratulations, you can now chillax!"

    case "${signal}" in
        ERR)
            # No progress_stop: under errtrace ERR also fires in a subshell, which must not end the parent's line.
            log_error "Command failed (exit ${ret}) at line ${line_no}: ${LOG_CODE}${cmd}${LOG_CODE}\n Stack trace:\n${stack_trace}"
            exit_status="${ret}"

            return
        ;;
        INT | TERM | QUIT)
            progress_stop
            log_critical "\n🦇 Bat luck out there!\n😥 Try hard next time."
            exit_status=1
        ;;
        EXIT)
            progress_stop
            script_cleanup
            [[ "${ret}" == 0 ]] && {
                log_info "${success}\n😎 May the odds be in your favour."
                speak "${success}"
            }
        ;;
    esac

    run_cmd ring_bell
    run_cmd sleep 0.8
    run_cmd notify "🎉 Installation is finished with status: ${exit_status}" "install.sh" "at_exit callback"

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

# Asks on a terminal before anything is installed, unless -y said yes already. True to go on.
confirm_install() {
    [[ "${ASSUME_YES}" != "true" ]] || return 0

    progress_confirm "Choose an action:" "Install .dotfiles" "Do nothing"
}

prepare() {
    # @see: scripts/common.sh
    validate_bash
    trap_with_arg at_exit ERR

    parse_args "$@"
    validate_args

    # @see: scripts/common.sh
    include_env_vars "${ENV_FILE}"
    declare_global_vars

    progress_banner "./assets/logo-blocks.txt" ".dotfiles Installer" "Install Mac software for the first time"

    # A no ends the run here: main stays the plain sequence of its steps.
    confirm_install || {
        log_notice "Nothing installed."

        exit 0
    }

    # Nothing is printed about the run or created before the answer is yes.
    print_config
    create_dirs

    # Only from here on is there something to clean up and a result to announce.
    trap_with_arg at_exit EXIT INT QUIT TERM
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
    # One step for each progress_run call below: the progress line shows the share that is done.
    progress_steps_of install

    progress_run "Homebrew" install_home_brew
    progress_run "Homebrew packages" install_home_brew_deps "./stow/.config/homebrew"

    # Stowing is necessary here, for the bat theme config file.
    progress_run "Stow" stow_config "./stow"

    # shellcheck disable=SC2119
    progress_run "Package installers" run_installers "./stow"

    progress_run "Themes" install_apps_themes
    progress_run "Touch ID for sudo" enable_touch_id_sudo
}

main() {
    prepare "$@"
    install

    start_services

    set_wallpapers "$(realpath "./wallpapers")"
}

is_bash_sourced || main "$@"
