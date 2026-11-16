#!/usr/bin/env bash
# Dispatches one bounded task to an executor model and prints a report for the
# orchestrator to validate. See ../SKILL.md for the loop.
#
# Self-contained on purpose: it runs from ~/.config/claude/skills/delegation/,
# outside the dotfiles repository, so scripts/common.sh is not available.
#
# Usage: delegate.sh [options] [--] <task...>
#        delegate.sh [options] - < spec.md
#
# Options:
#   -x, --executor <name>    auto (default), pi, opencode, codex or claude. auto takes pi
#                            when it is installed and has credentials, then opencode,
#                            then any installed executor inside tuios.
#   -v, --via <transport>    direct (default): headless subprocess. tuios: the executor
#                            runs interactively in a tuios pane; you answer its prompts.
#   -m, --model <id>         executor model id (defaults below)
#   -s, --session <id>       continue an executor session (feedback round)
#   -t, --thinking <level>   pi only: off, minimal, low, medium, high, xhigh, max
#   -r, --read-only          analysis only: read tools, no edits; the report says whether
#                            the tree changed anyway
#   -T, --timeout <dur>      direct transport: stop the executor after <dur> (default 30m;
#                            seconds, or <n>s, <n>m, <n>h)
#   -h, --help               this text
#
# Default models: pi zai/glm-5.3, opencode zai-coding-plan/glm-5.3, codex its own
# default, claude sonnet. Override with DELEGATE_PI_MODEL, DELEGATE_OPENCODE_MODEL,
# DELEGATE_CODEX_MODEL, DELEGATE_CLAUDE_MODEL.
#
# Environment: DELEGATE_EXECUTOR, DELEGATE_VIA, DELEGATE_THINKING, DELEGATE_TIMEOUT
# (default 30m), DELEGATE_KILL_GRACE (seconds between SIGTERM and SIGKILL, default 10),
# DELEGATE_STATE_DIR (default ${TMPDIR}/delegate), DELEGATE_CODEX_SANDBOX
# (default workspace-write), DELEGATE_TUIOS_EXECUTOR, DELEGATE_TUIOS_SESSION (default: the
# current tuios session, else "delegate"), DELEGATE_TUIOS_TIMEOUT_MS (default 1800000),
# DELEGATE_TUIOS_LINES (default 400), and the provider key the executor needs, e.g.
# ZAI_API_KEY for zai/*.
#
# A run that fails or times out keeps its files (the executor's stdout and stderr) in a
# run.* directory under DELEGATE_STATE_DIR; the report names it.
#
# Exit: 0 executor finished, 1 executor or credential failure, 2 usage,
#       3 executor blocked on a prompt in its tuios pane,
#       4 executor stopped by the watchdog (DELEGATE_TIMEOUT),
#       129, 130, 143 after SIGHUP, SIGINT, SIGTERM: the executor is stopped first.

set -Eeuo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly SKILL_DIR
readonly EXECUTOR_PROMPT="${SKILL_DIR}/executor-prompt.md"
readonly EXECUTORS="pi opencode codex claude"
readonly DEFAULT_PI_MODEL="zai/glm-5.3"
readonly DEFAULT_OPENCODE_MODEL="zai-coding-plan/glm-5.3"
readonly DEFAULT_CLAUDE_MODEL="sonnet"
readonly DEFAULT_CODEX_SANDBOX="workspace-write"
readonly PI_READ_ONLY_TOOLS="read,grep,find,ls"
readonly CLAUDE_READ_ONLY_TOOLS="Read,Grep,Glob"
readonly OPENCODE_READ_ONLY_AGENT="plan"
readonly CODEX_READ_ONLY_SANDBOX="read-only"
readonly CODEX_THREAD_EVENT="thread.started"
readonly HEADLESS_EXCLUDED_TOOLS="ask_question"
readonly TUIOS_NAME_PREFIX="dlg-"
readonly TUIOS_DEFAULT_SESSION="delegate"
readonly TUIOS_READY_TIMEOUT_MS=120000
readonly TUIOS_BLOCKED_STATE="needs_input"
readonly UNKNOWN_SESSION="unknown"
readonly STDERR_TAIL_LINES=20
readonly STATE_DIR_MODE=700
readonly STATE_DIR_UMASK=077
readonly DEFAULT_TIMEOUT="30m"
readonly DEFAULT_KILL_GRACE=10
readonly POLL_SECONDS=1
readonly PI_FAILED_STOP_REASONS="error aborted"
readonly READ_ONLY_UNKNOWN="unknown (not a git repository)"
readonly READ_ONLY_UNCHANGED="unchanged"
readonly READ_ONLY_CHANGED="CHANGED (the tree moved during a read-only run; inspect it before trusting the result)"
readonly EXIT_OK=0
readonly EXIT_FAILURE=1
readonly EXIT_USAGE=2
readonly EXIT_BLOCKED=3
readonly EXIT_TIMEOUT=4
readonly EXIT_HUP=129
readonly EXIT_INT=130
readonly EXIT_TERM=143

# jq: the events of pi's stream the report is built from, as one array. A line that is not
# a JSON object is dropped, so a stray line on stdout does not cost the whole report. Only
# the session header and the finished messages are kept; the stream also carries every delta.
readonly PI_EVENTS_FILTER='[ inputs | fromjson? | objects | select(.type == "session" or .type == "message_end") ]'
# jq over those events: the id of the session header.
readonly PI_SESSION_FILTER='[ .[] | select(.type == "session") | .id ] | first // empty'
# jq over those events: every assistant text part, blank-line separated.
readonly PI_RESULT_FILTER='
    [ .[] | select(.type == "message_end" and .message.role == "assistant") | .message.content
      | if type == "string" then . else [ .[]? | select(.type? == "text") | .text ] | join("\n") end
      | select(length > 0) ]
    | join("\n\n")'
# jq over those events: one line, fields split by the unit separator (0x1f):
# the last assistant message's stopReason, provider/model and errorMessage, plus the token
# and cost totals over every assistant message.
# shellcheck disable=SC2016 # $all is a jq variable, not a shell expansion
readonly PI_OUTCOME_FILTER='
    [ .[] | select(.type == "message_end" and .message.role == "assistant") | .message ]
    | select(length > 0) | . as $all | last
    | [ (.stopReason // ""),
        (if .provider then "\(.provider)/\(.model // "")" else (.model // "") end),
        ($all | map(.usage.input // 0) | add),
        ($all | map(.usage.output // 0) | add),
        ((($all | map(.usage.cost.total // 0) | add) * 1000000 | round) / 1000000),
        (.errorMessage // "" | gsub("\n"; " ")) ]
    | map(tostring) | join("\u001f")'

DELEGATE_THINKING="${DELEGATE_THINKING:-medium}"
DELEGATE_TIMEOUT="${DELEGATE_TIMEOUT:-${DEFAULT_TIMEOUT}}"
DELEGATE_KILL_GRACE="${DELEGATE_KILL_GRACE:-${DEFAULT_KILL_GRACE}}"
DELEGATE_STATE_DIR="${DELEGATE_STATE_DIR:-${TMPDIR:-/tmp}/delegate}"
DELEGATE_TUIOS_SESSION="${DELEGATE_TUIOS_SESSION:-${TUIOS_SESSION:-${TUIOS_DEFAULT_SESSION}}}"
DELEGATE_TUIOS_TIMEOUT_MS="${DELEGATE_TUIOS_TIMEOUT_MS:-1800000}"
DELEGATE_TUIOS_LINES="${DELEGATE_TUIOS_LINES:-400}"

executor="${DELEGATE_EXECUTOR:-auto}"
via="${DELEGATE_VIA:-direct}"
model=""
read_only=false
resume=false
session_id=""
agent_state=""
blocked=false
task=""
run_dir=""
result_file=""
executor_status="${EXIT_OK}"
timeout_seconds=""
timeout_label=""
kill_grace=""
timed_out=false
keep_run=false
failure_reason=""
executor_error=""
actual_model=""
usage_line=""
tree_before=""
read_only_check=""
child_pid=""
watchdog_pid=""

usage() {
    sed -n '/^# Usage:/,/^#       129/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

log() {
    printf '==> %s\n' "$*" >&2
}

abort() {
    printf 'delegate: %s\n' "$*" >&2
    exit "${EXIT_FAILURE}"
}

usage_error() {
    printf 'delegate: %s\n\n' "$*" >&2
    usage >&2
    exit "${EXIT_USAGE}"
}

is_command() {
    command -v "${1}" &>/dev/null
}

append_task() {
    [[ -z "${task}" ]] && task="${1}" || task="${task} ${1}"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -h|--help)
                usage
                exit "${EXIT_OK}"
                ;;
            -x|--executor)
                [[ $# -ge 2 ]] || usage_error "${1} needs a value"
                executor="${2}"
                shift 2
                ;;
            -v|--via)
                [[ $# -ge 2 ]] || usage_error "${1} needs a value"
                via="${2}"
                shift 2
                ;;
            -m|--model)
                [[ $# -ge 2 ]] || usage_error "${1} needs a value"
                model="${2}"
                shift 2
                ;;
            -s|--session)
                [[ $# -ge 2 ]] || usage_error "${1} needs a value"
                session_id="${2}"
                resume=true
                shift 2
                ;;
            -t|--thinking)
                [[ $# -ge 2 ]] || usage_error "${1} needs a value"
                DELEGATE_THINKING="${2}"
                shift 2
                ;;
            -T|--timeout)
                [[ $# -ge 2 ]] || usage_error "${1} needs a value"
                DELEGATE_TIMEOUT="${2}"
                shift 2
                ;;
            -r|--read-only)
                read_only=true
                shift
                ;;
            -)
                task="$(cat)"
                shift
                ;;
            --)
                shift
                while [[ $# -gt 0 ]]; do
                    append_task "${1}"
                    shift
                done
                ;;
            -*)
                usage_error "unknown option ${1}"
                ;;
            *)
                append_task "${1}"
                shift
                ;;
        esac
    done
}

read_task() {
    [[ -n "${task}" ]] && return

    [[ -t 0 ]] || task="$(cat)"
    [[ -n "${task}" ]] || usage_error "no task given"
}

# True for a plain decimal number.
is_number() {
    [[ -n "${1}" && "${1}" != *[!0-9]* ]]
}

invalid_timeout() {
    usage_error "invalid timeout ${DELEGATE_TIMEOUT}: use seconds or <n>s, <n>m, <n>h"
}

# Accepts seconds or <n>h, <n>m, <n>s; sets timeout_seconds and the label for the report.
parse_timeout() {
    local value="${DELEGATE_TIMEOUT}" unit number

    unit="${value##*[0-9]}"
    number="${value%"${unit}"}"

    case "${unit}" in
        ''|h|m|s) ;;
        *) invalid_timeout ;;
    esac
    is_number "${number}" || invalid_timeout

    # 10# keeps a leading zero from being read as octal.
    number=$(( 10#${number} ))
    [[ "${number}" -gt 0 ]] || invalid_timeout

    case "${unit}" in
        h) timeout_seconds=$(( number * 3600 )) ;;
        m) timeout_seconds=$(( number * 60 )) ;;
        *) timeout_seconds="${number}" ;;
    esac
    timeout_label="${number}${unit:-s}"
}

# Seconds between SIGTERM and SIGKILL; zero sends both at once.
parse_kill_grace() {
    is_number "${DELEGATE_KILL_GRACE}" ||
        usage_error "invalid DELEGATE_KILL_GRACE ${DELEGATE_KILL_GRACE}: use whole seconds"

    kill_grace=$(( 10#${DELEGATE_KILL_GRACE} ))
}

# --- executor resolution ------------------------------------------------------

pi_model() {
    printf '%s\n' "${model:-${DELEGATE_PI_MODEL:-${DEFAULT_PI_MODEL}}}"
}

default_model() {
    case "${executor}" in
        pi) pi_model ;;
        opencode) printf '%s\n' "${DELEGATE_OPENCODE_MODEL:-${DEFAULT_OPENCODE_MODEL}}" ;;
        codex) printf '%s\n' "${DELEGATE_CODEX_MODEL:-}" ;;
        claude) printf '%s\n' "${DELEGATE_CLAUDE_MODEL:-${DEFAULT_CLAUDE_MODEL}}" ;;
    esac
}

# Runs pi with a hermetic config dir: ~/.pi is not writable inside the Claude
# Code sandbox, and the user's own extensions and MCP servers stay out of the executor.
run_pi_bin() {
    env PI_CODING_AGENT_DIR="${DELEGATE_STATE_DIR}/agent" \
        PI_OFFLINE=1 \
        PI_SKIP_VERSION_CHECK=1 \
        PI_TELEMETRY=0 \
        pi "$@"
}

pi_has_credentials() {
    run_pi_bin auth check --model "$(pi_model)" >/dev/null 2>&1
}

credentials_hint() {
    printf 'no credentials for %s: export the provider key (ZAI_API_KEY for zai/*)' "$(pi_model)"
}

tuios_reachable() {
    is_command tuios && tuios ls >/dev/null 2>&1
}

first_installed_executor() {
    local candidate

    for candidate in ${EXECUTORS}; do
        is_command "${candidate}" || continue

        printf '%s\n' "${candidate}"

        return
    done

    return 1
}

is_executor() {
    case " ${EXECUTORS} " in
        *" ${1} "*) return 0 ;;
    esac

    return 1
}

resolve_tuios_executor() {
    tuios_reachable || abort "tuios daemon is not running: start a tuios session first"

    executor="${DELEGATE_TUIOS_EXECUTOR:-$(first_installed_executor)}" ||
        abort "tuios is running but no executor is installed: install pi, opencode, codex or claude"
}

resolve_auto() {
    [[ "${via}" == tuios ]] && {
        resolve_tuios_executor

        return
    }

    if is_command pi && pi_has_credentials; then
        executor=pi
    elif is_command opencode; then
        executor=opencode
    elif tuios_reachable; then
        via=tuios
        resolve_tuios_executor
    elif is_command pi; then
        abort "$(credentials_hint); opencode and tuios are not available either"
    else
        abort "no executor found: install pi or opencode, start tuios, or pass --executor codex|claude"
    fi
}

resolve_explicit() {
    is_executor "${executor}" || usage_error "unknown executor ${executor}"
    is_command "${executor}" || abort "${executor} not found on PATH"

    [[ "${via}" == tuios ]] && {
        tuios_reachable || abort "tuios daemon is not running: start a tuios session first"

        return
    }

    [[ "${executor}" == pi ]] || return 0

    pi_has_credentials || abort "$(credentials_hint)"
}

resolve_executor() {
    case "${via}" in
        direct|tuios) ;;
        *) usage_error "unknown transport ${via}" ;;
    esac

    if [[ "${executor}" == auto ]]; then
        resolve_auto
    else
        resolve_explicit
    fi

    [[ -n "${model}" ]] || model="$(default_model)"
}

# The state directory holds pi's config and every task. A link or another user's directory
# in its place would hand both to someone else, so it has to be this user's own and private.
prepare_state_dir() {
    local refused="${DELEGATE_STATE_DIR} is a link or belongs to another user: point DELEGATE_STATE_DIR at a directory of your own"

    [[ ! -L "${DELEGATE_STATE_DIR}" ]] || abort "${refused}"
    ( umask "${STATE_DIR_UMASK}" && mkdir -p "${DELEGATE_STATE_DIR}/agent" "${DELEGATE_STATE_DIR}/sessions" ) ||
        abort "cannot create ${DELEGATE_STATE_DIR}"
    [[ -O "${DELEGATE_STATE_DIR}" && ! -L "${DELEGATE_STATE_DIR}" ]] || abort "${refused}"

    chmod "${STATE_DIR_MODE}" "${DELEGATE_STATE_DIR}"
}

check_prerequisites() {
    [[ -r "${EXECUTOR_PROMPT}" ]] || abort "executor prompt missing: ${EXECUTOR_PROMPT}"

    prepare_state_dir
}

new_session_id() {
    is_command uuidgen && {
        uuidgen | tr '[:upper:]' '[:lower:]'

        return
    }

    printf '%08x-%04x-4%03x-%04x-%04x%08x\n' "${RANDOM}${RANDOM}" "${RANDOM}" "${RANDOM}" "${RANDOM}" "${RANDOM}" "${RANDOM}${RANDOM}"
}

contract_text() {
    cat "${EXECUTOR_PROMPT}"
}

# Executors without a system-prompt flag get the contract ahead of the task.
prefixed_task() {
    printf '%s\n\n%s\n' "$(contract_text)" "${task}"
}

# Runs from the EXIT trap at the bottom of the file; ShellCheck does not see that call.
# A signal that ends this script while the executor runs stops the executor's process
# group and the watchdog first. The signals are ignored meanwhile: a second one must not
# cut that short. The run directory of a failed run stays; the report names it.
# shellcheck disable=SC2329
cleanup() {
    trap '' HUP INT TERM

    [[ -z "${child_pid}" ]] || stop_group
    [[ -z "${watchdog_pid}" ]] || kill -KILL -- "-${watchdog_pid}" 2>/dev/null || true
    [[ -n "${run_dir}" && "${keep_run}" == false ]] || return 0

    rm -rf "${run_dir}"
}

# --- read-only check ------------------------------------------------------------

# One hash over the working tree: index and worktree changes, plus the content of the
# untracked files, which `git status` alone misses when they were already there. The
# diffs skip the user's external diff and textconv drivers: the fingerprint has to be
# quick and the same on every run.
tree_fingerprint() {
    local top
    top="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1

    (
        cd "${top}" || exit 1
        git status --porcelain
        git diff --no-ext-diff --no-textconv
        git diff --no-ext-diff --no-textconv --cached
        # An unreadable file hashes as its error line; it must not void the fingerprint.
        git ls-files -z --others --exclude-standard | xargs -0 shasum -a 256 -- 2>&1 || true
    ) 2>/dev/null | shasum -a 256
}

snapshot_tree() {
    [[ "${read_only}" == true ]] || return 0

    tree_before="$(tree_fingerprint)" || tree_before=""
}

# A read-only run is a promise by the executor's tool allowlist, not a guarantee:
# the tree is measured before and after, and the verdict goes into the report.
check_read_only() {
    [[ "${read_only}" == true ]] || return 0

    [[ -n "${tree_before}" ]] || {
        read_only_check="${READ_ONLY_UNKNOWN}"

        return
    }

    local tree_after
    tree_after="$(tree_fingerprint)" || tree_after=""

    if [[ "${tree_after}" == "${tree_before}" ]]; then
        read_only_check="${READ_ONLY_UNCHANGED}"
    else
        read_only_check="${READ_ONLY_CHANGED}"
    fi
}

# --- watchdog -------------------------------------------------------------------------

# True while the executor's process group still has a member.
group_alive() {
    kill -0 -- "-${child_pid}" 2>/dev/null
}

# SIGTERM for the executor's process group, then SIGKILL for what is left of it after the
# grace period: a member that ignores SIGTERM must not outlive the report.
stop_group() {
    local waited

    kill -TERM -- "-${child_pid}" 2>/dev/null || return 0

    for (( waited = 0; waited < kill_grace; waited += POLL_SECONDS )); do
        group_alive || return 0

        sleep "${POLL_SECONDS}"
    done

    kill -KILL -- "-${child_pid}" 2>/dev/null || true
}

# Body of the watchdog job: stops the executor's process group once the limit has passed.
# It polls instead of sleeping through the limit, so it leaves with the group and never
# signals a group id that something else took over later. It runs in its own process
# group and still enforces the limit after a kill -9 of this script.
watchdog() {
    local elapsed

    for (( elapsed = 0; elapsed < timeout_seconds; elapsed += POLL_SECONDS )); do
        group_alive || return 0

        sleep "${POLL_SECONDS}"
    done

    group_alive || return 0

    # Written before the signal: the script looks for it as soon as the executor is gone.
    : > "${run_dir}/timeout" || true
    stop_group
}

# Runs the executor as the leader of its own process group, so a stop reaches it together
# with any tool command it left running. Job control is on only while the two jobs start.
watched() {
    set -m
    "$@" &
    child_pid=$!
    watchdog &
    watchdog_pid=$!
    set +m

    # 2>/dev/null: bash reports a job that died of SIGKILL on stderr.
    wait "${child_pid}" 2>/dev/null || executor_status=$?

    # The marker says the watchdog is stopping the group: it finishes that before the report.
    [[ -f "${run_dir}/timeout" ]] && timed_out=true
    [[ "${timed_out}" == true ]] || kill -KILL -- "-${watchdog_pid}" 2>/dev/null || true
    wait "${watchdog_pid}" 2>/dev/null || true
    child_pid=""
    watchdog_pid=""

    [[ "${timed_out}" == true ]] || return 0

    executor_status="${EXIT_TIMEOUT}"
    failure_reason="timeout after ${timeout_label}"
    executor_error="${executor} did not finish within ${timeout_label}; the watchdog stopped its process group (SIGTERM, then SIGKILL after ${kill_grace}s for what was left)"
}

# --- direct executors -----------------------------------------------------------

# Runs a jq filter over the events kept from pi's stream.
pi_query() {
    jq -Rrn "${PI_EVENTS_FILTER} | ${1}" "${run_dir}/stdout" 2>/dev/null
}

# Fails the round on evidence from the event stream. An exit code or a timeout that already
# failed it keeps its own reason.
pi_fail() {
    [[ "${executor_status}" -eq "${EXIT_OK}" ]] || return 0

    executor_status="${EXIT_FAILURE}"
    failure_reason="${1}"
    [[ -n "${executor_error}" ]] || executor_error="${2}"
}

# The outcome lives in pi's event stream, not in its exit code: after a provider error pi
# exits 0 with stopReason "error" on its last assistant message.
pi_collect() {
    local stream_session outcome newline=$'\n'
    local stop_reason served usage_in usage_out usage_cost error_message

    stream_session="$(pi_query "${PI_SESSION_FILTER}")" || stream_session=""
    [[ -z "${stream_session}" ]] || session_id="${stream_session}"

    result_file="${run_dir}/result"
    pi_query "${PI_RESULT_FILTER}" > "${result_file}" || : > "${result_file}"

    outcome="$(pi_query "${PI_OUTCOME_FILTER}")" || outcome=""
    [[ -n "${outcome}" ]] || {
        pi_fail "no assistant message" "pi exited 0 without an assistant message in its event stream"

        return 0
    }

    IFS=$'\x1f' read -r stop_reason served usage_in usage_out usage_cost error_message <<< "${outcome}"
    actual_model="${served}"
    usage_line="${usage_in} in, ${usage_out} out, cost ${usage_cost}"
    # A provider error joins what is already known, such as the watchdog's account of a timeout.
    [[ -z "${error_message}" ]] || executor_error="${executor_error:+${executor_error}${newline}}${error_message}"

    case " ${PI_FAILED_STOP_REASONS} " in
        *" ${stop_reason} "*) ;;
        *) return 0 ;;
    esac

    pi_fail "stopReason ${stop_reason}" "pi ended with stopReason ${stop_reason}"
}

run_pi() {
    is_command jq || abort "jq is required for the pi executor"

    local -a args=(-p --mode json --no-approve --no-mcp --no-extensions --no-skills --no-prompt-templates
                   --model "${model}"
                   --thinking "${DELEGATE_THINKING}"
                   --exclude-tools "${HEADLESS_EXCLUDED_TOOLS}"
                   --append-system-prompt "${EXECUTOR_PROMPT}"
                   --session-dir "${DELEGATE_STATE_DIR}/sessions"
                   --session-id "${session_id}")

    [[ "${read_only}" == true ]] && args+=(--tools "${PI_READ_ONLY_TOOLS}")

    # The task goes in on stdin: it stays out of the process list and has no size limit.
    result_file="${run_dir}/stdout"
    printf '%s' "${task}" > "${run_dir}/task"
    watched run_pi_bin "${args[@]}" <"${run_dir}/task" >"${run_dir}/stdout" 2>"${run_dir}/stderr"

    pi_collect
}

run_opencode() {
    local -a args=(run --standalone --auto --model "${model}" --session "${session_id}")

    [[ "${read_only}" == true ]] && args+=(--agent "${OPENCODE_READ_ONLY_AGENT}")

    result_file="${run_dir}/stdout"
    watched opencode "${args[@]}" "$(prefixed_task)" </dev/null >"${run_dir}/stdout" 2>"${run_dir}/stderr"
}

codex_sandbox() {
    [[ "${read_only}" == true ]] && {
        printf '%s\n' "${CODEX_READ_ONLY_SANDBOX}"

        return
    }

    printf '%s\n' "${DELEGATE_CODEX_SANDBOX:-${DEFAULT_CODEX_SANDBOX}}"
}

codex_thread_id() {
    local thread_id
    thread_id="$(jq -r "select(.type == \"${CODEX_THREAD_EVENT}\") | .thread_id // empty" "${run_dir}/stdout" 2>/dev/null | head -n 1)"

    printf '%s\n' "${thread_id:-${UNKNOWN_SESSION}}"
}

run_codex() {
    is_command jq || abort "jq is required for the codex executor"

    local -a args=(exec)

    # `codex exec resume` has no -s: there the sandbox goes in as a config override.
    if [[ "${resume}" == true ]]; then
        args+=(resume "${session_id}" -c "sandbox_mode=$(codex_sandbox)")
    else
        args+=(-s "$(codex_sandbox)")
    fi

    [[ -n "${model}" ]] && args+=(--model "${model}")
    args+=(--json --skip-git-repo-check --output-last-message "${run_dir}/result" -)

    result_file="${run_dir}/result"
    prefixed_task > "${run_dir}/task"
    watched codex "${args[@]}" <"${run_dir}/task" >"${run_dir}/stdout" 2>"${run_dir}/stderr"

    [[ "${resume}" == true ]] || session_id="$(codex_thread_id)"
}

run_claude() {
    local -a args=(-p --model "${model}" --permission-mode acceptEdits --output-format text
                   --append-system-prompt "$(contract_text)")

    if [[ "${resume}" == true ]]; then
        args+=(--resume "${session_id}")
    else
        args+=(--session-id "${session_id}")
    fi

    [[ "${read_only}" == true ]] && args+=(--tools "${CLAUDE_READ_ONLY_TOOLS}")

    result_file="${run_dir}/stdout"
    printf '%s' "${task}" > "${run_dir}/task"
    watched env CLAUDE_QUIET=true claude "${args[@]}" <"${run_dir}/task" >"${run_dir}/stdout" 2>"${run_dir}/stderr"
}

# --- tuios transport ------------------------------------------------------------------

# Interactive flags for the agent tuios starts in the pane; the contract travels in the prompt.
tuios_agent_args() {
    case "${executor}" in
        pi)
            printf -- '--model %s --no-approve' "${model}"
            [[ "${read_only}" == true ]] && printf -- ' --tools %s' "${PI_READ_ONLY_TOOLS}"
            ;;
        opencode)
            printf -- '--model %s' "${model}"
            [[ "${read_only}" == true ]] && printf -- ' --agent %s' "${OPENCODE_READ_ONLY_AGENT}"
            ;;
        codex)
            [[ -n "${model}" ]] && printf -- '--model %s' "${model}"
            [[ "${read_only}" == true ]] && printf -- ' -s %s' "${CODEX_READ_ONLY_SANDBOX}"
            ;;
        claude)
            printf -- '--model %s' "${model}"
            [[ "${read_only}" == true ]] && printf -- ' --tools %s' "${CLAUDE_READ_ONLY_TOOLS}"
            ;;
    esac

    printf '\n'
}

tuios_agent_state() {
    tuios get-agent-state -w "${session_id}" -s "${DELEGATE_TUIOS_SESSION}" 2>/dev/null || printf 'unknown\n'
}

# A new pane with the executor at its prompt. A start that stops on the agent's own
# question (folder trust, login) leaves the pane for the person and counts as blocked.
tuios_start_agent() {
    local -a agent_args
    # shellcheck disable=SC2207 # the flags carry no spaces inside a value
    agent_args=($(tuios_agent_args))

    session_id="${TUIOS_NAME_PREFIX}${session_id%%-*}"

    # ${arr[@]+"${arr[@]}"} keeps an empty array from tripping set -u on Bash 3.2.
    tuios start-agent --name "${session_id}" --cwd "${PWD}" -s "${DELEGATE_TUIOS_SESSION}" \
        --grants none --ready-timeout "${TUIOS_READY_TIMEOUT_MS}" \
        "${executor}" -- ${agent_args[@]+"${agent_args[@]}"} >/dev/null 2>>"${run_dir}/stderr" && return

    agent_state="$(tuios_agent_state)"
    [[ "${agent_state}" == "${TUIOS_BLOCKED_STATE}" ]] ||
        abort "tuios start-agent failed for ${executor}: $(tail -n 1 "${run_dir}/stderr")"

    blocked=true
}

tuios_ask() {
    tuios ask-agent -w "${session_id}" -s "${DELEGATE_TUIOS_SESSION}" \
        --timeout "${DELEGATE_TUIOS_TIMEOUT_MS}" --lines "${DELEGATE_TUIOS_LINES}" \
        "$(prefixed_task)" >"${run_dir}/stdout" 2>>"${run_dir}/stderr" ||
        executor_status=$?

    agent_state="$(tuios_agent_state)"
    [[ "${agent_state}" == "${TUIOS_BLOCKED_STATE}" ]] || return 0

    blocked=true
    executor_status="${EXIT_OK}"
}

run_tuios() {
    result_file="${run_dir}/stdout"
    : > "${run_dir}/stdout"

    [[ "${resume}" == true ]] || tuios_start_agent
    [[ "${blocked}" == true ]] || tuios_ask
}

run_executor() {
    run_dir="$(mktemp -d "${DELEGATE_STATE_DIR}/run.XXXXXX")"

    log "delegating to ${executor} ${model:-default model} via ${via} (session ${session_id})"

    [[ "${via}" == tuios ]] && {
        run_tuios

        return
    }

    case "${executor}" in
        pi) run_pi ;;
        opencode) run_opencode ;;
        codex) run_codex ;;
        claude) run_claude ;;
    esac
}

# --- report -------------------------------------------------------------------

print_changes() {
    git rev-parse --is-inside-work-tree &>/dev/null || {
        printf 'not a git repository\n'

        return
    }

    local status
    status="$(git status --short)"

    [[ -n "${status}" ]] || {
        printf 'none\n'

        return
    }

    printf '%s\n\n' "${status}"
    git diff --stat
}

print_session() {
    [[ "${session_id}" != "${UNKNOWN_SESSION}" ]] || {
        printf -- '- Session: unknown (%s printed no session id; feedback round unavailable)\n' "${executor}"

        return
    }

    printf -- '- Session: %s (feedback round: delegate.sh --via %s --executor %s --session %s "<findings>")\n' \
        "${session_id}" "${via}" "${executor}" "${session_id}"
    [[ "${via}" == tuios ]] && printf -- '- Pane: %s in tuios session %s (tuios attach %s; tuios close-window %s -s %s when done)\n' \
        "${session_id}" "${DELEGATE_TUIOS_SESSION}" "${DELEGATE_TUIOS_SESSION}" "${session_id}" "${DELEGATE_TUIOS_SESSION}"

    return 0
}

print_status() {
    if [[ "${blocked}" == true ]]; then
        printf 'blocked (answer the prompt in tuios pane %s)' "${session_id}"
    elif [[ "${executor_status}" -eq "${EXIT_OK}" ]]; then
        printf 'ok'
    elif [[ -n "${failure_reason}" ]]; then
        printf 'failed (%s)' "${failure_reason}"
    else
        printf 'failed (exit %s)' "${executor_status}"
    fi

    [[ -n "${agent_state}" ]] && printf ', executor %s' "${agent_state}"
    printf '\n'
}

print_prompt() {
    [[ "${blocked}" == true ]] || return 0

    printf '## Prompt\n\n'
    tuios peek-prompt -w "${session_id}" -s "${DELEGATE_TUIOS_SESSION}" 2>/dev/null || printf 'tuios peek-prompt failed\n'
    printf '\n'
}

print_report() {
    printf '# Delegate report\n\n'
    printf -- '- Executor: %s via %s\n' "${executor}" "${via}"
    printf -- '- Model: %s\n' "${model:-default}"
    [[ -z "${actual_model}" ]] || printf -- '- Actual model: %s\n' "${actual_model}"
    [[ -z "${usage_line}" ]] || printf -- '- Usage: %s\n' "${usage_line}"
    print_session
    [[ -z "${read_only_check}" ]] || printf -- '- Read-only check: %s\n' "${read_only_check}"
    printf -- '- Status: %s\n' "$(print_status)"
    [[ "${keep_run}" == false ]] ||
        printf -- '- Run files: %s (kept because the run failed; delete it when done)\n' "${run_dir}"

    printf '\n## Result\n\n'
    [[ -f "${result_file}" ]] && cat "${result_file}"
    printf '\n'

    print_prompt

    [[ "${executor_status}" -eq "${EXIT_OK}" ]] || {
        printf '## Error\n\n'
        [[ -z "${executor_error}" ]] || printf '%s\n\n' "${executor_error}"
        tail -n "${STDERR_TAIL_LINES}" "${run_dir}/stderr"
        printf '\n'
    }

    printf '## Changes\n\n'
    print_changes
}

main() {
    parse_args "$@"
    read_task
    parse_timeout
    parse_kill_grace
    check_prerequisites
    resolve_executor

    [[ -n "${session_id}" ]] || session_id="$(new_session_id)"

    snapshot_tree
    run_executor
    check_read_only
    [[ "${executor_status}" -eq "${EXIT_OK}" ]] || keep_run=true
    print_report

    [[ "${timed_out}" == true ]] && exit "${EXIT_TIMEOUT}"
    [[ "${executor_status}" -eq "${EXIT_OK}" ]] || exit "${EXIT_FAILURE}"
    [[ "${blocked}" == true ]] && exit "${EXIT_BLOCKED}"

    exit "${EXIT_OK}"
}

trap 'cleanup' EXIT
trap 'exit "${EXIT_HUP}"' HUP
trap 'exit "${EXIT_INT}"' INT
trap 'exit "${EXIT_TERM}"' TERM
main "$@"
