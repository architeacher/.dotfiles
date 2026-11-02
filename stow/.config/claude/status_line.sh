#!/usr/bin/env bash

# Claude Code status line in the Starship style, Catppuccin Mocha colors.
# Reads the session JSON on stdin: https://code.claude.com/docs/en/statusline
# Standalone on purpose: logger.sh writes to stdout, which is the status line.

# No -e: a failing segment prints nothing, the rest of the line still renders.
set -Euo pipefail

# Catppuccin Mocha, as "r;g;b" for 24-bit ANSI colors.
blue="137;180;250"
green="166;227;161"
sky="137;220;235"
lavender="180;190;254"
mauve="203;166;247"
overlay="108;112;134"
peach="250;179;135"
red="243;139;168"
text="205;214;244"
yellow="249;226;175"
# Severity levels 0-3, as counted by threshold_level.
level_colors=("${green}" "${yellow}" "${peach}" "${red}")

# Nerd Font glyphs as bytes, so editors cannot strip the private-use characters.
# BMP only (U+E000-U+F8FF): JetBrains' JediTerm draws glyphs above U+FFFF at a
# different width than Claude Code assumes, which garbles the redrawn line.
icon_apple=$'\xef\x85\xb9'
icon_linux=$'\xef\x85\xbc'
icon_other_os=$'\xef\x84\x88'
icon_home=$'\xef\x80\x95'
icon_folder=$'\xef\x81\xbc'
icon_branch=$'\xef\x90\x98'
icon_commit=$'\xef\x90\x97'
icon_modified=$'\xef\x81\x80'
icon_untracked=$'\xef\x84\xa8'
icon_go=$'\xee\x98\xa7'
icon_rust=$'\xee\x9e\xa8'
icon_zig=$'\xee\x9a\xa9'
icon_lua=$'\xee\x98\xa0'
icon_node=$'\xee\x9c\x98'
icon_php=$'\xee\x9c\xbd'
icon_python=$'\xee\x88\xb5'
icon_docker=$'\xef\x8c\x88'
icon_model=$'\xef\x92\xb8'
icon_context=$'\xef\x83\xa4'
icon_memory=$'\xef\x92\xbc'
icon_clock=$'\xef\x80\x97'
icon_reset=$'\xe2\x9f\xb3'
bar_filled=$'\xe2\x97\x8f'
bar_empty=$'\xe2\x97\x8b'

dir_max_parts=4
memory_threshold=85
context_warning=50
context_high=75
context_critical=90
# Absolute token thresholds, independent of the window size.
context_tokens_warning=62000
context_tokens_high=120000
context_tokens_critical=180000
bar_width=10
seconds_per_minute=60
seconds_per_hour=3600
# Last good docker/k8s context, shown dimmed when a CLI fails.
cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/claude/status_line"
# Cells Claude Code keeps for its own spacing; tune if the line wraps or ends short.
right_margin=4
min_gap=3
rate_limit_separator="   "
field_separator=$'\x1f'
tab=$'\t'

session_cwd=""
session_model=""
session_context=""
session_cost=""
session_tokens=""
session_five_hour=""
session_five_hour_reset=""
session_seven_day=""
session_seven_day_reset=""

# Prints text in an "r;g;b" color, plain when NO_COLOR is set (no-color.org).
paint() {
    local rgb="${1}" \
          content="${2}"

    [[ -n "${NO_COLOR:-}" ]] && { printf '%s' "${content}"; return 0; }

    printf '\033[38;2;%sm%s\033[0m' "${rgb}" "${content}"
}

# Fills the session_* globals from the JSON in one jq call.
parse_session() {
    local input="${1}" \
          fields

    fields="$(printf '%s' "${input}" | jq -r --arg sep "${field_separator}" '
        def text: if . == null then "" else tostring end;
        def tokens: if . == null then "" else
            (.input_tokens // 0) + (.cache_creation_input_tokens // 0) + (.cache_read_input_tokens // 0) | tostring
        end;
        [
            .workspace.current_dir // .cwd // "",
            .model.display_name // "",
            (.context_window.used_percentage | text),
            (.cost.total_cost_usd | text),
            (.context_window.current_usage | tokens),
            (.rate_limits.five_hour.used_percentage | text),
            (.rate_limits.five_hour.resets_at | text),
            (.rate_limits.seven_day.used_percentage | text),
            (.rate_limits.seven_day.resets_at | text)
        ] | join($sep)' 2>/dev/null)" || fields=""

    IFS="${field_separator}" read -r session_cwd session_model session_context session_cost \
        session_tokens session_five_hour session_five_hour_reset \
        session_seven_day session_seven_day_reset <<< "${fields}"

    : "${session_cwd:=${PWD}}"
}

# Prints an epoch in a strftime format, now when no epoch is given; no fork on bash 4.2+.
format_epoch() {
    local format="${1}" \
          epoch="${2:--1}"

    (( BASH_VERSINFO[0] > 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 2) )) && {
        # shellcheck disable=SC2059 # the format is a strftime pattern, built on purpose.
        printf "%(${format})T" "${epoch}"
        return 0
    }

    [[ "${epoch}" == "-1" ]] && { date +"${format}"; return 0; }

    date -r "${epoch}" +"${format}" 2>/dev/null || date -d "@${epoch}" +"${format}"
}

now_epoch() {
    [[ -n "${EPOCHSECONDS:-}" ]] && { printf '%s' "${EPOCHSECONDS}"; return 0; }

    format_epoch '%s'
}

format_os() {
    local icon="${icon_other_os}"

    case "${OSTYPE:-}" in
        darwin*) icon="${icon_apple}" ;;
        linux*) icon="${icon_linux}" ;;
    esac

    paint "${blue}" "${icon}"
}

format_user() {
    paint "${lavender}" "${USER:-$(whoami)}"
}

# Replaces the home prefix with an icon and keeps only the last parts of long paths.
format_directory() {
    local dir="${1}" \
          home="${2}" \
          parts \
          count

    [[ "${dir}" == "${home}" || "${dir}" == "${home}/"* ]] && dir="${icon_home} ~${dir#"${home}"}"

    IFS='/' read -ra parts <<< "${dir}"
    count="${#parts[@]}"

    [[ "${count}" -gt "${dir_max_parts}" ]] && {
        dir="…/${parts[count - 3]}/${parts[count - 2]}/${parts[count - 1]}"
    }

    paint "${blue}" "${icon_folder} ${dir}"
}

# Prints "ahead behind staged modified untracked" from `git status --porcelain=v2 --branch`.
count_git_status() {
    local status_output="${1}" \
          drift_pattern='\+([0-9]+) -([0-9]+)' \
          ahead=0 \
          behind=0 \
          staged=0 \
          modified=0 \
          untracked=0 \
          line

    while IFS= read -r line; do
        case "${line}" in
            "# branch.ab "*)
                [[ "${line}" =~ ${drift_pattern} ]] && {
                    ahead="${BASH_REMATCH[1]}"
                    behind="${BASH_REMATCH[2]}"
                }
                ;;
            "? "*) untracked=$((untracked + 1)) ;;
            [12]" "*)
                [[ "${line:2:1}" =~ [MADRC] ]] && staged=$((staged + 1))
                [[ "${line:3:1}" == "M" ]] && modified=$((modified + 1))
                ;;
        esac
    done <<< "${status_output}"

    printf '%s %s %s %s %s' "${ahead}" "${behind}" "${staged}" "${modified}" "${untracked}"
}

# Prints the branch, or the short commit when HEAD is detached.
format_git_head() {
    local status_output="${1}" \
          head="" \
          oid="" \
          line

    while IFS= read -r line; do
        case "${line}" in
            "# branch.oid "*) oid="${line##* }" ;;
            "# branch.head "*) head="${line##* }" ;;
            "# "*) ;;
            *) break ;;
        esac
    done <<< "${status_output}"

    [[ -n "${head}" && "${head}" != "(detached)" ]] && {
        paint "${green}" "${icon_branch} ${head}"
        return 0
    }

    paint "${peach}" "${icon_commit} ${oid:0:7}"
}

format_git_counts() {
    local ahead="${1}" \
          behind="${2}" \
          staged="${3}" \
          modified="${4}" \
          untracked="${5}"

    [[ "${ahead}" -gt 0 ]] && paint "${mauve}" "⇡${ahead}"
    [[ "${behind}" -gt 0 ]] && paint "${mauve}" "⇣${behind}"
    [[ "${staged}" -gt 0 ]] && paint "${green}" "++(${staged})"
    [[ "${modified}" -gt 0 ]] && paint "${yellow}" "${icon_modified} ${modified}"
    [[ "${untracked}" -gt 0 ]] && paint "${peach}" "${icon_untracked} ${untracked}"

    return 0
}

# One git call: porcelain v2 carries the branch, the commit and the drift.
format_git() {
    local cwd="${1}" \
          status_output \
          counts

    status_output="$(git -C "${cwd}" --no-optional-locks status --porcelain=v2 --branch 2>/dev/null)" || return 0

    format_git_head "${status_output}"

    counts="$(count_git_status "${status_output}")"

    # shellcheck disable=SC2086 # counts is five space-separated numbers, split on purpose.
    counts="$(format_git_counts ${counts})"
    [[ -n "${counts}" ]] && printf ' %s' "${counts}"

    return 0
}

format_languages() {
    local cwd="${1}"

    [[ -f "${cwd}/go.mod" ]] && paint "${sky}" "${icon_go} "
    [[ -f "${cwd}/Cargo.toml" ]] && paint "${peach}" "${icon_rust} "
    [[ -f "${cwd}/build.zig" ]] && paint "${peach}" "${icon_zig} "
    [[ -f "${cwd}/.luarc.json" ]] || compgen -G "${cwd}/*.lua" > /dev/null && paint "${blue}" "${icon_lua} "
    [[ -f "${cwd}/composer.json" ]] && paint "${lavender}" "${icon_php} "
    [[ -f "${cwd}/package.json" ]] && paint "${green}" "${icon_node} "
    [[ -f "${cwd}/pyproject.toml" || -f "${cwd}/setup.py" || -f "${cwd}/requirements.txt" ]] && paint "${yellow}" "${icon_python} "

    return 0
}

# Prints a cached value; refuses symlinks so nothing planted is shown.
cache_read() {
    local file="${cache_dir}/${1}"

    [[ -f "${file}" && ! -L "${file}" ]] || return 1

    printf '%s' "$(< "${file}")"
}

# Writes a private cache file; the rename replaces a planted symlink instead of following it.
cache_write() {
    local file="${cache_dir}/${1}" \
          value="${2}"

    [[ -f "${file}" && ! -L "${file}" && "$(< "${file}")" == "${value}" ]] && return 0

    (
        umask 077
        mkdir -p "${cache_dir}" && printf '%s' "${value}" > "${file}.$$" && mv -f "${file}.$$" "${file}"
    ) 2>/dev/null

    return 0
}

# Runs a command and caches its output. Returns 2 with the cached output when the command fails.
remember() {
    local key="${1}" \
          value
    shift

    value="$("$@" 2>/dev/null)" && [[ -n "${value}" ]] && {
        cache_write "${key}" "${value}"
        printf '%s' "${value}"
        return 0
    }

    cache_read "${key}" || return 1

    return 2
}

has_container_files() {
    local cwd="${1}" \
          file

    for file in compose.yaml docker-compose.yml docker-compose.yaml Dockerfile; do
        [[ -f "${cwd}/${file}" ]] && return 0
    done

    return 1
}

format_docker() {
    local context \
          color="${sky}"

    context="$(remember docker_context docker context show)"

    case "$?" in
        0) ;;
        2) color="${overlay}" ;;
        *) context="default" ;;
    esac

    paint "${color}" "${icon_docker} ${context} "
}

# One kubectl call for the context and its namespace.
format_kubernetes() {
    local kube \
          context \
          namespace="" \
          color="${blue}" \
          namespace_color="${text}"

    kube="$(remember kube_context kubectl config view --minify --output "jsonpath={.current-context}{\"\t\"}{..namespace}")"

    case "$?" in
        0) ;;
        2) color="${overlay}"; namespace_color="${overlay}" ;;
        *) return 0 ;;
    esac

    context="${kube%%"${tab}"*}"
    [[ "${kube}" == *"${tab}"* ]] && namespace="${kube#*"${tab}"}"
    [[ -n "${context}" ]] || return 0

    paint "${color}" "☸ ${context}"
    [[ -n "${namespace}" && "${namespace}" != "default" ]] && paint "${namespace_color}" " (${namespace})"

    return 0
}

format_containers() {
    local cwd="${1}"

    has_container_files "${cwd}" || return 0

    format_docker

    [[ -f "${cwd}/Dockerfile" ]] && command -v kubectl > /dev/null 2>&1 || return 0

    format_kubernetes
}

memory_percent() {
    local page \
          total

    [[ "${OSTYPE:-}" == darwin* ]] || {
        awk '/MemTotal/ {total=$2} /MemAvailable/ {avail=$2} END {if (total) printf "%.0f", (1-avail/total)*100}' /proc/meminfo 2>/dev/null

        return 0
    }

    { read -r page; read -r total; } < <(sysctl -n hw.pagesize hw.memsize 2>/dev/null)
    [[ "${page:-}" =~ ^[0-9]+$ && "${total:-}" =~ ^[1-9][0-9]*$ ]] || return 0

    vm_stat 2>/dev/null | awk -v page="${page}" -v total="${total}" '
        /Pages active/ {gsub(/\./, ""); used += $3}
        /Pages wired/  {gsub(/\./, ""); used += $4}
        END {printf "%d", used * page * 100 / total}'
}

format_memory() {
    local percent="${1}"

    [[ "${percent}" =~ ^[0-9]+$ ]] || return 0
    [[ "${percent}" -ge "${memory_threshold}" ]] || return 0

    paint "${yellow}" "${icon_memory} ${percent}%"
}

format_model() {
    local model="${1}"

    [[ -n "${model}" ]] || return 0

    paint "${mauve}" "${icon_model} ${model}"
}

# Prints how many of the given thresholds a value has reached, 0 to 3.
threshold_level() {
    local value="${1}" \
          level=0 \
          threshold
    shift

    for threshold in "$@"; do
        [[ "${value}" -ge "${threshold}" ]] && level=$((level + 1))
    done

    printf '%s' "${level}"
}

# Picks green, yellow, peach or red by how close a percentage is to 100.
percent_color() {
    local level

    level="$(threshold_level "${1}" "${context_warning}" "${context_high}" "${context_critical}")"

    printf '%s' "${level_colors[level]}"
}

# The worse of the token and the percentage level, so neither a 1M nor a full 200K window warns late.
# tokens is empty before the first API call and right after /compact.
context_color() {
    local tokens="${1}" \
          percent="${2}" \
          token_level \
          percent_level

    [[ "${tokens}" =~ ^[0-9]+$ ]] || { percent_color "${percent}"; return 0; }

    token_level="$(threshold_level "${tokens}" "${context_tokens_warning}" "${context_tokens_high}" "${context_tokens_critical}")"
    percent_level="$(threshold_level "${percent}" "${context_warning}" "${context_high}" "${context_critical}")"

    [[ "${percent_level}" -gt "${token_level}" ]] && token_level="${percent_level}"

    printf '%s' "${level_colors[token_level]}"
}

# Shows the percentage, colored by context_color.
format_context() {
    local percent="${1%%.*}" \
          tokens="${2:-}"

    [[ "${percent}" =~ ^[0-9]+$ ]] || return 0

    paint "$(context_color "${tokens}" "${percent}")" "${icon_context} ${percent}%"
}

format_cost() {
    local cost="${1}"

    [[ -n "${cost}" ]] || return 0

    paint "${peach}" "$(LC_NUMERIC=C printf '$%.2f' "${cost}")"
}

format_time() {
    paint "${text}" "${icon_clock} $(format_epoch '%R')"
}

# Prints bar_width dots, the used share in color and the rest dimmed.
build_bar() {
    local percent="${1%%.*}" \
          color="${2}" \
          filled \
          index \
          used="" \
          free=""

    [[ "${percent}" =~ ^[0-9]+$ ]] || return 0
    [[ "${percent}" -gt 100 ]] && percent=100

    filled=$((percent * bar_width / 100))

    for ((index = 0; index < filled; index++)); do
        used="${used}${bar_filled}"
    done

    for ((index = filled; index < bar_width; index++)); do
        free="${free}${bar_empty}"
    done

    [[ -n "${used}" ]] && paint "${color}" "${used}"
    [[ -n "${free}" ]] && paint "${overlay}" "${free}"

    return 0
}

# Prints the time left until an epoch as "1h 38m", "12m" or "now".
format_countdown() {
    local reset="${1%%.*}" \
          now="${2}" \
          left

    [[ "${reset}" =~ ^[0-9]+$ ]] || return 0

    left=$((reset - now))

    [[ "${left}" -le 0 ]] && { printf 'now'; return 0; }

    [[ "${left}" -ge "${seconds_per_hour}" ]] && {
        printf '%dh %dm' $((left / seconds_per_hour)) $((left % seconds_per_hour / seconds_per_minute))
        return 0
    }

    printf '%dm' $((left / seconds_per_minute))
}

format_reset_day() {
    local reset="${1%%.*}"

    [[ "${reset}" =~ ^[0-9]+$ ]] || return 0

    format_epoch '%a %R' "${reset}"
}

# Prints "label ●●○○ 23% ⟳ reset"; nothing when the window is absent.
format_rate_limit() {
    local label="${1}" \
          percent="${2%%.*}" \
          reset="${3}" \
          color

    [[ "${percent}" =~ ^[0-9]+$ ]] || return 0

    color="$(percent_color "${percent}")"

    printf '%s %s %s' "$(paint "${text}" "${label}")" "$(build_bar "${percent}" "${color}")" "$(paint "${color}" "${percent}%")"
    [[ -n "${reset}" ]] && printf ' %s' "$(paint "${overlay}" "${icon_reset} ${reset}")"

    return 0
}

# Counts terminal cells, ignoring colors. Every glyph used here is one cell wide.
visible_width() {
    local LC_ALL=C \
          content="${1}" \
          escape_pattern=$'^(.*)\033\\[[0-9;]*m(.*)$' \
          continuation_bytes=$'[\x80-\xbf]'

    while [[ "${content}" =~ ${escape_pattern} ]]; do
        content="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    done

    content="${content//${continuation_bytes}/}"

    printf '%s' "${#content}"
}

# Pads between both sides so the right one ends at the terminal edge.
align_line() {
    local left="${1}" \
          right="${2}" \
          columns="${3}" \
          gap="${min_gap}"

    [[ "${columns}" =~ ^[0-9]+$ ]] && {
        gap=$((columns - right_margin - $(visible_width "${left}") - $(visible_width "${right}")))
        [[ "${gap}" -lt "${min_gap}" ]] && gap="${min_gap}"
    }

    printf '%s%*s%s' "${left}" "${gap}" "" "${right}"
}

# Joins the non-empty arguments after the first with the first as separator.
join_with() {
    local separator="${1}" \
          segment \
          line=""
    shift

    for segment in "$@"; do
        [[ -n "${segment}" ]] && line="${line:+${line}${separator}}${segment}"
    done

    printf '%s' "${line}"
}

join_segments() {
    join_with " " "$@"
}

build_left() {
    join_segments \
        "$(format_os)" \
        "$(format_user)" \
        " $(format_directory "${session_cwd}" "${HOME}")" \
        "$(format_languages "${session_cwd}")" \
        "$(format_containers "${session_cwd}")" \
        "$(format_git "${session_cwd}")"
}

build_right() {
    join_segments \
        "$(format_model "${session_model}")" \
        "$(format_context "${session_context}" "${session_tokens}")" \
        "$(format_cost "${session_cost}")" \
        "$(format_memory "$(memory_percent)")" \
        "$(format_time)"
}

# Only claude.ai Pro/Max sessions carry rate_limits; elsewhere this prints nothing.
build_rate_limits() {
    local now

    [[ -n "${session_five_hour}${session_seven_day}" ]] || return 0

    now="$(now_epoch)"

    join_with "${rate_limit_separator}" \
        "$(format_rate_limit "5h" "${session_five_hour}" "$(format_countdown "${session_five_hour_reset}" "${now}")")" \
        "$(format_rate_limit "7d" "${session_seven_day}" "$(format_reset_day "${session_seven_day_reset}")")"
}

main() {
    local rate_limits

    parse_session "$(cat)"

    align_line "$(build_left)" "$(build_right)" "${COLUMNS:-}"

    rate_limits="$(build_rate_limits)"
    [[ -n "${rate_limits}" ]] && printf '\n%s' "${rate_limits}"

    return 0
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || main "$@"
