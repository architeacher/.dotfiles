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

@test "parse_session: reads token usage and rate limits" {
    local cases=(
        '{"context_window":{"context_window_size":1000000,"current_usage":{"input_tokens":100,"cache_creation_input_tokens":20,"cache_read_input_tokens":3}},"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600},"seven_day":{"used_percentage":41.2,"resets_at":1738857600}}}|123,23.5,1738425600,41.2,1738857600'
        '{"context_window":{"current_usage":null},"rate_limits":{"seven_day":{"used_percentage":5,"resets_at":1}}}|,,,5,1'
        '{"context_window":{"current_usage":{"input_tokens":7}}}|7,,,,'
    ) \
        entry \
        expected

    for entry in "${cases[@]}"; do
        expected="${entry#*|}"

        parse_session "${entry%%|*}"
        [ "${session_tokens},${session_five_hour},${session_five_hour_reset},${session_seven_day},${session_seven_day_reset}" == "${expected}" ]
    done
}

@test "parse_session: falls back to PWD on invalid JSON" {
    parse_session "not json"

    [ "${session_cwd}" == "${PWD}" ]
    [ -z "${session_model}" ]
    [ -z "${session_five_hour}" ]
}

# --- format_os --------------------------------------------------------------

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

# --- format_directory -------------------------------------------------------

@test "format_directory: replaces home and shortens long paths" {
    local cases=(
        "/home/me|${icon_folder} ${icon_home} ~"
        "/home/me/code|${icon_folder} ${icon_home} ~/code"
        "/home/me/a/b/c/d|${icon_folder} …/b/c/d"
        "/home/meow/x|${icon_folder} /home/meow/x"
        "/usr/local|${icon_folder} /usr/local"
        "/usr/local/share/man/man1|${icon_folder} …/share/man/man1"
    ) \
        entry \
        expected

    for entry in "${cases[@]}"; do
        expected="${entry#*|}"

        run format_directory "${entry%%|*}" "/home/me"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${expected}" ]
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

@test "format_git_head: shows the branch, or the short commit when detached" {
    local cases=(
        $'# branch.oid 0123456789abcdef\n# branch.head main|'"${icon_branch} main"
        $'# branch.oid 0123456789abcdef\n# branch.head (detached)|'"${icon_commit} 0123456"
    ) \
        entry

    for entry in "${cases[@]}"; do
        run format_git_head "${entry%|*}"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${entry##*|}" ]
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
    [ "${output}" == "${icon_branch} trunk ${icon_untracked} 1" ]
    [ "$(rg -c '^git ' "${TEST_DIR}/calls")" -eq 1 ]
}

@test "format_git: shows the short commit on a detached HEAD" {
    git -C "${TEST_DIR}" init -q -b trunk
    git -C "${TEST_DIR}" -c user.name=test -c user.email=test@example.com -c commit.gpgsign=false \
        commit -q --allow-empty -m init
    git -C "${TEST_DIR}" checkout -q --detach

    run format_git "${TEST_DIR}"
    [ "${status}" -eq 0 ]
    [ "${output}" == "${icon_commit} $(git -C "${TEST_DIR}" rev-parse --short=7 HEAD)" ]
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
        "0.01234|\$0.01"
        "1|\$1.00"
        "12.345|\$12.35"
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
    [ "${output}" == "${icon_model} Opus" ]

    run format_model ""
    [ -z "${output}" ]
}

# --- format_context ---------------------------------------------------------

@test "format_context: colors by percentage when token usage is unknown" {
    unset NO_COLOR
    local cases=(
        "0|${green}"
        "49.9|${green}"
        "50|${yellow}"
        "74|${yellow}"
        "75|${peach}"
        "89|${peach}"
        "90|${red}"
        "100|${red}"
    ) \
        entry \
        value \
        expected

    for entry in "${cases[@]}"; do
        value="${entry%%|*}"
        expected="$(paint "${entry#*|}" "${icon_context} ${value%%.*}%")"

        run format_context "${value}"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${expected}" ]
    done
}

@test "format_context: colors by absolute tokens, so a 1M window warns as early as 200K" {
    unset NO_COLOR
    local cases=(
        "$((context_tokens_warning - 1))|${green}"
        "${context_tokens_warning}|${yellow}"
        "${context_tokens_high}|${peach}"
        "${context_tokens_critical}|${red}"
    ) \
        entry \
        expected

    for entry in "${cases[@]}"; do
        expected="$(paint "${entry#*|}" "${icon_context} 1%")"

        run format_context "1" "${entry%%|*}"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${expected}" ]
    done
}

@test "format_context: picks the worse of the token and the percentage level" {
    unset NO_COLOR
    local cases=(
        "95|1000|${red}"
        "60|${context_tokens_high}|${peach}"
        "10|${context_tokens_critical}|${red}"
    ) \
        entry \
        percent \
        rest

    for entry in "${cases[@]}"; do
        percent="${entry%%|*}"
        rest="${entry#*|}"

        run format_context "${percent}" "${rest%%|*}"
        [ "${status}" -eq 0 ]
        [ "${output}" == "$(paint "${rest#*|}" "${icon_context} ${percent}%")" ]
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
        run build_bar "${entry%%|*}" "${green}"
        [ "${status}" -eq 0 ]
        [ "${output}" == "${entry#*|}" ]
    done
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

@test "format_rate_limit: shows a meter, hides when the window is missing" {
    run format_rate_limit "5h" "23.5" "1h 38m"
    [ "${output}" == "5h ●●○○○○○○○○ 23% ${icon_reset} 1h 38m" ]

    run format_rate_limit "7d" "41" ""
    [ "${output}" == "7d ●●●●○○○○○○ 41%" ]

    run format_rate_limit "7d" "" "1h"
    [ -z "${output}" ]
}

# --- visible_width / align_line / join_segments -----------------------------

@test "visible_width: counts cells, not bytes or color codes" {
    unset NO_COLOR
    local cases=(
        "abc|3"
        "$(paint "${blue}" "abc")|3"
        "${icon_branch} main|6"
        "$(paint "${mauve}" "${icon_model} Opus")$(paint "${text}" " …")|8"
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

@test "join_segments: skips empty segments" {
    run join_segments "a" "" "b" "" "c"
    [ "${output}" == "a b c" ]

    run join_with "  " "a" "" "b"
    [ "${output}" == "a  b" ]
}

# --- main -------------------------------------------------------------------

@test "main: renders the model from stdin JSON" {
    run bash -c "printf '%s' '{\"workspace\":{\"current_dir\":\"${TEST_DIR}\"},\"model\":{\"display_name\":\"Opus\"}}' \
        | NO_COLOR=1 '${BATS_TEST_DIRNAME}/../stow/.config/claude/status_line.sh'"

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"${icon_model} Opus"* ]]
    [ "${#lines[@]}" -eq 1 ]
}

@test "main: adds a rate-limit line only when the JSON has rate_limits" {
    run bash -c "printf '%s' '{\"workspace\":{\"current_dir\":\"${TEST_DIR}\"},\"rate_limits\":{\"five_hour\":{\"used_percentage\":23,\"resets_at\":4102444800},\"seven_day\":{\"used_percentage\":41,\"resets_at\":4102444800}}}' \
        | NO_COLOR=1 '${BATS_TEST_DIRNAME}/../stow/.config/claude/status_line.sh'"

    [ "${status}" -eq 0 ]
    [ "${#lines[@]}" -eq 2 ]
    [[ "${lines[1]}" == "5h ●●○○○○○○○○ 23% "* ]]
    [[ "${lines[1]}" == *"7d ●●●●○○○○○○ 41% "* ]]
}

@test "main: prints only BMP characters, JediTerm garbles anything above U+FFFF" {
    touch "${TEST_DIR}/composer.json" "${TEST_DIR}/package.json"

    run bash -c "printf '%s' '{\"workspace\":{\"current_dir\":\"${TEST_DIR}\"},\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":42},\"cost\":{\"total_cost_usd\":1.5},\"rate_limits\":{\"five_hour\":{\"used_percentage\":23,\"resets_at\":4102444800}}}' \
        | '${BATS_TEST_DIRNAME}/../stow/.config/claude/status_line.sh'"

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"${icon_context} 42%"* ]]

    run rg -q '[\x{10000}-\x{10FFFF}]' <<< "${output}"
    [ "${status}" -eq 1 ]
}
