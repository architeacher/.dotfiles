#!/usr/bin/env bats
# Run: bats tests/status_line.bats
# Needs: bats-core, jq, git on PATH.

setup() {
    export NO_COLOR=1

    # shellcheck disable=SC1091
    source "${BATS_TEST_DIRNAME}/../stow/.config/claude/status_line.sh"

    TEST_DIR="$(mktemp -d)"
}

teardown() {
    rm -rf "${TEST_DIR}"
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

@test "parse_session: falls back to PWD on invalid JSON" {
    parse_session "not json"

    [ "${session_cwd}" == "${PWD}" ]
    [ -z "${session_model}" ]
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

# --- count_git_status / format_git_counts -----------------------------------

@test "count_git_status: counts branch drift and file states" {
    local cases=(
        "## main|0 0 0 0 0"
        "## main...origin/main [ahead 2, behind 3]|2 3 0 0 0"
        $'## main\nM  staged.sh\n M worktree.sh\nMM both.sh\n?? new.sh|0 0 2 2 1'
        $'## main...origin/main [behind 1]\nA  added\nD  deleted\nR  renamed|0 1 3 0 0'
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

@test "format_git: shows the branch and untracked files" {
    git -C "${TEST_DIR}" init -q -b trunk
    touch "${TEST_DIR}/new.sh"

    run format_git "${TEST_DIR}"
    [ "${status}" -eq 0 ]
    [ "${output}" == "${icon_branch} trunk ${icon_untracked} 1" ]
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

@test "format_context: colors usage by how full the window is" {
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

@test "format_context: hides missing or non-numeric usage" {
    local cases=("" "null" "abc") \
        value

    for value in "${cases[@]}"; do
        run format_context "${value}"
        [ "${status}" -eq 0 ]
        [ -z "${output}" ]
    done
}

# --- join_segments / main ---------------------------------------------------

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
}

@test "main: renders the model from stdin JSON" {
    run bash -c "printf '%s' '{\"workspace\":{\"current_dir\":\"${TEST_DIR}\"},\"model\":{\"display_name\":\"Opus\"}}' \
        | NO_COLOR=1 '${BATS_TEST_DIRNAME}/../stow/.config/claude/status_line.sh'"

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"${icon_model} Opus"* ]]
}

@test "main: prints only BMP characters, JediTerm garbles anything above U+FFFF" {
    touch "${TEST_DIR}/composer.json" "${TEST_DIR}/package.json"

    run bash -c "printf '%s' '{\"workspace\":{\"current_dir\":\"${TEST_DIR}\"},\"model\":{\"display_name\":\"Opus\"},\"context_window\":{\"used_percentage\":42},\"cost\":{\"total_cost_usd\":1.5}}' \
        | '${BATS_TEST_DIRNAME}/../stow/.config/claude/status_line.sh'"

    [ "${status}" -eq 0 ]
    [[ "${output}" == *"${icon_context} 42%"* ]]

    run rg -q '[\x{10000}-\x{10FFFF}]' <<< "${output}"
    [ "${status}" -eq 1 ]
}
