#!/usr/bin/env bash

set -eou pipefail

readonly LOG_LEVEL_DEBUG=7
readonly LOG_LEVEL_INFO=6
readonly LOG_LEVEL_NOTICE=5
readonly LOG_LEVEL_WARNING=4
readonly LOG_LEVEL_ERROR=3
readonly LOG_LEVEL_CRITICAL=2
readonly LOG_LEVEL_ALERT=1
readonly LOG_LEVEL_EMERGENCY=0

readonly LOG_PREFIX="==>"

_log_level="${LOG_LEVEL_INFO}"

# string formatters, True if go_file descriptor FD is open and refers to a terminal.
tty_escape() { :; }

[[ -t 1 ]] && tty_escape() { printf "\x1b[%sm" "${1}"; }

tty_4bit_mk() { tty_escape "${1}"; }
tty_8bit_mk() { tty_escape "38;5;${1}"; }
tty_4bit_mkbold() { tty_4bit_mk "${1};1"; }
tty_8bit_mkbold() { tty_8bit_mk "${1};1"; }

tty_bold="$(tty_4bit_mkbold 39)"
# shellcheck disable=SC2034
tty_underline="$(tty_escape "4;39")"
tty_reset="$(tty_escape 0)"

# shellcheck disable=SC2034
tty_blue="$(tty_4bit_mk 34)"
tty_corn="$(tty_8bit_mk 178)"
tty_cyan="$(tty_8bit_mk 45)"
tty_green="$(tty_8bit_mk 35)"
tty_imperial="$(tty_4bit_mk 91)"
# shellcheck disable=SC2034
tty_lime="$(tty_8bit_mk 113)"
tty_magenta="$(tty_8bit_mk 170)"
# shellcheck disable=SC2034
tty_move="$(tty_4bit_mk 35)"
tty_olive="$(tty_8bit_mk 64)"
# shellcheck disable=SC2034
tty_orange="$(tty_8bit_mk 208)"
tty_pink="$(tty_8bit_mk 198)"
tty_red="$(tty_8bit_mkbold 196)"
# shellcheck disable=SC2034
tty_teal="$(tty_4bit_mk 36)"
# shellcheck disable=SC2034
tty_yellow="$(tty_8bit_mk 227)"

readonly LOG_LEVEL_TAGS=(emergency alert critical error warning notice info debug)
readonly LOG_LEVEL_COLORS=("${tty_red}" "${tty_pink}" "${tty_imperial}" "${tty_magenta}" "${tty_corn}" "${tty_olive}" "${tty_green}" "${tty_cyan}")

log_set_level() { _log_level="${1}"; }

log_priority() {
    local priority="${1:?priority required}"

    [[ "${priority}" -le "${_log_level}" ]]
}

display_message() { printf '%b\n' "${*}" >&2; }

to_pascal_case() {
    local input="${1}"

    printf "%s%s" "$(tr '[:lower:]' '[:upper:]' <<< "${input:0:1}")" "${input:1}"
}

to_upper_case() {
    local input="${1}"

    printf "%s" "$(tr '[:lower:]' '[:upper:]' <<< "${input}")"
}

log() {
    local log_level="${1}" \
          message="" \
          tty_color="${tty_bold}" \
          tag=""

    log_priority "${log_level}" || return 0

    [[ "${log_level}" =~ ^[0-9]+$ ]] && (( log_level < ${#LOG_LEVEL_COLORS[@]} )) \
        && { tty_color="${LOG_LEVEL_COLORS[${log_level}]}"; tag="${LOG_LEVEL_TAGS[${log_level}]}"; }

    shift
    message="${*}"

    [[ "${tag}" != "" ]] && {
        display_message "${tty_color}" "${LOG_PREFIX}" "[$(to_upper_case "${tag}")]:" "${message}" "${tty_reset}"

        return
    }

    printf "%s %s\n" "${LOG_PREFIX}" "${message}"
}

log_debug() {
    log "${LOG_LEVEL_DEBUG}" "${@}"
}

log_info() {
    log "${LOG_LEVEL_INFO}" "${@}"
}

log_notice() {
    log "${LOG_LEVEL_NOTICE}" "${@}"
}

log_warning() {
    log "${LOG_LEVEL_WARNING}" "${@}"
}

log_error() {
    log "${LOG_LEVEL_ERROR}" "${@}"
}

log_critical() {
    log "${LOG_LEVEL_CRITICAL}" "${@}"
}

log_alert() {
    log "${LOG_LEVEL_ALERT}" "${@}"
}

log_emergency() {
    log "${LOG_LEVEL_EMERGENCY}" "${@}"
}

# abort with an error message.
abort() {
    local message="${1}"

    log_error "${message}"
    exit 1
}

parse_log_level() {
    local log_input="${1}" \
          log_level=""

    case "${log_input}" in
        "debug")
            log_level="${LOG_LEVEL_DEBUG}"
            ;;
        "info")
            log_level="${LOG_LEVEL_INFO}"
            ;;
        "notice")
            log_level="${LOG_LEVEL_NOTICE}"
            ;;
        "warning")
            log_level="${LOG_LEVEL_WARNING}"
            ;;
        "error")
            log_level="${LOG_LEVEL_ERROR}"
            ;;
        "critical")
            log_level="${LOG_LEVEL_CRITICAL}"
            ;;
        "alert")
            log_level="${LOG_LEVEL_ALERT}"
            ;;
        "emergency")
            log_level="${LOG_LEVEL_EMERGENCY}"
            ;;
        *)
            abort "Invalid log level: ${log_input}"
            ;;
    esac

    echo "${log_level}"
}
