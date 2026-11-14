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
# Arrays are assigned first, then made readonly: Bash 3.2 makes `readonly name=(...)` local to the
# function when this file is sourced from one.
LOG_LEVEL_TAGS=(EMERGENCY ALERT CRITICAL ERROR WARNING NOTICE INFO DEBUG)
readonly LOG_LEVEL_TAGS

readonly LOG_ESCAPE=$'\033'
readonly LOG_NEWLINE=$'\n'
readonly LOG_ATTRIBUTE_BOLD=1

# Theme. One row per level (index = level): "<prefix> <tag> <message>" palette roles, the tag is bold.
LOG_THEME_LEVELS=(
    "magenta  maroon  text"        # emergency
    "pink     red     text"        # alert
    "violet   purple  cornflower"  # critical
    "mauve    fuchsia lavender"    # error
    "orange   yellow  gold"        # warning
    "olive    lime    muted"       # notice
    "green    cyan    teal"        # info
    "sapphire sky     blue"        # debug
)
readonly LOG_THEME_LEVELS

# One palette role per syntax token kind (index = kind): string, variable, assignment, comment,
# command, flag.
LOG_THEME_SYNTAX=(yellow purple purple muted green cyan)
readonly LOG_THEME_SYNTAX

# Wrap a command line in LOG_CODE to have it highlighted as one: "DRY RUN: ${LOG_CODE}$*${LOG_CODE}".
# The character, the ASCII unit separator, does not occur in a command and is never printed.
readonly LOG_CODE=$'\x1f'

readonly LOG_SYNTAX_NAME="[A-Za-z_][A-Za-z0-9_]*"
readonly LOG_SYNTAX_FLAG="--?[A-Za-z][A-Za-z0-9_-]*"
# A word with a value, "@=value": the value is a quoted string or runs up to the next space.
readonly LOG_SYNTAX_VALUED="@=\"[^\"]*\"|@='[^']*'|@=[^[:space:]]*"

# Syntax tokens, the kinds atuin highlights: one alternative per kind, in the order of
# LOG_THEME_SYNTAX. Each is "(<boundary>)(<token>)", exactly two groups: the token is colored where
# it follows its boundary, so prose like "don't" and "PR #16" is left alone. A pattern is matched
# against one line at a time.
# string: "double" or 'single' quoted
LOG_SYNTAX_TOKENS="([[:space:]=:([])(\"[^\"]*\"|'[^']*')"
# variable: ${name}, $name, $1, $?
LOG_SYNTAX_TOKENS+="|(.)([$]\{[^}]*\}|[$]${LOG_SYNTAX_NAME}|[$][-0-9?*@#!$])"
# assignment: NAME=value
LOG_SYNTAX_TOKENS+="|([[:space:]])(${LOG_SYNTAX_VALUED//@/${LOG_SYNTAX_NAME}})"
# comment: "# text", to the end of the line
LOG_SYNTAX_TOKENS+="|([[:space:]])(#[[:blank:]].*)"
readonly LOG_SYNTAX_TOKENS

# A message is prose: the tokens, plus the text between two LOG_CODE markers, a command line.
readonly LOG_SYNTAX_PATTERN="${LOG_SYNTAX_TOKENS}|(.)(${LOG_CODE}[^${LOG_CODE}]+${LOG_CODE})"

# A command line: the tokens, plus
# command: the first word, and the first word after ; | || &&
LOG_COMMAND_PATTERN="${LOG_SYNTAX_TOKENS}|(^[[:space:]]+|[;|&][[:space:]]+)([^[:space:];|&=\"'\$#-][^[:space:];|&=]*)"
# flag: -f, --flag, --flag=value
LOG_COMMAND_PATTERN+="|([[:space:]])(${LOG_SYNTAX_VALUED//@/${LOG_SYNTAX_FLAG}}|${LOG_SYNTAX_FLAG})"
readonly LOG_COMMAND_PATTERN

# Palettes. "default" is the base and holds every role the theme names, a scheme overrides the
# roles it defines.
# The entries are read through indirect expansion in log_style.
# shellcheck disable=SC2034
{
    RGB_default_blue="82;151;248"
    RGB_default_cornflower="128;152;228"
    RGB_default_cyan="156;207;216"
    RGB_default_fuchsia="255;0;255"
    RGB_default_gold="238;195;130"
    RGB_default_green="64;160;43"
    RGB_default_lavender="230;230;250"
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

LOG_PALETTE_NAME=""

# Styles of the active palette, compiled once by log_set_palette. All are empty when colors are off.
# SGR is Select Graphic Rendition: the ANSI (ECMA-48) escape sequence ESC [ <codes> m.
LOG_SGR_RESET=""
LOG_SGR_PREFIX=()
LOG_SGR_TAG=()
LOG_SGR_MESSAGE=()
LOG_SGR_SYNTAX=()

_log_level="${LOG_LEVEL_INFO}"

# True if stderr, where the log lines go, is open and refers to a terminal.
log_stderr_is_terminal() { [[ -t 2 ]]; }

# True when log lines get colors. LOG_COLOR is always, never or auto (the default): an explicit
# always or never wins, auto colors a terminal unless NO_COLOR is set and not empty or TERM is dumb.
log_color_enabled() {
    case "${LOG_COLOR:-auto}" in
        always) return 0 ;;
        never) return 1 ;;
        auto) ;;
        *) abort "Invalid LOG_COLOR: ${LOG_COLOR}" ;;
    esac

    [[ -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]] && log_stderr_is_terminal
}

# usage: log_style <role> [attribute]  (escape sequence in REPLY, empty when colors are off)
# The role is read from the active palette, else from the default one.
# truecolor if supported, else nearest 256-color
log_style() {
    local role="${1:?role required}" \
          attribute="${2:-}" \
          scheme="RGB_${LOG_PALETTE_NAME}_${1}" \
          base="RGB_default_${1}" \
          rgb \
          color \
          red \
          green \
          blue

    rgb="${!scheme:-${!base:-}}"
    [[ -n "${rgb}" ]] || abort "Unknown color: ${role}"

    REPLY=""
    [[ -n "${LOG_SGR_RESET}" ]] || return 0

    color="2;${rgb}"
    [[ "${COLORTERM:-}" == "truecolor" || "${COLORTERM:-}" == "24bit" ]] || {
        IFS=';' read -r red green blue <<< "${rgb}"
        color="5;$(( 16 + 36 * (red * 5 / 255) + 6 * (green * 5 / 255) + (blue * 5 / 255) ))"
    }

    REPLY="${LOG_ESCAPE}[${attribute:+${attribute};}38;${color}m"
}

log_set_palette() {
    local name \
          reset="" \
          level \
          kind \
          prefix \
          tag \
          message

    # Both checks can abort, so they run before any state changes.
    name="$(tr '[:upper:]-' '[:lower:]_' <<< "${1:?palette required}")"
    compgen -v "RGB_${name}_" > /dev/null || abort "Unknown palette: ${1}"
    log_color_enabled && reset="${LOG_ESCAPE}[0m"

    LOG_PALETTE_NAME="${name}"
    LOG_SGR_RESET="${reset}"

    for (( level = 0; level < ${#LOG_THEME_LEVELS[@]}; level++ )); do
        IFS=' ' read -r prefix tag message <<< "${LOG_THEME_LEVELS[level]}"

        log_style "${prefix}"
        LOG_SGR_PREFIX[level]="${REPLY}"
        log_style "${tag}" "${LOG_ATTRIBUTE_BOLD}"
        LOG_SGR_TAG[level]="${REPLY}"
        log_style "${message}"
        LOG_SGR_MESSAGE[level]="${REPLY}"
    done

    for (( kind = 0; kind < ${#LOG_THEME_SYNTAX[@]}; kind++ )); do
        log_style "${LOG_THEME_SYNTAX[kind]}"
        LOG_SGR_SYNTAX[kind]="${REPLY}"
    done
}

log_set_level() { _log_level="${1}"; }

log_priority() {
    local priority="${1:?priority required}"

    [[ "${priority}" -le "${_log_level}" ]]
}

# usage: log_highlight_line <line> <message style> [pattern]  (result in REPLY)
# Colors every token of the pattern, the prose one by default, and returns to the message style
# after it. The text between two LOG_CODE markers is not colored as a whole: it is highlighted as a
# command line, and the markers are dropped.
log_highlight_line() {
    local rest=" ${1}" \
          style="${2}" \
          pattern="${3:-${LOG_SYNTAX_PATTERN}}" \
          text="" \
          kind \
          plain \
          token

    # ${rest} starts with one character of context that is never printed: a space at the start of
    # the line, a dot after a token, so a boundary is not found inside the token before it.
    while [[ "${rest}" =~ ${pattern} ]]; do
        for (( kind = 0; kind < ${#LOG_THEME_SYNTAX[@]}; kind++ )); do
            [[ -n "${BASH_REMATCH[kind * 2 + 2]:-}" ]] && break
        done

        token="${BASH_REMATCH[kind * 2 + 2]}"
        plain="${rest%%"${BASH_REMATCH[0]}"*}${BASH_REMATCH[kind * 2 + 1]}"
        rest=".${rest:${#plain} + ${#token}}"
        text+="${plain:1}"

        [[ "${token:0:1}" == "${LOG_CODE}" ]] && {
            log_highlight_line "${token:1:${#token} - 2}" "${style}" "${LOG_COMMAND_PATTERN}"
            text+="${REPLY}"

            continue
        }

        text+="${LOG_SGR_SYNTAX[kind]:-}${token}${style}"
    done

    REPLY="${text}${rest:1}"
}

# usage: log_highlight <text> <message style>  (result in REPLY)
# Highlights line by line: no token spans lines, and the time stays linear in the number of lines.
log_highlight() {
    local style="${2}" \
          text="" \
          line

    [[ "${1}" == *"${LOG_NEWLINE}"* ]] || {
        log_highlight_line "${1}" "${style}"

        return
    }

    while IFS= read -r line; do
        log_highlight_line "${line}" "${style}"
        text+="${REPLY}${LOG_NEWLINE}"
    done <<< "${1}"

    REPLY="${text%"${LOG_NEWLINE}"}"
}

log() {
    local log_level="${1}" \
          message \
          style

    log_priority "${log_level}" || return 0
    shift

    [[ "${log_level}" =~ ^[0-9]+$ && "${log_level}" -lt "${#LOG_LEVEL_TAGS[@]}" ]] || {
        printf "%s %s\n" "${LOG_PREFIX}" "${*}"

        return
    }

    style="${LOG_SGR_MESSAGE[log_level]:-}"
    printf -v message '%b' "${*}"
    [[ -n "${LOG_SGR_RESET}" ]] && {
        log_highlight "${message}" "${style}"
        message="${REPLY}"
    }
    message="${message//${LOG_CODE}/}"

    printf '%s  %s %s\n' \
        "${LOG_SGR_PREFIX[log_level]:-}${LOG_PREFIX}${LOG_SGR_RESET}" \
        "${LOG_SGR_TAG[log_level]:-}[${LOG_LEVEL_TAGS[log_level]}]:${LOG_SGR_RESET}" \
        "${style}${message}${LOG_SGR_RESET}" >&2
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
            log_level="${LOG_LEVEL_WARN}"
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
