#!/usr/bin/env bats
# Run: bats tests/delegate.bats
# Needs: bats-core, rg, jq, git. pi, opencode, codex, claude and tuios are replaced by the
# test doubles in mocks/; the script runs with a PATH that hides the real binaries.

setup() {
    TEST_DIR="${BATS_TEST_TMPDIR}"
    DELEGATE="${BATS_TEST_DIRNAME}/../harness/skills/delegation/scripts/delegate.sh"
    PROMPT="$(cd "${BATS_TEST_DIRNAME}/../harness/skills/delegation" && pwd)/executor-prompt.md"
    MOCKS="${BATS_TEST_DIRNAME}/mocks"
    BIN="${TEST_DIR}/bin"
    POLL_ATTEMPTS=50
    POLL_INTERVAL=0.1

    mkdir -p "${BIN}"
    local tool
    for tool in pi opencode codex claude tuios; do
        ln -s "${MOCKS}/${tool}" "${BIN}/${tool}"
    done
    ln -s "$(command -v jq)" "${BIN}/jq"

    export DELEGATE_TEST_CALLS="${TEST_DIR}/calls"
    export DELEGATE_STATE_DIR="${TEST_DIR}/state"
    export GIT_CONFIG_GLOBAL=/dev/null
    export GIT_CONFIG_NOSYSTEM=1
    unset DELEGATE_EXECUTOR DELEGATE_VIA DELEGATE_THINKING DELEGATE_CODEX_SANDBOX \
          DELEGATE_PI_MODEL DELEGATE_OPENCODE_MODEL DELEGATE_CODEX_MODEL DELEGATE_CLAUDE_MODEL \
          DELEGATE_TUIOS_EXECUTOR DELEGATE_TUIOS_SESSION DELEGATE_TUIOS_TIMEOUT_MS DELEGATE_TUIOS_LINES \
          TUIOS_SESSION DELEGATE_TIMEOUT DELEGATE_KILL_GRACE DELEGATE_STUB_AUTH_STATUS DELEGATE_STUB_RUN_STATUS \
          DELEGATE_STUB_WRITE_FILE DELEGATE_STUB_RESULT DELEGATE_STUB_THREAD_ID DELEGATE_STUB_TUIOS_SERVER \
          DELEGATE_STUB_TUIOS_STATE DELEGATE_STUB_SESSION_ID DELEGATE_STUB_STOP_REASON DELEGATE_STUB_ERROR_MESSAGE \
          DELEGATE_STUB_SLEEP DELEGATE_STUB_HANG DELEGATE_STUB_PID_FILE DELEGATE_STUB_IGNORE_TERM \
          DELEGATE_STUB_NOISE DELEGATE_STUB_SILENT
    : > "${DELEGATE_TEST_CALLS}"

    REPO="${TEST_DIR}/repo"
    mkdir -p "${REPO}"
    git -C "${REPO}" init -q
    printf 'original\n' > "${REPO}/tracked.txt"
    git -C "${REPO}" add tracked.txt
    git -C "${REPO}" -c user.name=t -c user.email=t@t -c commit.gpgsign=false commit -q -m init
}

# Runs the script with the stubs and the base system tools only, so the real
# pi, opencode, codex and claude are never found.
delegate() {
    PATH="${BIN}:/usr/bin:/bin" bash "${DELEGATE}" "$@"
}

# Runs delegate inside the test repository.
in_repo() {
    cd "${REPO}" && delegate "$@"
}

# Removes a stub, so the tool looks uninstalled.
hide() {
    rm -f "${BIN}/${1}"
}

# True when the last `run` output contains the phrase, ignoring case.
has() {
    printf '%s' "${output}" | rg -qiF -- "${1}"
}

# True when the recorded executor calls contain the phrase.
called_with() {
    rg -qF -- "${1}" "${DELEGATE_TEST_CALLS}"
}

# A bare `! command` fails a bats test only as its last command; these two fail anywhere.
lacks() {
    ! has "${1}"
}

not_called_with() {
    ! called_with "${1}"
}

# True when no process has the pid.
gone() {
    ! kill -0 "${1}" 2>/dev/null
}

# Retries a command until it succeeds, for five seconds at most: a pid file appears a moment
# after the script starts, and a killed process stays visible until it is reaped.
eventually() {
    local attempt

    for (( attempt = 0; attempt < POLL_ATTEMPTS; attempt++ )); do
        "$@" && return 0

        sleep "${POLL_INTERVAL}"
    done

    return 1
}

# Starts the script inside the test repository as a background job of the test and sets
# script_pid. The script is the job itself, so a signal to that pid reaches it; 3>&- keeps
# the job off the file descriptor bats waits on.
start_in_repo() {
    cd "${REPO}" || return 1
    PATH="${BIN}:/usr/bin:/bin" bash "${DELEGATE}" "$@" > /dev/null 2>&1 3>&- &
    script_pid=$!
}

# --- usage ------------------------------------------------------------------

@test "help prints usage" {
    run delegate --help
    [ "${status}" -eq 0 ]
    has "Usage: delegate.sh"
    has "--executor"
    has "--read-only"
    has "--timeout"
}

@test "no task exits 2 with usage" {
    run delegate < /dev/null
    [ "${status}" -eq 2 ]
    has "no task given"
    has "Usage: delegate.sh"
}

@test "options without a value, unknown options and unknown executors exit 2" {
    local cases=("--executor" "--via" "--model" "--session" "--thinking" "--timeout" "--bogus" "--executor nope"
                 "--via tmux" "--timeout 5x" "--timeout 0") \
          option

    for option in "${cases[@]}"; do
        # shellcheck disable=SC2086 # the option may carry a value
        run in_repo ${option} "do the thing" < /dev/null
        [ "${status}" -eq 2 ]
    done
}

@test "a timeout with a leading zero is read as a decimal number" {
    local cases=("08" "09m") \
          duration

    for duration in "${cases[@]}"; do
        run in_repo --timeout "${duration}" "do the thing"
        [ "${status}" -eq 0 ]
    done

    DELEGATE_STUB_SLEEP=20 run in_repo --timeout 01s "do the thing"
    [ "${status}" -eq 4 ]
    has "- Status: failed (timeout after 1s)"
}

@test "DELEGATE_KILL_GRACE takes whole seconds only" {
    local cases=("soon" "1s" "-1" "1.5") \
          grace

    for grace in "${cases[@]}"; do
        DELEGATE_KILL_GRACE="${grace}" run in_repo "do the thing"
        [ "${status}" -eq 2 ]
        has "invalid DELEGATE_KILL_GRACE ${grace}"
    done
}

# --- executor resolution ----------------------------------------------------

@test "auto takes pi when it is installed and has credentials" {
    run in_repo "do the thing"
    [ "${status}" -eq 0 ]
    has "- Executor: pi"
    called_with "pi: auth check --model zai/glm-5.3"
    called_with "pi: -p"
}

@test "auto falls back to opencode when pi is missing or has no credentials" {
    hide pi
    run in_repo "do the thing"
    [ "${status}" -eq 0 ]
    has "- Executor: opencode"
    called_with "opencode: run"

    ln -s "${MOCKS}/pi" "${BIN}/pi"
    : > "${DELEGATE_TEST_CALLS}"
    DELEGATE_STUB_AUTH_STATUS=1 run in_repo "do the thing"
    [ "${status}" -eq 0 ]
    has "- Executor: opencode"
    not_called_with "pi: -p"
}

@test "auto falls back to tuios with the first installed executor when pi and opencode are missing" {
    hide pi
    hide opencode
    run in_repo "do the thing"
    [ "${status}" -eq 0 ]
    has "- Executor: codex via tuios"
    called_with "tuios: ls"
    called_with "--ready-timeout 120000 codex --"

    : > "${DELEGATE_TEST_CALLS}"
    DELEGATE_TUIOS_EXECUTOR=claude run in_repo "do the thing"
    [ "${status}" -eq 0 ]
    has "- Executor: claude via tuios"
}

@test "auto aborts when no executor and no tuios can run" {
    hide opencode
    hide tuios
    DELEGATE_STUB_AUTH_STATUS=1 run in_repo "do the thing"
    [ "${status}" -eq 1 ]
    has "no credentials for zai/glm-5.3"
    has "opencode and tuios are not available"

    hide pi
    run in_repo "do the thing"
    [ "${status}" -eq 1 ]
    has "no executor found"
}

@test "an explicit pi without credentials aborts before any run" {
    DELEGATE_STUB_AUTH_STATUS=1 run in_repo --executor pi "do the thing"
    [ "${status}" -eq 1 ]
    has "no credentials for zai/glm-5.3"
    has "ZAI_API_KEY"
    not_called_with "pi: -p"
}

@test "an explicit executor missing from PATH aborts" {
    hide codex
    run in_repo --executor codex "do the thing"
    [ "${status}" -eq 1 ]
    has "codex not found on PATH"
}

@test "pi runs with the hermetic agent dir and offline mode" {
    run in_repo "do the thing"
    [ "${status}" -eq 0 ]
    [ "$(rg -c "agent_dir: ${DELEGATE_STATE_DIR}/agent" "${DELEGATE_TEST_CALLS}")" -eq 2 ]
    [ "$(rg -c 'offline: 1' "${DELEGATE_TEST_CALLS}")" -eq 2 ]
}

@test "the state directory is made private to the user" {
    run in_repo "do the thing"
    [ "${status}" -eq 0 ]
    [ -n "$(find "${DELEGATE_STATE_DIR}" -maxdepth 0 -perm 700)" ]
}

@test "a state directory that is a symbolic link is refused before anything is written" {
    mkdir "${TEST_DIR}/elsewhere"
    ln -s "${TEST_DIR}/elsewhere" "${TEST_DIR}/linked"

    DELEGATE_STATE_DIR="${TEST_DIR}/linked" run in_repo "do the thing"
    [ "${status}" -eq 1 ]
    has "is a link or belongs to another user"
    not_called_with "pi:"
    [ -z "$(find "${TEST_DIR}/elsewhere" -mindepth 1)" ]
}

# --- dispatch ---------------------------------------------------------------

@test "each executor gets its headless flags, default model and a session" {
    local cases=(
        "pi|pi: -p --mode json --no-approve --no-mcp --no-extensions --no-skills --no-prompt-templates --model zai/glm-5.3 --thinking medium --exclude-tools ask_question --append-system-prompt ${PROMPT} --session-dir ${DELEGATE_STATE_DIR}/sessions --session-id "
        "opencode|opencode: run --standalone --auto --model zai-coding-plan/glm-5.3 --session "
        "codex|codex: exec -s workspace-write --json --skip-git-repo-check --output-last-message "
        "claude|claude: -p --model sonnet --permission-mode acceptEdits --output-format text --append-system-prompt "
    ) \
        entry \
        executor \
        expected

    for entry in "${cases[@]}"; do
        executor="${entry%%|*}"
        expected="${entry#*|}"
        : > "${DELEGATE_TEST_CALLS}"

        run in_repo --executor "${executor}" "do the thing"
        [ "${status}" -eq 0 ]
        has "- Executor: ${executor}"
        called_with "${expected}"
    done
}

@test "the task reaches each executor with the contract where no system prompt flag exists" {
    run in_repo --executor pi "do the thing"
    called_with "stdin: do the thing"
    not_called_with "-- do the thing"

    : > "${DELEGATE_TEST_CALLS}"
    run in_repo --executor opencode "do the thing"
    called_with "# Executor contract"
    called_with "do the thing"

    : > "${DELEGATE_TEST_CALLS}"
    run in_repo --executor codex "do the thing"
    called_with "stdin: # Executor contract"
    called_with "do the thing"
    not_called_with "--model"

    : > "${DELEGATE_TEST_CALLS}"
    run in_repo --executor claude "do the thing"
    called_with "--append-system-prompt # Executor contract"
    called_with "stdin: do the thing"
    called_with "quiet: true"
    called_with "--session-id "
}

@test "read-only maps to each executor's read tools" {
    local cases=(
        "pi|--tools read,grep,find,ls"
        "opencode|--agent plan"
        "codex|-s read-only"
        "claude|--tools Read,Grep,Glob"
    ) \
        entry \
        executor \
        expected

    for entry in "${cases[@]}"; do
        executor="${entry%%|*}"
        expected="${entry#*|}"
        : > "${DELEGATE_TEST_CALLS}"

        run in_repo --executor "${executor}" --read-only "do the thing"
        [ "${status}" -eq 0 ]
        called_with "${expected}"
    done

    : > "${DELEGATE_TEST_CALLS}"
    run in_repo --executor pi "do the thing"
    not_called_with "--tools"
}

@test "a feedback round continues each executor's session" {
    local cases=(
        "pi|--session-id round-2"
        "opencode|--session round-2"
        "codex|codex: exec resume round-2"
        "claude|--resume round-2"
    ) \
        entry \
        executor \
        expected

    for entry in "${cases[@]}"; do
        executor="${entry%%|*}"
        expected="${entry#*|}"
        : > "${DELEGATE_TEST_CALLS}"

        run in_repo --executor "${executor}" --session round-2 "apply the findings"
        [ "${status}" -eq 0 ]
        called_with "${expected}"
        has "- Session: round-2 (feedback round: delegate.sh --via direct --executor ${executor} --session round-2"
    done

    not_called_with "-s workspace-write"
}

@test "a codex feedback round keeps its sandbox" {
    local cases=(
        "|sandbox_mode=workspace-write"
        "--read-only|sandbox_mode=read-only"
    ) \
        entry \
        option \
        expected

    for entry in "${cases[@]}"; do
        option="${entry%%|*}"
        expected="${entry#*|}"
        : > "${DELEGATE_TEST_CALLS}"

        # shellcheck disable=SC2086 # the option may be empty
        run in_repo --executor codex ${option} --session round-2 "apply the findings"
        [ "${status}" -eq 0 ]
        called_with "codex: exec resume round-2 -c ${expected}"
    done
}

@test "models come from --model or the executor's environment variable" {
    local cases=(
        "pi|DELEGATE_PI_MODEL"
        "opencode|DELEGATE_OPENCODE_MODEL"
        "codex|DELEGATE_CODEX_MODEL"
        "claude|DELEGATE_CLAUDE_MODEL"
    ) \
        entry \
        executor \
        variable

    for entry in "${cases[@]}"; do
        executor="${entry%%|*}"
        variable="${entry#*|}"
        : > "${DELEGATE_TEST_CALLS}"

        run in_repo --executor "${executor}" --model flag/model "do the thing"
        [ "${status}" -eq 0 ]
        called_with "--model flag/model"
        has "- Model: flag/model"

        : > "${DELEGATE_TEST_CALLS}"
        env "${variable}=env/model" bash -c "cd '${REPO}' && PATH='${BIN}:/usr/bin:/bin' bash '${DELEGATE}' --executor '${executor}' 'do the thing'" > /dev/null
        called_with "--model env/model"
    done
}

@test "codex reports the thread id from its event stream and the result from its output file" {
    DELEGATE_STUB_THREAD_ID=thread-123 DELEGATE_STUB_RESULT="codex says done" run in_repo --executor codex "do the thing"
    [ "${status}" -eq 0 ]
    has "- Session: thread-123 (feedback round: delegate.sh --via direct --executor codex --session thread-123"
    has "codex says done"

    run in_repo --executor codex "do the thing"
    [ "${status}" -eq 0 ]
    has "- Session: unknown (codex printed no session id; feedback round unavailable)"
}

@test "a new session id is generated when none is given" {
    run in_repo "do the thing"
    [ "${status}" -eq 0 ]
    printf '%s' "${output}" | rg -q -- '^- Session: [0-9a-z][0-9a-z.-]+ \(feedback round'
}

@test "task is read from stdin with a dash, words are joined otherwise" {
    run in_repo - <<< "multi
line spec"
    [ "${status}" -eq 0 ]
    called_with "stdin: multi"
    called_with "line spec"

    run in_repo fix the -- flag parsing
    [ "${status}" -eq 0 ]
    called_with "stdin: fix the flag parsing"
}

# --- outcome signals --------------------------------------------------------

@test "pi reports the result, session, usage and actual model from its JSON stream" {
    DELEGATE_STUB_RESULT="done, see ## Report" DELEGATE_STUB_SESSION_ID=stream-7 run in_repo "do the thing"
    [ "${status}" -eq 0 ]
    has "- Status: ok"
    has "- Session: stream-7 (feedback round: delegate.sh --via direct --executor pi --session stream-7"
    has "- Actual model: zai/glm-5.3"
    has "- Usage: 10 in, 5 out, cost 0.75"
    has "first part"
    has "done, see ## Report"
    lacks '"type":"message_end"'
    lacks "thinking aloud"
}

@test "a pi run that ends with stopReason error fails even when pi exits 0" {
    DELEGATE_STUB_STOP_REASON=error DELEGATE_STUB_ERROR_MESSAGE="Connection error.: Proxy response (403)" \
        run in_repo "do the thing"
    [ "${status}" -eq 1 ]
    has "- Status: failed (stopReason error)"
    has "## Error"
    has "Proxy response (403)"
}

@test "lines on pi's stdout that are not events do not cost the report" {
    local cases=("warning: not json" "31337" '{"level":"warn"}' '{"type":"message_end","mess') \
          noise

    for noise in "${cases[@]}"; do
        DELEGATE_STUB_NOISE="${noise}" DELEGATE_STUB_RESULT="done, see ## Report" \
            run in_repo --session round-1 "do the thing"
        [ "${status}" -eq 0 ]
        has "- Status: ok"
        has "- Usage: 10 in, 5 out, cost 0.75"
        has "done, see ## Report"
        lacks "${noise}"
    done
}

@test "a pi run without an assistant message fails even when pi exits 0" {
    DELEGATE_STUB_SILENT=1 run in_repo "do the thing"
    [ "${status}" -eq 1 ]
    has "- Status: failed (no assistant message)"
    has "## Error"
    has "without an assistant message"
}

# --- watchdog ---------------------------------------------------------------

@test "the watchdog kills a direct executor that exceeds the timeout and exits 4" {
    DELEGATE_STUB_SLEEP=20 run in_repo --timeout 1s "do the thing"
    [ "${status}" -eq 4 ]
    has "- Status: failed (timeout after 1s)"
    has "## Error"
    has "did not finish within 1s"

    DELEGATE_STUB_SLEEP=20 DELEGATE_TIMEOUT=1 run in_repo --executor claude "do the thing"
    [ "${status}" -eq 4 ]
    has "- Status: failed (timeout after 1s)"
}

@test "an executor that ignores SIGTERM is killed after the grace period" {
    local cases=("pi" "claude") \
          executor \
          pid_file="${TEST_DIR}/executor.pid"

    for executor in "${cases[@]}"; do
        : > "${pid_file}"

        DELEGATE_STUB_SLEEP=20 DELEGATE_STUB_IGNORE_TERM=1 DELEGATE_STUB_PID_FILE="${pid_file}" DELEGATE_KILL_GRACE=1 \
            run in_repo --executor "${executor}" --timeout 1s "do the thing"
        [ "${status}" -eq 4 ]
        has "- Status: failed (timeout after 1s)"
        [ -s "${pid_file}" ]
        eventually gone "$(cat "${pid_file}")"
    done
}

@test "a timeout keeps the provider error from pi's unfinished stream" {
    DELEGATE_STUB_STOP_REASON=error DELEGATE_STUB_ERROR_MESSAGE="Connection error.: Proxy response (403)" \
        DELEGATE_STUB_HANG=20 run in_repo --timeout 1s "do the thing"
    [ "${status}" -eq 4 ]
    has "- Status: failed (timeout after 1s)"
    has "did not finish within 1s"
    has "Proxy response (403)"
}

@test "a signal to the script stops an executor that ignores SIGTERM" {
    local cases=("TERM|143" "HUP|129") \
          entry \
          signal \
          expected \
          script_status \
          pid_file="${TEST_DIR}/executor.pid"

    for entry in "${cases[@]}"; do
        signal="${entry%%|*}"
        expected="${entry#*|}"
        script_status=0
        : > "${pid_file}"

        DELEGATE_STUB_SLEEP=20 DELEGATE_STUB_IGNORE_TERM=1 DELEGATE_STUB_PID_FILE="${pid_file}" DELEGATE_KILL_GRACE=1 \
            start_in_repo "do the thing"
        eventually test -s "${pid_file}"

        kill -s "${signal}" "${script_pid}"
        wait "${script_pid}" || script_status=$?
        [ "${script_status}" -eq "${expected}" ]
        eventually gone "$(cat "${pid_file}")"
    done
}

@test "the watchdog outlives a kill -9 of the script and stops the executor at the limit" {
    local pid_file="${TEST_DIR}/executor.pid"

    DELEGATE_STUB_SLEEP=20 DELEGATE_STUB_PID_FILE="${pid_file}" start_in_repo --timeout 2s "do the thing"
    eventually test -s "${pid_file}"

    kill -KILL "${script_pid}"
    wait "${script_pid}" || true
    eventually gone "$(cat "${pid_file}")"
}

# --- tuios transport --------------------------------------------------------

@test "tuios starts the executor in a pane, asks it the task and reports the reply" {
    run in_repo --via tuios --executor pi "do the thing"
    [ "${status}" -eq 0 ]
    has "- Executor: pi via tuios"
    has "- Pane: dlg-"
    has "in tuios session delegate (tuios attach delegate; tuios close-window dlg-"
    has "- Status: ok, executor idle"
    has "stub result"
    called_with "tuios: start-agent --name dlg-"
    called_with "--cwd ${REPO} -s delegate --grants none --ready-timeout 120000 pi -- --model zai/glm-5.3 --no-approve"
    called_with "tuios: ask-agent -w dlg-"
    called_with "-s delegate --timeout 1800000 --lines 400 # Executor contract"
    called_with "do the thing"

    : > "${DELEGATE_TEST_CALLS}"
    TUIOS_SESSION=main run in_repo --via tuios --executor pi "do the thing"
    [ "${status}" -eq 0 ]
    called_with "-s main --grants none"
    called_with "ask-agent -w dlg-"
    has "in tuios session main"
}

@test "tuios passes each executor its interactive flags and read-only mode" {
    local cases=(
        "pi|pi -- --model zai/glm-5.3 --no-approve --tools read,grep,find,ls"
        "opencode|opencode -- --model zai-coding-plan/glm-5.3 --agent plan"
        "codex|codex -- -s read-only"
        "claude|claude -- --model sonnet --tools Read,Grep,Glob"
    ) \
        entry \
        executor \
        expected

    for entry in "${cases[@]}"; do
        executor="${entry%%|*}"
        expected="${entry#*|}"
        : > "${DELEGATE_TEST_CALLS}"

        run in_repo --via tuios --executor "${executor}" --read-only "do the thing"
        [ "${status}" -eq 0 ]
        called_with "${expected}"
    done
}

@test "a tuios feedback round asks the existing agent without a new pane" {
    run in_repo --via tuios --executor pi --session dlg-abc "apply the findings"
    [ "${status}" -eq 0 ]
    has "- Session: dlg-abc (feedback round: delegate.sh --via tuios --executor pi --session dlg-abc"
    called_with "tuios: ask-agent -w dlg-abc"
    not_called_with "start-agent"
}

@test "a blocked tuios agent exits 3, shows its prompt and says where to answer" {
    DELEGATE_STUB_TUIOS_STATE=needs_input run in_repo --via tuios --executor pi "do the thing"
    [ "${status}" -eq 3 ]
    has "- Status: blocked (answer the prompt in tuios pane dlg-"
    has ", executor needs_input"
    has "## Prompt"
    has "Allow edit of tracked.txt?"
    lacks "## Error"
}

@test "tuios without a running daemon aborts" {
    DELEGATE_STUB_TUIOS_SERVER=0 run in_repo --via tuios --executor pi "do the thing"
    [ "${status}" -eq 1 ]
    has "tuios daemon is not running"
}

# --- report -----------------------------------------------------------------

@test "report carries the executor result and the git changes" {
    DELEGATE_STUB_RESULT="done, see ## Report" DELEGATE_STUB_WRITE_FILE="${REPO}/tracked.txt" run in_repo "do the thing"
    [ "${status}" -eq 0 ]
    has "# Delegate report"
    has "- Model: zai/glm-5.3"
    has "- Status: ok"
    has "## Result"
    has "done, see ## Report"
    has "## Changes"
    has " M tracked.txt"
    has "1 file changed"
    lacks "## Error"
}

@test "report says none without changes and not a git repository outside one" {
    run in_repo "do the thing"
    [ "${status}" -eq 0 ]
    printf '%s' "${output}" | rg -qUF -- "## Changes

none"

    mkdir -p "${TEST_DIR}/plain"
    run bash -c "cd '${TEST_DIR}/plain' && PATH='${BIN}:/usr/bin:/bin' bash '${DELEGATE}' 'do the thing'"
    [ "${status}" -eq 0 ]
    has "not a git repository"
}

@test "executor failure exits 1 and reports the exit code, stderr and changes" {
    DELEGATE_STUB_RUN_STATUS=3 DELEGATE_STUB_WRITE_FILE="${REPO}/partial.txt" run in_repo --executor claude "do the thing"
    [ "${status}" -eq 1 ]
    has "- Status: failed (exit 3)"
    has "## Error"
    has "provider rejected the request (401)"
    has "?? partial.txt"
}

@test "a read-only run reports whether the tree changed" {
    run in_repo --read-only "do the thing"
    [ "${status}" -eq 0 ]
    has "- Read-only check: unchanged"

    DELEGATE_STUB_WRITE_FILE="${REPO}/new.txt" run in_repo --read-only "do the thing"
    [ "${status}" -eq 0 ]
    has "- Read-only check: CHANGED"

    printf 'draft\n' > "${REPO}/draft.txt"
    DELEGATE_STUB_WRITE_FILE="${REPO}/draft.txt" run in_repo --read-only "do the thing"
    has "- Read-only check: CHANGED"

    mkdir -p "${TEST_DIR}/plain"
    run bash -c "cd '${TEST_DIR}/plain' && PATH='${BIN}:/usr/bin:/bin' bash '${DELEGATE}' --read-only 'do the thing'"
    has "- Read-only check: unknown (not a git repository)"

    run in_repo "do the thing"
    lacks "Read-only check"
}

@test "the read-only check sees a change to a file that was already dirty" {
    local cases=("tracked.txt" $'caf\xc3\xa9.txt') \
          name

    for name in "${cases[@]}"; do
        printf 'draft\n' > "${REPO}/${name}"

        DELEGATE_STUB_WRITE_FILE="${REPO}/${name}" run in_repo --read-only "do the thing"
        [ "${status}" -eq 0 ]
        has "- Read-only check: CHANGED"
    done
}

@test "an unreadable untracked file does not void the read-only check" {
    printf 'draft\n' > "${REPO}/locked.txt"
    chmod 000 "${REPO}/locked.txt"

    run in_repo --read-only "do the thing"
    [ "${status}" -eq 0 ]
    has "- Read-only check: unchanged"

    DELEGATE_STUB_WRITE_FILE="${REPO}/new.txt" run in_repo --read-only "do the thing"
    has "- Read-only check: CHANGED"
}

@test "the read-only check does not run the repository's diff drivers" {
    local cases=("textconv" "command") \
          driver \
          spy="${TEST_DIR}/spy" \
          marker="${TEST_DIR}/spy.ran"

    printf '#!/usr/bin/env bash\n: > "%s"\ncat "${1}"\n' "${marker}" > "${spy}"
    chmod +x "${spy}"
    mkdir -p "${REPO}/.git/info"
    printf '*.txt diff=spy\n' > "${REPO}/.git/info/attributes"
    printf 'draft\n' > "${REPO}/tracked.txt"

    for driver in "${cases[@]}"; do
        git -C "${REPO}" config "diff.spy.${driver}" "${spy}"

        run in_repo --read-only "do the thing"
        [ "${status}" -eq 0 ]
        has "- Read-only check: unchanged"
        [ ! -e "${marker}" ]

        git -C "${REPO}" config --unset "diff.spy.${driver}"
    done
}

@test "a failed run keeps its files and the report says where" {
    local cases=(
        "DELEGATE_STUB_RUN_STATUS=3|--executor claude"
        "DELEGATE_STUB_STOP_REASON=error|--executor pi"
        "DELEGATE_STUB_SLEEP=20|--executor pi --timeout 1s"
    ) \
        entry \
        setting \
        options \
        kept

    for entry in "${cases[@]}"; do
        setting="${entry%%|*}"
        options="${entry#*|}"
        rm -rf "${DELEGATE_STATE_DIR}"/run.*

        run env "${setting}" bash -c "cd '${REPO}' && PATH='${BIN}:/usr/bin:/bin' bash '${DELEGATE}' ${options} 'do the thing'"
        [ "${status}" -ne 0 ]
        kept="$(find "${DELEGATE_STATE_DIR}" -maxdepth 1 -name 'run.*')"
        [ -d "${kept}" ]
        has "- Run files: ${kept}"
        [ -f "${kept}/stdout" ]
        [ -f "${kept}/stderr" ]
    done
}

@test "a successful run removes its run directory" {
    run in_repo "do the thing"
    [ "${status}" -eq 0 ]
    [ -z "$(find "${DELEGATE_STATE_DIR}" -maxdepth 1 -name 'run.*')" ]
}
