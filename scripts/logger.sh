#!/usr/bin/env bash

set -eou pipefail

# Log levels (following complete syslog standard - higher number = less severe)
# These are readonly to prevent malicious override after initialization
readonly LOG_LEVEL_DEBUG=7      # Debug information (least severe)
readonly LOG_LEVEL_INFO=6       # Informational messages
readonly LOG_LEVEL_NOTICE=5     # Normal but significant conditions
readonly LOG_LEVEL_WARN=4       # Warning conditions
readonly LOG_LEVEL_ERROR=3      # Error conditions
readonly LOG_LEVEL_CRITICAL=2   # Critical conditions
readonly LOG_LEVEL_ALERT=1      # Action must be taken immediately
readonly LOG_LEVEL_EMERGENCY=0  # System is unusable (most severe)

readonly LOG_PREFIX="==>"
readonly LOG_LEVEL_TAGS=(emergency alert critical error warning notice info debug)

_log_level="${LOG_LEVEL_INFO}"

# string formatters, True if a go_file descriptor FD is open and refers to a terminal.
tty_escape() { :; }

[[ -t 1 ]] && tty_escape() { printf "\x1b[%sm" "${1}"; }

tty_4bit_mk() { tty_escape "${1}"; }
tty_8bit_mk() { tty_escape "38;5;${1}"; }
tty_24bit_mkbold() { tty_escape "38;2;${1}"; }
tty_4bit_mkbold() { tty_4bit_mk "${1};1"; }
tty_8bit_mkbold() { tty_8bit_mk "${1};1"; }

tty_bold="$(tty_4bit_mkbold 39)"
# shellcheck disable=SC2034
tty_underline="$(tty_escape "4;39")"
tty_reset="$(tty_escape 0)"

# unified roles, shared by all palettes. index = level (0 emergency ... 7 debug)
readonly LOG_PREFIX_COLORS=(magenta pink violet mauve orange olive green sapphire)
readonly LOG_TAG_COLORS=(maroon red purple fuchsia yellow lime cyan sky)
readonly LOG_MSG_COLORS=(text text cornflower lavender gold muted teal blue)

# shellcheck disable=SC2034
{
    RGB_default_aqua="0;255;255"
    RGB_default_blue="82;151;248"
    RGB_default_cornflower="128;152;228"
    RGB_default_cyan="156;207;216"
    RGB_default_fuchsia="255;0;255"
    RGB_default_gold="238;195;130"
    RGB_default_green="64;160;43"
    RGB_default_lavender="230;230;250"
#    RGB_default_lavender="219;118;145"
    RGB_default_lime="138;255;14"
    RGB_default_magenta="255;0;128"
    RGB_default_maroon="128;0;0"
    RGB_default_mauve="224;175;255"
    RGB_default_muted="110;106;134"
    RGB_default_olive="128;128;0"
    RGB_default_orange="254;100;11"
    RGB_default_pink="255;121;198"
    RGB_default_purple="157;0;255"
    RGB_default_red="210;15;57"
    RGB_default_sky="120;203;250"
    RGB_default_teal="62;143;176"
    RGB_default_text="202;211;245"
    RGB_default_sapphire="59;134;193"
    RGB_default_yellow="241;250;14"
    RGB_default_violet="189;147;249"

    # color maps: RGB_<palette>_<role>="R;G;B"
    # roles: red pink purple yellow cyan blue text muted
    RGB_rose_pine_moon_blue="62;143;176"      # pine
    RGB_rose_pine_moon_cyan="156;207;216"     # foam
    RGB_rose_pine_moon_muted="110;106;134"
    RGB_rose_pine_moon_pink="234;154;151"     # rose
    RGB_rose_pine_moon_purple="196;167;231"   # iris
    RGB_rose_pine_moon_red="235;111;146"      # love
    RGB_rose_pine_moon_text="224;222;244"
    RGB_rose_pine_moon_yellow="223;142;29"

    RGB_catppuccin_macchiato_blue="166;218;149"    # green
    RGB_catppuccin_macchiato_cyan="139;213;202"    # teal
    RGB_catppuccin_macchiato_muted="128;135;162"   # overlay1
    RGB_catppuccin_macchiato_pink="238;153;160"    # maroon
    RGB_catppuccin_macchiato_purple="198;160;246"  # mauve
    RGB_catppuccin_macchiato_red="237;135;150"
    RGB_catppuccin_macchiato_text="202;211;245"
    RGB_catppuccin_macchiato_yellow="234;157;52"   # gold
}

# usage: tty_rgb "R;G;B" [bold_flag]
# truecolor if supported, else nearest 256-color
tty_rgb() {
    local rgb="${1:?rgb required}" \
          bold="${2:-}" \
          r \
          g \
          b

    [[ "${COLORTERM:-}" == "truecolor" || "${COLORTERM:-}" == "24bit" ]] && {
        tty_escape "${bold:+${bold};}38;2;${rgb}"

        return
    }

    IFS=';' read -r r g b <<< "${rgb}"
    tty_escape "${bold:+${bold};}38;5;$(( 16 + 36 * (r * 5 / 255) + 6 * (g * 5 / 255) + (b * 5 / 255) ))"
}

LOG_PALETTE_NAME=""
LOG_PREFIX_RGB=()
LOG_TAG_RGB=()
LOG_MSG_RGB=()

# usage: color_rgb <name>  (uses the active palette)
color_rgb() {
    local role="${1:?color required}" \
          value \
          var \
          fallback

    var="RGB_${LOG_PALETTE_NAME}_${role}"
    fallback="RGB_default_${role}"
    value="${!var:-}"
    value="${value:-${!fallback:-}}"

    [[ -n "${value}" ]] || abort "Unknown color: ${role}"
    printf '%s' "${value}"
}

log_set_palette() {
    local name \
          index

    name="$(tr '[:upper:]-' '[:lower:]_' <<< "${1:?palette required}")"
    compgen -v "RGB_${name}_" > /dev/null || abort "Unknown palette: ${1}"
    LOG_PALETTE_NAME="${name}"

    for (( index = 0; index < ${#LOG_TAG_COLORS[@]}; index++ )); do
        LOG_PREFIX_RGB[index]="$(color_rgb "${LOG_PREFIX_COLORS[index]}")"
        LOG_TAG_RGB[index]="$(color_rgb "${LOG_TAG_COLORS[index]}")"
        LOG_MSG_RGB[index]="$(color_rgb "${LOG_MSG_COLORS[index]}")"
    done
}

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
          tag="" \
          prefix_color="" \
          msg_color="" \
          tag_color="${tty_bold}"

    log_priority "${log_level}" || return 0

    [[ "${log_level}" =~ ^[0-9]+$ ]] && (( log_level < ${#LOG_LEVEL_TAGS[@]} )) && {
        tag="${LOG_LEVEL_TAGS[${log_level}]}"
        prefix_color="$(tty_rgb "${LOG_PREFIX_RGB[${log_level}]}")"
        tag_color="$(tty_rgb "${LOG_TAG_RGB[${log_level}]}" 1)"
        msg_color="$(tty_rgb "${LOG_MSG_RGB[${log_level}]}")"
    }

    shift
    message="${*}"

    [[ "${tag}" != "" ]] && {
        display_message "${prefix_color}${LOG_PREFIX}${tty_reset} " \
            "${tag_color}[$(to_upper_case "${tag}")]:${tty_reset}" \
            "${msg_color}${message}${tty_reset}"

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
    log "${LOG_LEVEL_WARN}" "${@}"
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

log_set_palette "${LOG_PALETTE:-rose_pine_moon}"
