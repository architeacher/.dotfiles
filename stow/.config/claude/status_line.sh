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
peach="250;179;135"
red="243;139;168"
text="205;214;244"
yellow="249;226;175"

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

dir_max_parts=4
memory_threshold=85
context_warning=50
context_high=75
context_critical=90
# Cells Claude Code keeps for its own spacing; tune if the line wraps or ends short.
right_margin=4
min_gap=3
field_separator=$'\x1f'

session_cwd=""
session_model=""
session_context=""
session_cost=""

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

    fields="$(printf '%s' "${input}" | jq -r --arg sep "${field_separator}" '[
        .workspace.current_dir // .cwd // "",
        .model.display_name // "",
        (.context_window.used_percentage // "" | tostring),
        (.cost.total_cost_usd // "" | tostring)
    ] | join($sep)' 2>/dev/null)" || fields=""

    IFS="${field_separator}" read -r session_cwd session_model session_context session_cost <<< "${fields}"

    : "${session_cwd:=${PWD}}"
}

format_os() {
    local icon="${icon_other_os}"

    case "$(uname -s)" in
        Darwin) icon="${icon_apple}" ;;
        Linux) icon="${icon_linux}" ;;
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

# Prints "ahead behind staged modified untracked" from `git status --porcelain=v1 -b`.
count_git_status() {
    local status_output="${1}" \
          ahead=0 \
          behind=0 \
          staged=0 \
          modified=0 \
          untracked=0 \
          line

    while IFS= read -r line; do
        [[ -z "${line}" ]] && continue

        [[ "${line}" == "##"* ]] && {
            [[ "${line}" =~ ahead\ ([0-9]+) ]] && ahead="${BASH_REMATCH[1]}"
            [[ "${line}" =~ behind\ ([0-9]+) ]] && behind="${BASH_REMATCH[1]}"
            continue
        }

        [[ "${line:0:1}" == "?" ]] && { untracked=$((untracked + 1)); continue; }
        [[ "${line:0:1}" =~ [MADRC] ]] && staged=$((staged + 1))
        [[ "${line:1:1}" == "M" ]] && modified=$((modified + 1))
    done <<< "${status_output}"

    printf '%s %s %s %s %s' "${ahead}" "${behind}" "${staged}" "${modified}" "${untracked}"
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

format_git() {
    local cwd="${1}" \
          branch \
          counts

    git -C "${cwd}" rev-parse --git-dir > /dev/null 2>&1 || return 0

    branch="$(git -C "${cwd}" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null)"

    if [[ -n "${branch}" ]]; then
        paint "${green}" "${icon_branch} ${branch}"
    else
        paint "${peach}" "${icon_commit} $(git -C "${cwd}" --no-optional-locks rev-parse --short HEAD 2>/dev/null)"
    fi

    counts="$(count_git_status "$(git -C "${cwd}" --no-optional-locks status --porcelain=v1 -b 2>/dev/null)")"

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

has_container_files() {
    local cwd="${1}" \
          file

    for file in compose.yaml docker-compose.yml docker-compose.yaml Dockerfile; do
        [[ -f "${cwd}/${file}" ]] && return 0
    done

    return 1
}

format_containers() {
    local cwd="${1}" \
          context \
          namespace

    has_container_files "${cwd}" || return 0

    context="$(docker context show 2>/dev/null)" || context="default"
    paint "${sky}" "${icon_docker} ${context} "

    [[ -f "${cwd}/Dockerfile" ]] && command -v kubectl > /dev/null 2>&1 || return 0

    context="$(kubectl config current-context 2>/dev/null)" || return 0
    [[ -n "${context}" ]] || return 0

    paint "${blue}" "☸ ${context}"

    namespace="$(kubectl config view --minify -o jsonpath='{..namespace}' 2>/dev/null)"
    [[ -n "${namespace}" && "${namespace}" != "default" ]] && paint "${text}" " (${namespace})"

    return 0
}

memory_percent() {
    [[ "$(uname -s)" != "Darwin" ]] && {
        awk '/MemTotal/ {total=$2} /MemAvailable/ {avail=$2} END {printf "%.0f", (1-avail/total)*100}' /proc/meminfo 2>/dev/null

        return 0
    }

    vm_stat | awk -v page="$(pagesize)" -v total="$(sysctl -n hw.memsize)" '
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

# Colors the context usage by how close the window is to full.
format_context() {
    local percent="${1%%.*}"

    [[ "${percent}" =~ ^[0-9]+$ ]] || return 0

    local color="${green}"

    [[ "${percent}" -ge "${context_warning}" ]] && color="${yellow}"
    [[ "${percent}" -ge "${context_high}" ]] && color="${peach}"
    [[ "${percent}" -ge "${context_critical}" ]] && color="${red}"

    paint "${color}" "${icon_context} ${percent}%"
}

format_cost() {
    local cost="${1}"

    [[ -n "${cost}" ]] || return 0

    paint "${peach}" "$(LC_NUMERIC=C printf '$%.2f' "${cost}")"
}

format_time() {
    paint "${text}" "${icon_clock} $(date +%R)"
}

# Counts terminal cells, ignoring colors. Every glyph used here is one cell wide.
visible_width() {
    printf '%s' "${1}" \
        | LC_ALL=C sed $'s/\033\\[[0-9;]*m//g' \
        | LC_ALL=C tr -d '\200-\277' \
        | wc -c \
        | tr -d ' '
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

# Joins the non-empty arguments with single spaces.
join_segments() {
    local segment \
          line=""

    for segment in "$@"; do
        [[ -n "${segment}" ]] && line="${line:+${line} }${segment}"
    done

    printf '%s' "${line}"
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
        "$(format_context "${session_context}")" \
        "$(format_cost "${session_cost}")" \
        "$(format_memory "$(memory_percent)")" \
        "$(format_time)"
}

main() {
    parse_session "$(cat)"

    align_line "$(build_left)" "$(build_right)" "${COLUMNS:-}"
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || main "$@"
