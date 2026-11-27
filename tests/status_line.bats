#!/usr/bin/env bats
# Run: bats tests/status_line.bats
# Needs: bats-core >= 1.4, jq, git on PATH.

setup() {
    export NO_COLOR=1

    # BATS_TEST_TMPDIR honors TMPDIR and is cleaned up; macOS `mktemp -d` ignores TMPDIR.
    TEST_DIR="${BATS_TEST_TMPDIR}"
    export XDG_CACHE_HOME="${TEST_DIR}/cache"

    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../stow/.config/claude/status_line.sh"
}

# Writes an executable stub into TEST_DIR/bin, ahead of the real command on PATH.
# Every call is appended to TEST_DIR/calls.
stub_command() {
    local name="${1}" \
          body="${2}"

    mkdir -p "${TEST_DIR}/bin"
    printf '#!/usr/bin/env bash\necho "%s $*" >> "%s/calls"\n%s\n' "${name}" "${TEST_DIR}" "${body}" > "${TEST_DIR}/bin/${name}"
    chmod +x "${TEST_DIR}/bin/${name}"
    PATH="${TEST_DIR}/bin:${PATH}"
}

file_mode() {
    stat -c %a "${1}" 2>/dev/null || stat -f %Lp "${1}"
}

# --- parse_session ----------------------------------------------------------

@test "parse_session: reads every field, empty model keeps the later fields aligned" {
    local cases=(
        '{"workspace":{"current_dir":"/w"},"model":{"display_name":"Opus"},"context_window":{"used_percentage":8},"cost":{"total_cost_usd":0.5}}|/w,Opus,8,0.5'
        '{"cwd":"/c","context_window":{"used_percentage":23.5},"cost":{"total_cost_usd":1}}|/c,,23.5,1'
        '{"workspace":{"current_dir":"/w"},"context_window":{"used_percentage":null}}|/w,,,'
    ) \
        entry \
        expected

    for entry in "${cases[@]}"; do
        expected="${entry#*|}"

        parse_session "${entry%%|*}"
        [ "${session_cwd},${session_model},${session_context},${session_cost}" == "${expected}" ]
    done
}

@test "parse_session: reads token usage, the window size and rate limits" {
    local cases=(
        '{"context_window":{"context_window_size":1000000,"current_usage":{"input_tokens":100,"cache_creation_input_tokens":20,"cache_read_input_tokens":3}},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},"seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}|123,1000000,23.5,1738425600,41.2,1738857600'
        '{"context_window":{"current_usage":null},"rate_limits":{"seven_day":{"used_percentage":5,"resets_at":1}}}|,,,,5,1'
        '{"context_window":{"current_usage":{"input_tokens":7}}}|7,,,,,'
    ) \
        entry \
        expected

    for entry in "${cases[@]}"; do
        expected="${entry#*|}"

        parse_session "${entry%%|*}"
        [ "${session_tokens},${session_window},${session_five_hour},${session_five_hour_reset},${session_seven_day},${session_seven_day_reset}" == "${expected}" ]
    done
}

@test "parse_session: falls back to PWD on invalid JSON" {
    parse_session "not json"

    [ "${session_cwd}" == "${PWD}" ]
    [ -z "${session_model}" ]
    [ -z "${session_five_hour}" ]
}

@test "parse_session: reads the effort level, empty when the model has none" {
    local cases=(
        '{"model":{"display_name":"Opus"},"effort":{"level":"xhigh"}}|Opus,xhigh'
        '{"model":{"display_name":"Haiku"}}|Haiku,'
        '{"effort":{"level":null}}|,'
    ) \
        entry \
        expected

    for entry in "${cases[@]}"; do
        expected="${entry#*|}"

        parse_session "${entry%%|*}"
        [ "${session_model},${session_effort}" == "${expected}" ]
    done
}

@test "parse_session: reads the session duration, empty when the JSON has none" {
    local cases=(
        '{"cost":{"total_cost_usd":1,"total_duration_ms":527000}}|527000'
        '{"cost":{"total_cost_usd":1}}|'
        '{}|'
    ) \
        entry

    for entry in "${cases[@]}"; do
        parse_session "${entry%%|*}"
        [ "${session_duration}" == "${entry#*|}" ]
    done
}

# --- paint / block ----------------------------------------------------------

@test "paint: puts SGR attributes ahead of the color" {
    unset NO_COLOR
    local cases=(
        "|"$'\033[38;2;1;2;3mx\033[0m'
        "${bold}|"$'\033[1;38;2;1;2;3mx\033[0m'
        "${italic}|"$'\033[3;38;2;1;2;3mx\033[0m'
    ) \
        entry

    for entry in "${cases[@]}"; do
        run paint "1;2;3" "x" "${entry%%|*}"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${entry#*|}" ]
    done
}

@test "block: pads the text on a solid background, in one SGR sequence" {
    unset NO_COLOR
    local cases=(
        "|"$'\033[48;2;4;5;6;38;2;1;2;3m x \033[0m'
        "${bold}|"$'\033[1;48;2;4;5;6;38;2;1;2;3m x \033[0m'
    ) \
        entry

    for entry in "${cases[@]}"; do
        run block "4;5;6" "1;2;3" "${entry%%|*}" "x"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${entry#*|}" ]
    done
}

@test "paint, block: print the same text without colors under NO_COLOR" {
    run paint "1;2;3" "x" "${bold}"
    [ "${output}" == "x" ]

    run block "4;5;6" "1;2;3" "${bold}" "x"
    [ "${output}" == " x " ]
}

@test "styles: every restyled segment has its own colors and attributes" {
    unset NO_COLOR
    local head=$'# branch.oid 0123456789abcdef\n# branch.head ' \
          cases \
          entry

    cases=(
        "$(USER=me OSTYPE=darwin24 format_user)|$(block "${navy}" "${text}" "${bold}" "${icon_apple} me")"
        "$(format_directory "/usr/local" "/home/me")|$(block "${steel}" "${text}" "" "${icon_folder} /usr/local")"
        "$(format_git_head "${head}main")|$(block "${teal}" "${crust}" "${italic}" "${icon_branch} main")"
        "$(format_git_head "${head}(detached)")|$(block "${peach}" "${crust}" "${italic}" "${icon_commit} 0123456")"
        "$(format_model "Opus")|$(block "${royal}" "${pearl}" "${bold}" "${icon_model} Opus")"
        "$(format_effort "low")|$(block "${ocean}" "${ice}" "${bold}" "${icon_effort} low")"
        "$(format_cost "0.42")|$(paint "${yellow}" "${icon_cost} \$0.42")"
        "$(format_duration "527000")|$(block "${umber}" "${salmon}" "" "${icon_duration} 8m 47s")"
    )

    for entry in "${cases[@]}"; do
        [ "${entry%%|*}" == "${entry#*|}" ]
    done
}

# --- format_os / format_user ------------------------------------------------

@test "format_os: picks the icon from OSTYPE" {
    local cases=(
        "darwin24|${icon_apple}"
        "linux-gnu|${icon_linux}"
        "msys|${icon_other_os}"
    ) \
        entry

    for entry in "${cases[@]}"; do
        OSTYPE="${entry%%|*}" run format_os
        [ "${status}" -eq 0 ]
        [ "${output}" == "${entry#*|}" ]
    done
}

@test "format_user: shows the OS icon and the user in one block" {
    USER=me OSTYPE=darwin24 run format_user

    [ "${status}" -eq 0 ]
    [ "${output}" == " ${icon_apple} me " ]
}

# --- format_directory -------------------------------------------------------

@test "format_directory: replaces home and shortens long paths" {
    local cases=(
        "/home/me|${icon_folder} ${icon_home} ~"
        "/home/me/code|${icon_folder} ${icon_home} ~/code"
        "/home/me/a/b|${icon_folder} ${icon_home} ~/a/b"
        "/home/me/a/b/c|${icon_folder} …/a/b/c"
        "/home/me/a/b/c/d|${icon_folder} …/b/c/d"
        "/home/meow/x|${icon_folder} /home/meow/x"
        "/usr/local|${icon_folder} /usr/local"
        "/usr/local/share|${icon_folder} /usr/local/share"
        "/usr/local/share/man|${icon_folder} …/local/share/man"
        "/usr/local/share/man/man1|${icon_folder} …/share/man/man1"
    ) \
        entry \
        expected

    for entry in "${cases[@]}"; do
        expected="${entry#*|}"

        run format_directory "${entry%%|*}" "/home/me"
        [ "${status}" -eq 0 ]
        [ "${output}" == " ${expected} " ]
    done
}

# --- count_git_status / format_git_head / format_git_counts -----------------

@test "count_git_status: counts branch drift and file states from porcelain v2" {
    local cases=(
        $'# branch.oid 0123abc\n# branch.head main|0 0 0 0 0'
        $'# branch.oid 0123abc\n# branch.head main\n# branch.upstream origin/main\n# branch.ab +2 -3|2 3 0 0 0'
        $'# branch.head main\n1 M. N... 100644 100644 100644 a b staged.sh\n1 .M N... 100644 100644 100644 a b worktree.sh\n1 MM N... 100644 100644 100644 a b both.sh\n? new.sh|0 0 2 2 1'
        $'# branch.ab +0 -1\n1 A. N... 000000 100644 100644 a b added\n1 D. N... 100644 000000 000000 a b deleted\n2 R. N... 100644 100644 100644 a b R100 renamed\told|0 1 3 0 0'
    ) \
        entry \
        expected

    for entry in "${cases[@]}"; do
        expected="${entry##*|}"

        run count_git_status "${entry%|*}"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${expected}" ]
    done
}

@test "format_git_head: shows the branch, cut when longer than 18 characters, or the short commit when detached" {
    local cases=(
        $'# branch.oid 0123456789abcdef\n# branch.head main|'"${icon_branch} main"
        $'# branch.oid 0123456789abcdef\n# branch.head chore/status-line1|'"${icon_branch} chore/status-line1"
        $'# branch.oid 0123456789abcdef\n# branch.head chore/status-line12|'"${icon_branch} chore/status-line…"
        $'# branch.oid 0123456789abcdef\n# branch.head chore/enhancing-claude-status-line|'"${icon_branch} chore/enhancing-c…"
        $'# branch.oid 0123456789abcdef\n# branch.head (detached)|'"${icon_commit} 0123456"
    ) \
        entry

    for entry in "${cases[@]}"; do
        run format_git_head "${entry%|*}"
        [ "${status}" -eq 0 ]
        [ "${output}" == " ${entry##*|} " ]
    done
}

@test "format_git_counts: hides zero counts" {
    local cases=(
        "0 0 0 0 0|"
        "1 0 0 0 0|⇡1"
        "0 2 3 0 0|⇣2++(3)"
        "0 0 0 4 5|${icon_modified} 4${icon_untracked} 5"
    ) \
        entry \
        expected

    for entry in "${cases[@]}"; do
        expected="${entry#*|}"

        # shellcheck disable=SC2086 # five counts, split on purpose.
        run format_git_counts ${entry%%|*}
        [ "${status}" -eq 0 ]
        [ "${output}" == "${expected}" ]
    done
}

@test "format_git: prints nothing outside a git repository" {
    run format_git "${TEST_DIR}"

    [ "${status}" -eq 0 ]
    [ -z "${output}" ]
}

@test "format_git: shows the branch and untracked files with a single git call" {
    local real_git \
          repo="${TEST_DIR}/repo"

    real_git="$(command -v git)"
    git init -q -b trunk "${repo}"
    touch "${repo}/new.sh"
    stub_command git "exec '${real_git}' \"\$@\""

    run format_git "${repo}"
    [ "${status}" -eq 0 ]
    [ "${output}" == " ${icon_branch} trunk  ${icon_untracked} 1" ]
    [ "$(rg -c '^git ' "${TEST_DIR}/calls")" -eq 1 ]
}

@test "format_git: shows the short commit on a detached HEAD" {
    git -C "${TEST_DIR}" init -q -b trunk
    git -C "${TEST_DIR}" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false \
        commit -q --allow-empty -m init
    git -C "${TEST_DIR}" checkout -q --detach

    run format_git "${TEST_DIR}"
    [ "${status}" -eq 0 ]
    [ "${output}" == " ${icon_commit} $(git -C "${TEST_DIR}" rev-parse --short=7 HEAD) " ]
}

# --- format_languages -------------------------------------------------------

@test "format_languages: detects projects by marker files" {
    local cases=(
        "|"
        "go.mod|${icon_go} "
        "init.lua|${icon_lua} "
        ".luarc.json|${icon_lua} "
        "go.mod package.json|${icon_go} ${icon_node} "
        "requirements.txt|${icon_python} "
    ) \
        entry \
        files \
        file \
        expected

    for entry in "${cases[@]}"; do
        files="${entry%%|*}"
        expected="${entry#*|}"
        rm -rf "${TEST_DIR:?}"/* "${TEST_DIR}"/.luarc.json

        for file in ${files}; do
            touch "${TEST_DIR}/${file}"
        done

        run format_languages "${TEST_DIR}"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${expected}" ]
    done
}

# --- format_containers / cache ----------------------------------------------

@test "format_containers: asks kubectl once for context and namespace" {
    touch "${TEST_DIR}/Dockerfile"
    stub_command docker 'echo desktop-linux'
    stub_command kubectl 'printf "prod\tpayments"'

    run format_containers "${TEST_DIR}"
    [ "${status}" -eq 0 ]
    [ "${output}" == "${icon_docker} desktop-linux ☸ prod (payments)" ]
    [ "$(rg -c '^kubectl ' "${TEST_DIR}/calls")" -eq 1 ]
}

@test "format_containers: hides the default namespace" {
    touch "${TEST_DIR}/Dockerfile"
    stub_command docker 'echo desktop-linux'
    stub_command kubectl 'printf "dev\tdefault"'

    run format_containers "${TEST_DIR}"
    [ "${output}" == "${icon_docker} desktop-linux ☸ dev" ]
}

@test "format_containers: falls back to the last good value, dimmed, when a CLI fails" {
    touch "${TEST_DIR}/Dockerfile"
    stub_command docker 'echo desktop-linux'
    stub_command kubectl 'printf "prod\tpayments"'
    format_containers "${TEST_DIR}" > /dev/null

    stub_command docker 'exit 1'
    stub_command kubectl 'exit 1'
    unset NO_COLOR

    run format_containers "${TEST_DIR}"
    [ "${status}" -eq 0 ]
    [ "${output}" == "$(paint "${overlay}" "${icon_docker} desktop-linux ")$(paint "${overlay}" "☸ prod")$(paint "${overlay}" " (payments)")" ]
}

@test "format_containers: shows the default docker context and no k8s without a cache" {
    touch "${TEST_DIR}/Dockerfile"
    stub_command docker 'exit 1'
    stub_command kubectl 'exit 1'

    run format_containers "${TEST_DIR}"
    [ "${status}" -eq 0 ]
    [ "${output}" == "${icon_docker} default " ]
}

@test "cache_write: keeps the cache private" {
    cache_write "probe" "value"

    [ "$(file_mode "${cache_dir}")" == "700" ]
    [ "$(file_mode "${cache_dir}/probe")" == "600" ]

    run cache_read "probe"
    [ "${status}" -eq 0 ]
    [ "${output}" == "value" ]
}

@test "cache: never writes through or reads from a symlink" {
    mkdir -p "${cache_dir}"
    printf 'planted' > "${TEST_DIR}/target"
    ln -s "${TEST_DIR}/target" "${cache_dir}/link"

    run cache_read "link"
    [ "${status}" -eq 1 ]

    cache_write "link" "value"
    [ "$(cat "${TEST_DIR}/target")" == "planted" ]
    [ ! -L "${cache_dir}/link" ]
}

# --- format_memory / format_cost / format_model -----------------------------

@test "format_memory: shows only at or above the threshold" {
    local cases=(
        "84|"
        "85|${icon_memory} 85%"
        "99|${icon_memory} 99%"
        "|"
        "abc|"
    ) \
        entry \
        expected

    for entry in "${cases[@]}"; do
        expected="${entry#*|}"

        run format_memory "${entry%%|*}"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${expected}" ]
    done
}

@test "format_cost: rounds to cents and hides when missing" {
    local cases=(
        "0.01234|${icon_cost} \$0.01"
        "1|${icon_cost} \$1.00"
        "12.345|${icon_cost} \$12.35"
        "|"
    ) \
        entry \
        expected

    for entry in "${cases[@]}"; do
        expected="${entry#*|}"

        run format_cost "${entry%%|*}"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${expected}" ]
    done
}

@test "format_model: shows the model name when present" {
    run format_model "Opus"
    [ "${output}" == " ${icon_model} Opus " ]

    run format_model ""
    [ -z "${output}" ]
}

@test "format_effort: shows the effort level when present" {
    run format_effort "high"
    [ "${output}" == " ${icon_effort} high " ]

    run format_effort ""
    [ -z "${output}" ]
}

@test "format_effort: colors the block by level, an unknown level looks like low" {
    unset NO_COLOR
    local cases=(
        "max|${magenta}|${chalk}"
        "xhigh|${indigo}|${white}"
        "high|${coral}|${white}"
        "medium|${butter}|${black}"
        "low|${ocean}|${ice}"
        "auto|${ocean}|${ice}"
    ) \
        entry \
        level \
        background \
        foreground

    for entry in "${cases[@]}"; do
        IFS='|' read -r level background foreground <<< "${entry}"

        run format_effort "${level}"
        [ "${status}" -eq 0 ]
        [ "${output}" == "$(block "${background}" "${foreground}" "${bold}" "${icon_effort} ${level}")" ]
    done
}

@test "format_time: shows the clock in its own block" {
    local clock_pattern="^ ${icon_clock} [0-9]{2}:[0-9]{2} $"

    run format_time
    [ "${status}" -eq 0 ]
    [[ "${output}" =~ ${clock_pattern} ]]

    unset NO_COLOR

    run format_time
    [ "${status}" -eq 0 ]
    [[ "${output}" == $'\033[48;2;'"${dusk};38;2;${orchid}m ${icon_clock} "* ]]
}

@test "format_elapsed: prints milliseconds as seconds, minutes or hours, nothing below a second" {
    local cases=(
        "0|"
        "999|"
        "1000|1s"
        "47000|47s"
        "60000|1m 0s"
        "527000|8m 47s"
        "527000.7|8m 47s"
        "3599999|59m 59s"
        "3600000|1h 0m"
        "7500000|2h 5m"
        "abc|"
        "null|"
        "|"
    ) \
        entry

    for entry in "${cases[@]}"; do
        run format_elapsed "${entry%%|*}"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${entry#*|}" ]
    done
}

@test "format_duration: shows the session time in a block, hides when unknown or zero" {
    local cases=(
        "527000| ${icon_duration} 8m 47s "
        "0|"
        "|"
    ) \
        entry

    for entry in "${cases[@]}"; do
        run format_duration "${entry%%|*}"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${entry#*|}" ]
    done
}

# --- format_context ---------------------------------------------------------

# Prints the colored start of the context segment: the icon and the bar, both in the level color.
context_start() {
    local percent="${1}" \
          color="${2}"

    printf '%s %s ' "$(paint "${color}" "${icon_context}")" \
        "$(build_bar "${percent}" "${color}" "${slab_filled}" "${slab_empty}" "${color}")"
}

@test "format_context: colors the icon and the bar by percentage" {
    unset NO_COLOR
    local cases=(
        "0|${cyan}"
        "49.9|${cyan}"
        "50|${yellow}"
        "74|${yellow}"
        "75|${peach}"
        "89|${peach}"
        "90|${red}"
        "100|${red}"
    ) \
        entry \
        value

    for entry in "${cases[@]}"; do
        value="${entry%%|*}"

        run format_context "${value}"
        [ "${status}" -eq 0 ]
        [[ "${output}" == "$(context_start "${value}" "${entry#*|}")"* ]]
    done
}

@test "format_context: colors by the percentage, however many tokens the window holds" {
    unset NO_COLOR

    run format_context "38" "388000" "1000000"
    [ "${status}" -eq 0 ]
    [[ "${output}" == "$(context_start "38" "${cyan}")"* ]]
}

@test "format_context: prints the percentage bold and the tokens dimmed" {
    unset NO_COLOR

    run format_context "42" "84320" "200000"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *" $(paint "${text}" "$(format_percent 42 84320 200000)%" "${bold}") $(paint "${overlay}" "84K")" ]]
}

@test "format_percent: derives one decimal from the tokens and the window size, else keeps the rounded percentage" {
    local cases=(
        "47|94400|200000|47.2"
        "0|0|200000|0.0"
        "1|8000|1000000|0.8"
        "1|8499|1000000|0.8"
        "1|8500|1000000|0.9"
        "48|95900|200000|48.0"
        "100|200000|200000|100.0"
        "47||200000|47"
        "47|null|200000|47"
        "47|94400||47"
        "47|94400|null|47"
        "47|94400|0|47"
    ) \
        entry \
        percent \
        tokens \
        window \
        expected

    for entry in "${cases[@]}"; do
        IFS='|' read -r percent tokens window expected <<< "${entry}"

        run format_percent "${percent}" "${tokens}" "${window}"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${expected}" ]
    done
}

@test "format_tokens: shortens to K and M, hides non-numeric input" {
    local cases=(
        "0|0"
        "999|999"
        "1000|1K"
        "1499|1K"
        "1500|2K"
        "84320|84K"
        "999499|999K"
        "999500|1M"
        "1000000|1M"
        "1250000|1.3M"
        "2040000|2M"
        "|"
        "null|"
    ) \
        entry

    for entry in "${cases[@]}"; do
        run format_tokens "${entry%%|*}"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${entry#*|}" ]
    done
}

@test "format_context: shows the bar, the percentage and the tokens, the tokens only when known" {
    local cases=(
        "42|84320|200000|${icon_context} ▰▰▰▰▱▱▱▱▱▱ $(format_percent 42 84320 200000)% 84K"
        "42.7|84320|200000|${icon_context} ▰▰▰▰▱▱▱▱▱▱ $(format_percent 42 84320 200000)% 84K"
        "42|||${icon_context} ▰▰▰▰▱▱▱▱▱▱ $(format_percent 42 "" "")%"
        "42|null||${icon_context} ▰▰▰▰▱▱▱▱▱▱ $(format_percent 42 null "")%"
        "100|||${icon_context} ▰▰▰▰▰▰▰▰▰▰ $(format_percent 100 "" "")%"
    ) \
        entry \
        percent \
        tokens \
        window \
        expected

    for entry in "${cases[@]}"; do
        IFS='|' read -r percent tokens window expected <<< "${entry}"

        run format_context "${percent}" "${tokens}" "${window}"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${expected}" ]
    done
}

@test "format_context: hides missing or non-numeric usage" {
    local cases=("" "null" "abc") \
        value

    for value in "${cases[@]}"; do
        run format_context "${value}" "5000"
        [ "${status}" -eq 0 ]
        [ -z "${output}" ]
    done
}

# --- rate limits ------------------------------------------------------------

@test "build_bar: fills dots by percentage and clamps at 100" {
    local cases=(
        "0|○○○○○○○○○○"
        "23|●●○○○○○○○○"
        "23.9|●●○○○○○○○○"
        "100|●●●●●●●●●●"
        "150|●●●●●●●●●●"
        "abc|"
        "|"
    ) \
        entry

    for entry in "${cases[@]}"; do
        run build_bar "${entry%%|*}" "${green}" "${dot_filled}" "${dot_empty}" "${overlay}"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${entry#*|}" ]
    done
}

@test "build_bar: draws the given glyphs, the empty ones in their own color" {
    unset NO_COLOR

    run build_bar "30" "${green}" "${wave_filled}" "${wave_empty}" "${red}"
    [ "${status}" -eq 0 ]
    [ "${output}" == "$(paint "${green}" "≋≋≋")$(paint "${red}" "·······")" ]
}

@test "format_countdown: prints the time left until a reset" {
    local cases=(
        "1000|now"
        "999|now"
        "1060|1m"
        "4600|1h 0m"
        "6880|1h 38m"
        "abc|"
        "|"
    ) \
        entry

    for entry in "${cases[@]}"; do
        run format_countdown "${entry%%|*}" "1000"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${entry#*|}" ]
    done
}

@test "format_epoch: formats a given epoch" {
    export TZ=UTC

    run format_epoch '%a %R' 0
    [ "${status}" -eq 0 ]
    [ "${output}" == "Thu 00:00" ]
}

@test "format_five_hour, format_seven_day: show a meter, hide when the window is missing" {
    local cases=(
        "format_five_hour|23.5|1h 38m|5h ●●○○○○○○○○ 23% ${icon_reset} 1h 38m"
        "format_five_hour|41||5h ●●●●○○○○○○ 41%"
        "format_five_hour||1h|"
        "format_seven_day|32.9|Thu 09:00|7d [≋≋≋·······] 32% ${icon_reset} Thu 09:00"
        "format_seven_day|41||7d [≋≋≋≋······] 41%"
        "format_seven_day|100||7d [≋≋≋≋≋≋≋≋≋≋] 100%"
        "format_seven_day||Thu 09:00|"
    ) \
        entry \
        formatter \
        percent \
        reset \
        expected

    for entry in "${cases[@]}"; do
        IFS='|' read -r formatter percent reset expected <<< "${entry}"

        run "${formatter}" "${percent}" "${reset}"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${expected}" ]
    done
}

@test "rate limits: the labels 5h and 7d keep the text color" {
    unset NO_COLOR
    local cases=(
        "$(format_five_hour "23" "")|5h"
        "$(format_seven_day "32" "")|7d"
    ) \
        entry

    for entry in "${cases[@]}"; do
        [[ "${entry%%|*}" == "$(paint "${text}" "${entry#*|}") "* ]]
    done
}

@test "rate limits: 5h dims the unused dots, 7d draws its whole meter in one color" {
    unset NO_COLOR
    local cases=(
        "$(format_five_hour "23" "")|$(paint "${green}" "●●")$(paint "${overlay}" "○○○○○○○○") $(paint "${green}" "23%")"
        "$(format_five_hour "80" "")|$(paint "${peach}" "●●●●●●●●")$(paint "${overlay}" "○○") $(paint "${peach}" "80%")"
        "$(format_seven_day "32" "")|$(paint "${aqua}" "[")$(paint "${aqua}" "≋≋≋")$(paint "${aqua}" "·······")$(paint "${aqua}" "]") $(paint "${azure}" "32%")"
        "$(format_seven_day "80" "")|$(paint "${peach}" "[")$(paint "${peach}" "≋≋≋≋≋≋≋≋")$(paint "${peach}" "··")$(paint "${peach}" "]") $(paint "${peach}" "80%")"
    ) \
        entry

    for entry in "${cases[@]}"; do
        [[ "${entry%%|*}" == *" ${entry#*|}" ]]
    done
}

# --- visible_width / align_line / join_segments -----------------------------

@test "visible_width: counts cells, not bytes or color codes, and two cells for an emoji" {
    unset NO_COLOR
    local cases=(
        "abc|3"
        "$(paint "${blue}" "abc")|3"
        "${icon_branch} main|6"
        "$(paint "${mauve}" "${icon_model} Opus")$(paint "${text}" " …")|9"
        "$(block "${navy}" "${text}" "${bold}" "${icon_apple} me")|6"
        "${icon_context} ▰▱ [≋·] ${icon_effort}|13"
        "${icon_duration} 8m 47s|9"
        "${icon_cost} \$0.42|8"
        "${icon_model}${icon_model}|4"
        "|0"
    ) \
        entry

    for entry in "${cases[@]}"; do
        run visible_width "${entry%|*}"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${entry##*|}" ]
    done
}

@test "align_line: pushes the right side to the terminal edge" {
    local cases=(
        "20|left${icon_clock}|right|left${icon_clock}      right"
        "20||right|           right"
        "20|left||left"
        "10|left|right|left   right"
        "|left|right|left   right"
        "abc|left|right|left   right"
    ) \
        entry \
        columns \
        rest \
        left \
        right

    for entry in "${cases[@]}"; do
        columns="${entry%%|*}"
        rest="${entry#*|}"
        left="${rest%%|*}"
        rest="${rest#*|}"
        right="${rest%%|*}"

        run align_line "${left}" "${right}" "${columns}"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${rest#*|}" ]
    done
}

@test "build_right: joins the blocks without a gap, the memory warning sits before the clock" {
    local cases=(
        "40| ${icon_duration} 8m 47s  ${icon_model} Opus  ${icon_effort} high  ${icon_clock} "
        "91| ${icon_duration} 8m 47s  ${icon_model} Opus  ${icon_effort} high  ${icon_memory} 91%  ${icon_clock} "
    ) \
        entry \
        memory_stub

    memory_percent() { printf '%s' "${memory_stub}"; }
    session_duration="527000"
    session_model="Opus"
    session_effort="high"

    for entry in "${cases[@]}"; do
        memory_stub="${entry%%|*}"

        run build_right
        [ "${status}" -eq 0 ]
        [[ "${output}" == "${entry#*|}"* ]]
    done
}

@test "join_segments: skips empty segments" {
    run join_segments "a" "" "b" "" "c"
    [ "${output}" == "a b c" ]

    run join_with "  " "a" "" "b"
    [ "${output}" == "a  b" ]
}

# --- main -------------------------------------------------------------------

@test "main: renders the model on a single line while the context is unknown, whatever the cost" {
    run bash -c "printf '%s' '{\"workspace\":{\"current_dir\":\"${TEST_DIR}\"},\"model\":{\"display_name\":\"Opus\"},\"cost\":{\"total_cost_usd\":0.42}}' \
        | NO_COLOR=1 '${BATS_TEST_DIRNAME}/../stow/.config/claude/status_line.sh'"

    [ "${status}" -eq 0 ]
    [[ "${output}" == *" ${icon_model} Opus "* ]]
    [ "${#lines[@]}" -eq 1 ]
}

@test "main: puts the session time, the model and the effort level side by side" {
    run bash -c "printf '%s' '{\"workspace\":{\"current_dir\":\"${TEST_DIR}\"},\"model\":{\"display_name\":\"Opus\"},\"effort\":{\"level\":\"high\"},\"cost\":{\"total_duration_ms\":527000}}' \
        | NO_COLOR=1 '${BATS_TEST_DIRNAME}/../stow/.config/claude/status_line.sh'"

    [ "${status}" -eq 0 ]
    [[ "${output}" == *" ${icon_duration} 8m 47s  ${icon_model} Opus  ${icon_effort} high "* ]]
}

@test "main: adds the rate limits to the second line only when the JSON has rate_limits" {
    run bash -c "printf '%s' '{\"workspace\":{\"current_dir\":\"${TEST_DIR}\"},\"rate_limits\":{\"five_hour\":{\"used_percentage\":23,\"resets_at\":4102444800},\"seven_day\":{\"used_percentage\":41,\"resets_at\":4102444800}}}' \
        | NO_COLOR=1 '${BATS_TEST_DIRNAME}/../stow/.config/claude/status_line.sh'"

    [ "${status}" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [[ "${lines[1]}" == "5h ●●○○○○○○○○ 23% "* ]]
    [[ "${lines[1]}" == *"7d [≋≋≋≋······] 41% "* ]]
}

@test "main: aligns the context and the cost on the second line, also without rate limits" {
    unset NO_COLOR

    run bash -c "printf '%s' '{\"workspace\":{\"current_dir\":\"${TEST_DIR}\"},\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":42},\"cost\":{\"total_cost_usd\":0.42}}' \
        | COLUMNS=120 '${BATS_TEST_DIRNAME}/../stow/.config/claude/status_line.sh'"

    [ "${status}" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [[ "${lines[0]}" != *'$0.42'* ]]
    [[ "${lines[1]}" == *"$(paint "${yellow}" "${icon_cost} \$0.42")" ]]
    [ "$(visible_width "${lines[0]}")" -eq "$((120 - right_margin))" ]
    [ "$(visible_width "${lines[1]}")" -eq "$((120 - right_margin))" ]
}

@test "main: prints no private-use glyph above U+FFFF, JediTerm draws those at another width" {
    touch "${TEST_DIR}/composer.json" "${TEST_DIR}/package.json"

    run bash -c "printf '%s' '{\"workspace\":{\"current_dir\":\"${TEST_DIR}\"},\"model\":{\"display_name\":\"Opus\"},\"effort\":{\"level\":\"high\"},\"context_window\":{\"used_percentage\":42},\"cost\":{\"total_cost_usd\":1.5,\"total_duration_ms\":527000},\"rate_limits\":{\"five_hour\":{\"used_percentage\":23,\"resets_at\":4102444800},\"seven_day\":{\"used_percentage\":41,\"resets_at\":4102444800}}}' \
        | '${BATS_TEST_DIRNAME}/../stow/.config/claude/status_line.sh'"

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"${icon_context} ▰▰▰▰▱▱▱▱▱▱ 42"* ]]
    [[ "${output}" == *"${icon_effort} high"* ]]
    [[ "${output}" == *"${icon_duration} 8m 47s"* ]]

    run rg -q '[\x{F0000}-\x{10FFFF}]' <<< "${output}"
    [ "${status}" -eq 1 ]
}
