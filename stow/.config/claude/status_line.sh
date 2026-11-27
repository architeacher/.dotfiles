#!/usr/bin/env bash

# Claude Code status line in the Starship style, Catppuccin Mocha colors.
# Reads the session JSON on stdin: https://code.claude.com/docs/en/statusline
# Standalone on purpose: logger.sh writes to stdout, which is the status line.

# No -e: a failing segment prints nothing, the rest of the line still renders.
set -Euo pipefail

# Catppuccin Mocha, as "r;g;b" for 24-bit ANSI colors.
blue="137;180;250"
crust="17;17;27"
green="166;227;161"
sky="137;220;235"
lavender="180;190;254"
mauve="203;166;247"
overlay="108;112;134"
peach="250;179;135"
red="243;139;168"
teal="148;226;213"
text="205;214;244"
yellow="249;226;175"
# Block backgrounds, not part of the palette.
navy="35;62;90"
steel="45;100;130"
# Colors of the reference style: Tailwind cyan-300, teal-400, sky-800 and sky-100, and azure for the
# 7d percentage.
cyan="103;232;249"
aqua="45;212;191"
azure="37;139;210"
ocean="7;89;133"
ice="224;242;254"
# Other blocks of the reference style: salmon on umber for the session time, pearl on royal for the model,
# orchid on dusk for the clock.
umber="54;38;30"
salmon="218;161;143"
royal="38;76;185"
pearl="245;243;255"
dusk="33;32;46"
orchid="216;112;202"
# Effort levels of the reference style: chalk on magenta for max, white on indigo for xhigh,
# white on coral for high, black on butter for medium, ice on ocean for low.
magenta="215;0;175"
indigo="94;99;234"
chalk="238;238;236"
butter="252;233;79"
black="0;0;0"
coral="230;113;78"
white="255;255;255"
# Severity levels 1-3, as counted by threshold_level. At level 0 a meter shows its own color.
warning_colors=("${yellow}" "${peach}" "${red}")
# SGR attributes for paint and block.
bold="1"
italic="3"

# Nerd Font glyphs as bytes, so editors cannot strip the private-use characters.
# BMP only (U+E000-U+F8FF): JetBrains' JediTerm draws the private-use glyphs above U+FFFF
# at a different width than Claude Code assumes, which garbles the redrawn line.
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
icon_memory=$'\xef\x92\xbc'
icon_clock=$'\xef\x80\x97'
icon_reset=$'\xe2\x9f\xb3'
# Emoji are two cells wide: visible_width counts them through wide_glyphs.
icon_duration=$'\xe2\x8c\x9b'
icon_model=$'\xf0\x9f\xa4\x96'
icon_effort=$'\xf0\x9f\x92\xaa'
icon_context=$'\xf0\x9f\xa7\xa0'
icon_cost=$'\xf0\x9f\x92\xb0'
wide_glyphs=("${icon_duration}" "${icon_model}" "${icon_effort}" "${icon_context}" "${icon_cost}")
# Meter glyphs: dots for the 5h window, waves for the 7d window, slabs for the context.
dot_filled=$'\xe2\x97\x8f'
dot_empty=$'\xe2\x97\x8b'
wave_filled=$'\xe2\x89\x8b'
wave_empty=$'\xc2\xb7'
slab_filled=$'\xe2\x96\xb0'
slab_empty=$'\xe2\x96\xb1'

dir_max_parts=3
branch_max_length=18
memory_threshold=85
context_warning=50
context_high=75
context_critical=90
tokens_per_kilo=1000
tokens_per_mega_tenth=100000
# The whole window in tenths of a percent: format_percent counts the share in them.
tenths_per_whole=1000
bar_width=10
milliseconds_per_second=1000
seconds_per_minute=60
seconds_per_hour=3600
# Last good docker/k8s context, shown dimmed when a CLI fails.
cache_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/claude/status_line"
# Cells Claude Code keeps for its own spacing; tune if the line wraps or ends short.
right_margin=4
min_gap=3
rate_limit_separator="   "
cost_separator=" · "
field_separator=$'\x1f'
tab=$'\t'

session_cwd=""
session_model=""
session_context=""
session_cost=""
session_duration=""
session_tokens=""
session_window=""
session_five_hour=""
session_five_hour_reset=""
session_seven_day=""
session_seven_day_reset=""
session_effort=""

# Prints text in an "r;g;b" color, plain when NO_COLOR is set (no-color.org).
# Optional SGR attributes, such as "${bold}", go ahead of the color in the same sequence.
paint() {
    local rgb="${1}" \
          content="${2}" \
          attributes="${3:-}"

    [[ -n "${NO_COLOR:-}" ]] && { printf '%s' "${content}"; return 0; }

    printf '\033[%s38;2;%sm%s\033[0m' "${attributes:+${attributes};}" "${rgb}" "${content}"
}

# Prints " text " on a solid "r;g;b" background. NO_COLOR keeps the padding, so the text stays the same.
block() {
    local background="${1}" \
          foreground="${2}" \
          attributes="${3}" \
          content="${4}"

    paint "${foreground}" " ${content} " "${attributes:+${attributes};}48;2;${background}"
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
            (.cost.total_duration_ms | text),
            (.context_window.current_usage | tokens),
            (.context_window.context_window_size | text),
            (.rate_limits.five_hour.used_percentage | text),
            (.rate_limits.five_hour.resets_at | text),
            (.rate_limits.seven_day.used_percentage | text),
            (.rate_limits.seven_day.resets_at | text),
            .effort.level // ""
        ] | join($sep)' 2>/dev/null)" || fields=""

    IFS="${field_separator}" read -r session_cwd session_model session_context session_cost \
        session_duration session_tokens session_window session_five_hour session_five_hour_reset \
        session_seven_day session_seven_day_reset session_effort <<< "${fields}"

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

    printf '%s' "${icon}"
}

format_user() {
    block "${navy}" "${text}" "${bold}" "$(format_os) ${USER:-$(whoami)}"
}

# Replaces the home prefix with an icon and keeps only the last parts of a path with more than dir_max_parts.
format_directory() {
    local dir="${1}" \
          home="${2}" \
          parts \
          count

    [[ "${dir}" == "${home}" || "${dir}" == "${home}/"* ]] && dir="${icon_home} ~${dir#"${home}"}"

    # The home counts as a part, the root does not: "/a/b/c" has three.
    IFS='/' read -ra parts <<< "${dir#/}"
    count="${#parts[@]}"

    [[ "${count}" -gt "${dir_max_parts}" ]] && {
        dir="…/${parts[count - 3]}/${parts[count - 2]}/${parts[count - 1]}"
    }

    block "${steel}" "${text}" "" "${icon_folder} ${dir}"
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
# A branch longer than branch_max_length is cut and ends with "…", so it never gets wider than that.
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
        [[ "${#head}" -gt "${branch_max_length}" ]] && head="${head:0:branch_max_length - 1}…"
        block "${teal}" "${crust}" "${italic}" "${icon_branch} ${head}"
        return 0
    }

    block "${peach}" "${crust}" "${italic}" "${icon_commit} ${oid:0:7}"
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

    block "${royal}" "${pearl}" "${bold}" "${icon_model} ${model}"
}

# Models without the effort parameter send no level, so this prints nothing for them.
# Each level has its own colors; low and any unknown level keep ice on ocean.
format_effort() {
    local effort="${1}" \
          background="${ocean}" \
          foreground="${ice}"

    [[ -n "${effort}" ]] || return 0

    case "${effort}" in
        max) background="${magenta}"; foreground="${chalk}" ;;
        xhigh) background="${indigo}"; foreground="${white}" ;;
        high) background="${coral}"; foreground="${white}" ;;
        medium) background="${butter}"; foreground="${black}" ;;
    esac

    block "${background}" "${foreground}" "${bold}" "${icon_effort} ${effort}"
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

# Picks a meter's own color, then yellow, peach or red by how close a percentage is to 100.
percent_color() {
    local percent="${1}" \
          calm="${2}" \
          level

    level="$(threshold_level "${percent}" "${context_warning}" "${context_high}" "${context_critical}")"

    [[ "${level}" -gt 0 ]] || { printf '%s' "${calm}"; return 0; }

    printf '%s' "${warning_colors[level - 1]}"
}

# Shortens a token count: 999, 84K, 1.3M. Prints nothing for a non-numeric count.
format_tokens() {
    local tokens="${1}" \
          kilos \
          mega_tenths

    [[ "${tokens}" =~ ^[0-9]+$ ]] || return 0

    tokens=$((10#${tokens}))
    [[ "${tokens}" -lt "${tokens_per_kilo}" ]] && { printf '%s' "${tokens}"; return 0; }

    kilos=$(((tokens + tokens_per_kilo / 2) / tokens_per_kilo))
    [[ "${kilos}" -lt "${tokens_per_kilo}" ]] && { printf '%sK' "${kilos}"; return 0; }

    mega_tenths=$(((tokens + tokens_per_mega_tenth / 2) / tokens_per_mega_tenth))
    [[ $((mega_tenths % 10)) -eq 0 ]] && { printf '%sM' "$((mega_tenths / 10))"; return 0; }

    printf '%s.%sM' "$((mega_tenths / 10))" "$((mega_tenths % 10))"
}

# Prints the context share with one decimal: 94400 tokens of a 200000 window is 47.2.
# Claude Code rounds used_percentage to an integer, so the decimal has to come from the tokens.
# Keeps that rounded percentage while the tokens or the window size are unknown:
# tokens is empty before the first API call and right after /compact.
format_percent() {
    local percent="${1}" \
          tokens="${2}" \
          window="${3}" \
          tenths

    [[ "${tokens}" =~ ^[0-9]+$ && "${window}" =~ ^[1-9][0-9]*$ ]] || { printf '%s' "${percent}"; return 0; }

    tenths=$(((10#${tokens} * tenths_per_whole + window / 2) / window))

    printf '%s.%s' "$((tenths / 10))" "$((tenths % 10))"
}

# Prints "icon ▰▰▰▰▱▱▱▱▱▱ 47.2% 94K": the icon and the bar in the percent_color, cyan while calm, the tokens dimmed.
format_context() {
    local percent="${1%%.*}" \
          tokens="${2:-}" \
          window="${3:-}" \
          color \
          short_tokens

    [[ "${percent}" =~ ^[0-9]+$ ]] || return 0

    color="$(percent_color "${percent}" "${cyan}")"
    short_tokens="$(format_tokens "${tokens}")"

    join_segments \
        "$(paint "${color}" "${icon_context}")" \
        "$(build_bar "${percent}" "${color}" "${slab_filled}" "${slab_empty}" "${color}")" \
        "$(paint "${text}" "$(format_percent "${percent}" "${tokens}" "${window}")%" "${bold}")" \
        "${short_tokens:+$(paint "${overlay}" "${short_tokens}")}"
}

format_cost() {
    local cost="${1}"

    [[ -n "${cost}" ]] || return 0

    paint "${yellow}" "${icon_cost} $(LC_NUMERIC=C printf '$%.2f' "${cost}")"
}

format_time() {
    block "${dusk}" "${orchid}" "" "${icon_clock} $(format_epoch '%R')"
}

# Prints milliseconds as "47s", "8m 47s" or "2h 5m". Prints nothing for a non-numeric duration or less than a second.
format_elapsed() {
    local milliseconds="${1%%.*}" \
          seconds

    [[ "${milliseconds}" =~ ^[0-9]+$ ]] || return 0

    seconds=$((10#${milliseconds} / milliseconds_per_second))
    [[ "${seconds}" -gt 0 ]] || return 0

    [[ "${seconds}" -ge "${seconds_per_hour}" ]] && {
        printf '%dh %dm' $((seconds / seconds_per_hour)) $((seconds % seconds_per_hour / seconds_per_minute))
        return 0
    }

    [[ "${seconds}" -ge "${seconds_per_minute}" ]] && {
        printf '%dm %ds' $((seconds / seconds_per_minute)) $((seconds % seconds_per_minute))
        return 0
    }

    printf '%ds' "${seconds}"
}

# Prints the time since the session started as "⌛ 8m 47s"; nothing while it is unknown or still zero.
format_duration() {
    local elapsed

    elapsed="$(format_elapsed "${1}")"
    [[ -n "${elapsed}" ]] || return 0

    block "${umber}" "${salmon}" "" "${icon_duration} ${elapsed}"
}

# Prints bar_width glyphs: the used share filled in its color, the rest empty in another color.
build_bar() {
    local percent="${1%%.*}" \
          color="${2}" \
          filled_glyph="${3}" \
          empty_glyph="${4}" \
          empty_color="${5}" \
          filled \
          index \
          used="" \
          free=""

    [[ "${percent}" =~ ^[0-9]+$ ]] || return 0
    [[ "${percent}" -gt 100 ]] && percent=100

    filled=$((percent * bar_width / 100))

    for ((index = 0; index < filled; index++)); do
        used="${used}${filled_glyph}"
    done

    for ((index = filled; index < bar_width; index++)); do
        free="${free}${empty_glyph}"
    done

    [[ -n "${used}" ]] && paint "${color}" "${used}"
    [[ -n "${free}" ]] && paint "${empty_color}" "${free}"

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

# Prints "label meter ⟳ reset", the reset only when known.
format_rate_limit() {
    local label="${1}" \
          meter="${2}" \
          reset="${3}"

    printf '%s %s' "$(paint "${text}" "${label}")" "${meter}"
    [[ -n "${reset}" ]] && printf ' %s' "$(paint "${overlay}" "${icon_reset} ${reset}")"

    return 0
}

# Prints "5h ●●○○○○○○○○ 23% ⟳ 1h 38m", the unused dots dimmed; nothing when the window is absent.
format_five_hour() {
    local percent="${1%%.*}" \
          reset="${2}" \
          color

    [[ "${percent}" =~ ^[0-9]+$ ]] || return 0

    color="$(percent_color "${percent}" "${green}")"

    format_rate_limit "5h" \
        "$(build_bar "${percent}" "${color}" "${dot_filled}" "${dot_empty}" "${overlay}") $(paint "${color}" "${percent}%")" \
        "${reset}"
}

# Prints "7d [≋≋≋·······] 32% ⟳ Thu 09:00", the whole meter in one color, aqua while calm; nothing when the window is absent.
format_seven_day() {
    local percent="${1%%.*}" \
          reset="${2}" \
          color

    [[ "${percent}" =~ ^[0-9]+$ ]] || return 0

    color="$(percent_color "${percent}" "${aqua}")"

    format_rate_limit "7d" \
        "$(paint "${color}" "[")$(build_bar "${percent}" "${color}" "${wave_filled}" "${wave_empty}" "${color}")$(paint "${color}" "]") $(paint "$(percent_color "${percent}" "${azure}")" "${percent}%")" \
        "${reset}"
}

# Counts terminal cells, ignoring colors. Every glyph used here is one cell wide, except those in wide_glyphs.
visible_width() {
    local LC_ALL=C \
          content="${1}" \
          escape_pattern=$'^(.*)\033\\[[0-9;]*m(.*)$' \
          continuation_bytes=$'[\x80-\xbf]' \
          glyph \
          narrow \
          extra_cells=0

    while [[ "${content}" =~ ${escape_pattern} ]]; do
        content="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    done

    for glyph in "${wide_glyphs[@]}"; do
        narrow="${content//${glyph}/}"
        extra_cells=$((extra_cells + (${#content} - ${#narrow}) / ${#glyph}))
    done

    content="${content//${continuation_bytes}/}"

    printf '%s' "$((${#content} + extra_cells))"
}

# Pads between both sides so the right one ends at the terminal edge.
align_line() {
    local left="${1}" \
          right="${2}" \
          columns="${3}" \
          gap="${min_gap}"

    [[ -n "${right}" ]] || { printf '%s' "${left}"; return 0; }

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

# Line 1, left: the blocks stand back to back, the other segments follow with a space.
build_left() {
    join_segments \
        "$(format_user)$(format_directory "${session_cwd}" "${HOME}")$(format_git "${session_cwd}")" \
        "$(format_languages "${session_cwd}")" \
        "$(format_containers "${session_cwd}")"
}

# Line 1, right: the blocks stand back to back. The memory warning, when shown, sits before the clock.
build_right() {
    local memory

    memory="$(format_memory "$(memory_percent)")"

    printf '%s%s%s' \
        "$(format_duration "${session_duration}")$(format_model "${session_model}")$(format_effort "${session_effort}")" \
        "${memory:+ ${memory} }" \
        "$(format_time)"
}

# Line 2, left. Only claude.ai Pro/Max sessions carry rate_limits; elsewhere this prints nothing.
build_rate_limits() {
    local now

    [[ -n "${session_five_hour}${session_seven_day}" ]] || return 0

    now="$(now_epoch)"

    join_with "${rate_limit_separator}" \
        "$(format_five_hour "${session_five_hour}" "$(format_countdown "${session_five_hour_reset}" "${now}")")" \
        "$(format_seven_day "${session_seven_day}" "$(format_reset_day "${session_seven_day_reset}")")"
}

# Line 2, right: the context and the session cost; nothing while the context is unknown.
build_context() {
    local context

    context="$(format_context "${session_context}" "${session_tokens}" "${session_window}")"
    [[ -n "${context}" ]] || return 0

    join_with "$(paint "${overlay}" "${cost_separator}")" "${context}" "$(format_cost "${session_cost}")"
}

main() {
    local second_line

    parse_session "$(cat)"

    align_line "$(build_left)" "$(build_right)" "${COLUMNS:-}"

    second_line="$(align_line "$(build_rate_limits)" "$(build_context)" "${COLUMNS:-}")"
    [[ -n "${second_line}" ]] && printf '\n%s' "${second_line}"

    return 0
}

[[ "${BASH_SOURCE[0]}" != "${0}" ]] || main "$@"
