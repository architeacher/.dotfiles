#!/usr/bin/env bash

set -eou pipefail

. "$(dirname "${BASH_SOURCE[0]}")/logger.sh"

SUDO=

is_command() {
    command -v "${1}" &>/dev/null
}

copy() {
    local target="${1}"

    is_command "pbcopy" && {
        printf '%s' "${target}" | pbcopy

        return
    }

    is_command "xclip" && {
        printf '%s' "${target}" | xclip -selection clipboard

        return
    }

    is_command "xsel" && {
        printf '%s' "${target}" | xsel --clipboard --input

        return
    }

    printf 'copy: no clipboard tool found\n' >&2

    return 1
}

is_bash_sourced() {
    [[ "${BASH_SOURCE[1]}" != "${0}" ]]
}

is_darwin() {
    [[ "$(uname -s)" == "Darwin" ]]
}

check_sudo() {
    [[ "$(id -u)" -eq 0 ]] && return

    is_command "sudo" && SUDO="sudo"
    [[ -z "${SUDO}" ]] && abort "This script must be executed as root."
}

get_bash_version() {
    printf '%s\n' "${BASH_VERSION%%.*}"
}

get_profile() {
    local shell_profile="${HOME}/.bash_profile"

    case "${SHELL}" in
        */bash*)
            [[ -r "${HOME}/.bash_profile" ]] && shell_profile="${HOME}/.bash_profile" || shell_profile="${HOME}/.profile"
            ;;
        */zsh*)
            shell_profile="${ZDOTDIR:-"${HOME}"}/.zprofile"
            ;;
        */fish*)
            shell_profile="${HOME}/.config/fish/config.fish"
            ;;
        *)
            shell_profile="${HOME}/.profile"
            ;;
    esac

    printf '%s\n' "${shell_profile}"
}

get_random_string() {
    is_command "uuidgen" && {
        printf '%s\n' "$(uuidgen | md5)"

        return
    }

    printf '%s\n' "$(export LC_CTYPE=C; cat </dev/urandom | tr -dc 'a-zA-Z0-9\.' | fold -w 32 | head -n 1)"
}

include_env_vars() {
    local env_file="${1:-.envrc}"

    [[ -f "${env_file}" ]] || abort "Env file not found: ${env_file}"

    set -a
    # shellcheck source=./.envrc
    . "${env_file}"
    set +a
}

ring_bell() {
    # Use the shell's audible bell.
    [[ -t 1 ]] && printf '\a' || :
}

notify() {
    local message="${1}"

    osascript -e "display notification \"${message}\""
}

url_decode() {
    local url_encoded="${1//+/ }"        # Replace + with a space.

    printf '%b' "${url_encoded//\%/\\x}" # Replace % with \x for printf.
}

validate_bash() {
    # Fail fast with a concise message when not using bash
    # Single brackets are needed here for POSIX compatibility
    # shellcheck disable=SC2292
    [[ -z "${BASH_VERSION:-}" ]] && abort "Bash is required to interpret this script."

    # Check if running in a compatible bash version.
    ((BASH_VERSINFO[0] < 3)) && abort "Bash version 3 or above is required."

    # Check if the script is run in POSIX mode.
    [[ -n "${POSIXLY_CORRECT+1}" ]] && abort "Bash must not run in POSIX compatibility mode. Please disable by unsetting POSIXLY_CORRECT and try again." || :
}

build_stack_trace() {
    local frame \
          trace=""

    for ((frame = 1; frame < ${#FUNCNAME[@]} - 1; frame++)); do
        trace+="  at ${FUNCNAME[${frame}]} (${BASH_SOURCE[${frame}]}:${BASH_LINENO[${frame}-1]})\n"
    done

    printf '%b' "${trace}"
}

trap_with_arg() {
    local handler="${1}"

    shift

    local signal
    for signal in "$@"; do
        # shellcheck disable=SC2064
        trap "${handler} ${signal} \"\$?\" \"\${LINENO}\" \"\${BASH_COMMAND}\" \"\$(caller)\" \"\$(build_stack_trace)\"" "${signal}"
    done
}
