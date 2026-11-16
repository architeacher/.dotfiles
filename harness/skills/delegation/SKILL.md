---
name: delegate
description: 'Hands a bounded, fully specified task to a cheaper executor (pi with GLM by default; opencode, codex, or claude with Haiku/Sonnet) and validates the result in this session: diff, tests, acceptance criteria. Use when the user says "delegate", "hand this to GLM", "let the executor do it", or when a task is mechanical enough that this session should only specify and verify.'
license: MIT
metadata:
  tags: "Orchestration, Delegation, Productivity"
  category: "productivity"
---

# delegate

## Roles

- **Orchestrator**: this session. Thinks, writes the spec, validates the result, decides. Never trusts
  the executor's summary.
- **Executor**: a headless coding agent on a cheaper model. Edits files and runs commands without
  approval prompts, then reports. Picked by `--executor`, or automatically: `pi` when it is installed
  and has credentials, otherwise `opencode`.

| Executor | Default model | Model ids | Needs |
|---|---|---|---|
| `pi` (default) | `zai/glm-5.3` | pi `provider/model`, e.g. `amazon-bedrock/global.zai.glm-5.3` | `pi` on PATH, `ZAI_API_KEY` for `zai/*` |
| `opencode` (fallback) | `zai-coding-plan/glm-5.3` | opencode `provider/model` | `opencode` on PATH, provider auth in opencode |
| `codex` | codex's own | codex model name | `codex` logged in, `jq` |
| `claude` | `sonnet` | `haiku`, `sonnet`, `opus`, full ids | same auth as this session |

Haiku and Sonnet executors: `--executor claude --model haiku` or `--model sonnet`.

## When to use

Delegate when the task is bounded and can be specified completely: implement a written spec, mechanical
edits across files, write tests for existing behavior, fix a bug with a reproduction, port a pattern.

Do not delegate: open design questions, anything touching secrets or credentials, git operations, tasks
whose acceptance criteria you cannot write down, and tasks small enough that the spec costs more than
the edit. Do those here.

Match the executor to the risk. Review limits the damage of a weak first attempt; it does not turn it
into a good one. Where correctness rides on security, concurrency, a migration, or domain knowledge the
spec cannot carry, do the work here or hand it to a stronger executor (`--executor codex`, or `claude`
with `--model opus`). The cheap default is for work that tests and linters can judge.

## Where executors can run

The script runs wherever Bash runs it. Inside the Claude Code sandbox only `pi` can work: its state goes
to `DELEGATE_STATE_DIR`, and it reaches its provider only when `api.z.ai` is allowed, either per call with
`allowed_domains: ["api.z.ai"]` on the Bash call that runs the script, or for good in
`sandbox.network.allowedDomains`. `ZAI_API_KEY` must be in the environment. When the host is denied, pi
retries and exits 0 anyway; the report then says `failed (stopReason error)`. The others hit sandbox
limits:

- `opencode` starts a private server on a localhost port; needs `sandbox.network.allowLocalBinding: true`.
- `codex` applies its own Seatbelt profile and writes `~/.codex`; neither works nested in the sandbox.
- `claude` reads the AWS auth files, which the sandbox denies.

For those three, use `--via tuios`, run the command from your own terminal, or exclude the script from
the sandbox with `sandbox.excludedCommands`. Excluding it removes the outer boundary for every executor,
including `pi`, which never asks before running a command.

### tuios transport

`--via tuios` runs the executor interactively in a tuios pane instead of a headless subprocess. The pane
runs in your terminal session, outside the sandbox, so every executor works there and you see it work.
The auto chain lands here too when neither `pi` nor `opencode` is installed and a tuios daemon runs.

- Start a tuios session first. Inside a tuios pane the executor opens in your session; outside, in a
  session named `delegate` (`DELEGATE_TUIOS_SESSION`), created on demand. `tuios attach delegate` shows it.
- `tuios start-agent` opens the pane with `--grants none`, so the executor cannot drive tuios itself;
  `tuios ask-agent` types the task and returns the reply once the agent is back at rest. The agent is
  named `dlg-<id>`; the report's `Session` line is the feedback-round command and the `Pane` line says
  where to look. The pane stays open; `tuios close-window dlg-<id> -s <session>` when done.
- An approval or question dialog puts the agent in `needs_input`: the script exits 3, and the report
  shows the prompt under `## Prompt` (from `tuios peek-prompt`). Answer in the pane, then send the next
  round with `--session dlg-<id>`. Only you answer another agent's prompt.
- The reply is capped at `DELEGATE_TUIOS_LINES` lines (default 400) and fenced by tuios as untrusted
  content. For a long spec, write it to a file and make the task "Read <path> and do it".
- The wait limit is `DELEGATE_TUIOS_TIMEOUT_MS` (default 30 minutes). A timeout fails the round; the
  agent keeps running in its pane.

## The loop

### 1. Spec

Write the task as a spec, not a chat message:

```markdown
# Task: <title>
## Goal
<observable outcome>
## Context
<why; project conventions worth repeating; related files to read first>
## Files
<paths the executor may change; everything else is off limits>
## Constraints
<no new dependencies, Bash 3.2, keep public API, ...>
## Acceptance
<commands that must pass, behavior to verify>
```

A `--read-only` run changes no files, so the deliverable is the executor's final message. Replace
`## Files` and `## Acceptance` with a `## Deliverable` that says what the answer must contain, and ask
for observed facts with `path:line`, inferences, and open questions as separate lists. For a second
opinion on a decision of yours:

```markdown
# Task: second opinion on <decision>
## Agreed
<points both positions accept>
## Contested
1. <point>. Position A: <...>. Position B: <...>.
## Deliverable
For each contested point: defend or concede, and name the evidence that decided it.
```

The decision stays here. The executor's answer is one more input, not a verdict.

### 2. Dispatch

```bash
bash "${CLAUDE_CONFIG_DIR:-$HOME/.config/claude}/skills/delegation/scripts/delegate.sh" - < spec.md
```

Run it as a background command (`run_in_background` on the Bash call) unless the task is done in a
minute or two: a foreground call ends at the Bash timeout, which is shorter than the watchdog's default
limit, and a script that is killed prints no report. Dispatch in parallel only when the file sets are
disjoint. For a risky or long task, enter a worktree first so the executor's changes stay isolated.
Dispatch from a clean tree, so `## Changes` reads as what the executor did.

| Option | Use |
|---|---|
| `--executor <pi\|opencode\|codex\|claude>` | pick the executor; default `auto` (pi, then opencode, then tuios) |
| `--via tuios` | run the executor interactively in a tuios pane; see above |
| `--model <id>` | executor model; or `DELEGATE_PI_MODEL`, `DELEGATE_OPENCODE_MODEL`, `DELEGATE_CODEX_MODEL`, `DELEGATE_CLAUDE_MODEL` |
| `--read-only` | analysis, review, investigation: read tools only |
| `--session <id>` | feedback round in the same executor session (keeps its context) |
| `--thinking <level>` | pi only; `off` to `max`, default `medium` |
| `--timeout <dur>` | direct transport: stop the executor after `30m` by default; implementation specs often need `--timeout 2h`. Or `DELEGATE_TIMEOUT` |

### 3. Validate

The report has `## Result` (the executor's final message, ending with its `## Report`) and `## Changes`
(`git status --short` and `git diff --stat`: the whole tree, not an attribution). Treat both as claims.
The header lines are measurements:

- `Status`: `ok`; `failed (exit N)`; `failed (stopReason error)` when pi's last message is an error even
  though pi exited 0; `failed (no assistant message)` when pi's stream holds no answer at all;
  `failed (timeout after 30m)` when the watchdog stopped the executor, exit 4; `blocked` for a tuios
  prompt, exit 3.
- `Run files` (failed runs only): the directory with the executor's full stdout, which for pi is its
  event stream, and its stderr. Read it when the tail under `## Error` is not enough, and delete it
  when done. A successful run leaves nothing behind.
- `Actual model` and `Usage` (pi): what served the run and what it cost. The requested model is a pattern.
- `Read-only check` (`--read-only`): `unchanged`, `CHANGED` or `unknown`. `CHANGED` fails the round: the
  tool allowlist is a promise, the tree is the proof. The check compares `git status`, both diffs and
  the content of untracked files. It does not see ignored files, a further change inside a submodule
  that was already dirty, changes inside an untracked nested repository, or anything outside the
  repository.

1. `git diff`: read every hunk. A change outside the spec's file list fails the round.
2. Test edits first. An edit to an existing test the spec did not ask for, a newly skipped or
   commented-out test, or a loosened assertion (exact match to contains, a wider error type, a bigger
   tolerance) is a contract change, not part of the fix. Treat it as failing.
3. Run the acceptance commands yourself: tests, linters, build. The executor's `Verification` line is
   not evidence. Passing is necessary, not sufficient.
4. Sweep the diff for what gates miss: hardcoded fixture data on a real path; catch-all error handling
   that returns a default; imports, methods or signatures absent from the installed version; unused
   helpers, unreachable branches, scaffolding comments; a second idiom next to the repository's own;
   tests that assert internals; abstractions with no caller.
5. Read `Decisions`, `Not done` and `Open questions`. A choice the spec did not ask for is yours once
   you accept it: keep it on purpose or send it back. Design questions are yours to answer, not the
   executor's.
6. For risky changes, run the `code-review` skill on the diff.

The tree is evidence. Between dispatch and your commit, never `git checkout`, `reset`, `clean` or switch
branches in the workspace before reading `git status`, `git diff`, `git diff --cached` and the untracked
files: the uncommitted tree is the only copy of the executor's work. Discarding is a verdict after that
reading, never a reflex.

No report means the script was killed before it could print one: a Bash timeout, a stopped task, a
closed terminal. A direct run stops its executor on SIGTERM, SIGHUP or SIGINT; after a `kill -9` the
executor runs on until the watchdog's limit, and a tuios agent keeps running in its pane. Wait until
`git status` stops changing, then read the tree the same way. The session id is on the script's first
log line (`==> delegating to ... (session <id>)`): continue with `--session <id>` and what is left, or
dispatch again once the partial edits are kept or reverted.

### 4. Decide

- **Accept**: continue with the project's commit rules.
- **Feedback round**: the report's `Session` line gives the exact command. Send concrete findings:
  `path:line`, the failing command and its output, the acceptance item missed. One round at a time.
  A codex run without a thread id in its output has no feedback round; dispatch again.
- **Wrong premise**: a fact in the spec turned out false (owner, branch, a constraint). Premises freeze
  at dispatch and there is no steering channel: stop the run, read the tree, keep or revert the partial
  edits, dispatch a corrected spec. Do not discount the output afterwards.
- **Take over**: after three rounds without a pass, or when the executor reports a blocker you can only
  resolve by redesign, finish the task yourself and tell the user why.

### 5. Report to the user

What was delegated and to which executor, what you verified and how, rounds used, open questions, and
the session id. Surface, do not absorb: the executor's design decisions, defensible but unasked turns,
and the nitpicks you let through all go in this report. Ask before expanding the mandate when correct
completion needs more than the spec allowed.

## Queues

A sweep across layers or files is a queue of specs, not one big spec.

- One task at a time, in dependency order; land each (validate, commit) before dispatching the next. A
  clean tree before each dispatch keeps `## Changes` honest. Parallel runs only for independent tasks in
  separate worktrees.
- Fresh session per task. Executors do not remember earlier tasks: a helper name, fixture path or
  interface decided in task 2 goes into task 5's spec. Reuse a session only for a feedback round on the
  same task.
- More than three tasks: keep a progress file next to the work with the status per task (queued, at the
  executor, landed with its commit), what you verified, and what needs the user's eyes.
- Close with a coherence pass: full tests and build once more, a repo-wide search for the thing the queue
  changed, migrations replayed from clean when applicable. Read the whole range as one diff
  (`git diff <commit before the queue>..HEAD`) for what per-task review cannot see: one problem solved
  two ways, a helper written twice, code a later task made dead, the old and the new pattern side by side.
- Stop and ask when a task cannot be completed within its spec, when review calls the plan into
  question, when a gate breaks an already landed task, or when two tasks in a row need rework for the
  same reason: then the specs' constraints are at fault, not the executor.

## Safety

Executors run with the tools and network their environment allows, without per-command approval:
`pi` never asks, `opencode` runs with `--auto`, `codex` with `-s workspace-write`, `claude` with
`--permission-mode acceptEdits`. Never put secrets in a spec. Prefer `--read-only` when the task does not
need edits, and read its `Read-only check` line. `pi` state lives under `DELEGATE_STATE_DIR` (default
`${TMPDIR}/delegate`), never in `~/.pi`; pi runs with `--no-approve`, so project-local `.pi` resources
stay untrusted. The script makes that directory private to you (mode 700) and refuses one that is a
symbolic link or belongs to another user. `claude` runs with `CLAUDE_QUIET=true`, so your notification
hooks stay silent. The task reaches `pi`, `codex` and `claude` on stdin and stays out of the process
list; `opencode` takes it as an argument. A codex feedback round keeps its sandbox, read-only included.

A direct run cannot outlive `DELEGATE_TIMEOUT` (default `30m`): the watchdog sends SIGTERM to the
executor's process group, SIGKILL to what is left of it after `DELEGATE_KILL_GRACE` seconds (default
10), and the script exits 4 with the reason under `## Error`. A SIGTERM, SIGHUP or SIGINT to the script
stops the group the same way, and the script exits with 128 plus the signal number. After a `kill -9`
of the script the watchdog still enforces the limit. One gap remains: `pi` runs each tool command in a
process group of its own and stops it when pi gets SIGTERM, so a tool command can outlive the run only
when pi itself has to be killed with SIGKILL. The tuios transport has its own limit,
`DELEGATE_TUIOS_TIMEOUT_MS`, and leaves the agent running in its pane.
