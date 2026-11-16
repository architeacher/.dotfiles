# Changelog

All notable changes to this repository. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **REST API design skill** (`harness/skills/rest-api-openapi/`): spec-first design of REST endpoints with a
  modular OpenAPI 3.0.3 layout under `docs/contracts/openapi`. The skill is generic: a project supplies its own
  values (API name, version, base path, problem-type base URL, realm, ADR pointers, additions to the baseline
  tables) in `docs/contracts/openapi/profile.yaml`, created from `assets/profile.yaml`, and an API that does not
  follow the layout keeps its own conventions. `references/` holds the directory layout and rule map, the
  endpoint template, the status-code matrix, header sets, the RFC 9457 error catalogue, media-type decisions,
  pagination and the toolchain snippets. `assets/rest-api-ruleset.yaml` is the redocly ruleset a project
  installs verbatim; `assets/redocly.yaml` is the project config that extends it with two apis, so one
  `redocly bundle` call writes the public bundle (everything marked `x-internal` removed) and the full internal
  one. The ruleset rejects `Authorization`, `Accept` and `Content-Type` header parameters (OpenAPI 3.0.3
  ignores them), a version segment in a path, an operation without its own `security`, an undeclared tag and a
  `POST`, `PUT` or `PATCH` that misses a status of the matrix; a duplicate example key fails the bundle.
  Contract rules worth knowing: `503` with `Retry-After` on every operation and `500` for defects only; `403`
  opt-in for an operation restricted by scope, role or ownership; only a successful outcome is stored under an
  idempotency key; cursor mode omits the totals; the URL selects the version, `API-Version` only asserts it, and
  a breaking change starts a new `v<N+1>` tree. `tests/rest_api_openapi.bats` (15 tests) builds a contract from
  the endpoint template's own YAML blocks over the scaffold in `tests/fixtures/rest-api-openapi/`: ten
  structural tests need only `rg`, among them one that holds the template to the status matrix; five run the
  ruleset with `@redocly/cli` (checked with 2.78.0: lint clean, both bundles written, seven seeded violations
  fail) and are skipped when no `redocly` binary is on `PATH` or in `REDOCLY_BIN`.

- **Delegation harness** (`harness/skills/delegation/`): the `delegate` skill keeps the Claude Code session as
  the orchestrator (spec, validation, decision) while a headless executor runs the task on a cheaper model.
  `scripts/delegate.sh` drives `pi` (default, `zai/glm-5.3`), `opencode` (automatic fallback,
  `zai-coding-plan/glm-5.3`), `codex`, or `claude` (`haiku`, `sonnet`) with one interface: `--executor`,
  `--model`, `--read-only`, `--session <id>` for a feedback round in the same executor session,
  `--timeout <dur>`. Pi runs in `--mode json` with a hermetic state dir under `${TMPDIR}/delegate`; the
  executor contract goes in through the system prompt or ahead of the task; the report (`Executor`, `Model`,
  `Actual model`, `Usage`, `Session`, `Read-only check`, `Status`, `Result`, `Changes`) is what the
  orchestrator validates with its own diff, tests and linters. The executor's own `## Report` lists
  `Decisions` (choices the spec did not specify) next to `Not done` and `Open questions`; the skill says
  when not to delegate, how to spec a read-only run or a second opinion, and what to do after an
  interrupted run. The status comes from pi's event stream, not its exit code: pi exits 0 after a provider
  error, and the report says `failed (stopReason error)`; a stream without an assistant message is
  `failed (no assistant message)`, and lines that are not events are skipped. A watchdog (`DELEGATE_TIMEOUT`,
  default `30m`) stops a direct executor's process group, SIGTERM then SIGKILL after `DELEGATE_KILL_GRACE`
  seconds (default 10), and exits 4; a signal to the script stops the group the same way (exit 129, 130 or
  143), and the watchdog still fires after a `kill -9` of the script. A failed run keeps its run directory
  with the executor's full stdout and stderr, and the report names it. The task reaches `pi`, `codex` and
  `claude` on stdin. The state directory is made private (mode 700) and refused when it is a symbolic link or
  another user's; a codex feedback round keeps its sandbox through `-c sandbox_mode`. `--read-only`
  fingerprints the tree before and after the run (`git status`, both diffs without the user's diff drivers,
  the untracked files' content) and reports `unchanged`, `CHANGED` or `unknown`. `--via tuios` runs any
  executor interactively in a tuios pane (`tuios start-agent` with `--grants none`, `tuios ask-agent` for the
  reply), exits 3 with the blocking prompt in the report when the agent needs input, and is the auto chain's
  last fallback when neither pi nor opencode is installed. `tests/delegate.bats` (46 tests) with stubbed `pi`,
  `opencode`, `codex`, `claude` and `tuios` in `tests/mocks/`. Inside the Claude Code sandbox pi needs
  `api.z.ai` allowed, per Bash call through `allowed_domains` or in `sandbox.network.allowedDomains`;
  `stow/.config/claude/settings.json` does not add it.

- **Code review harness** (`harness/`): the `code-review` skill orchestrates five parallel, read-only `code-reviewer`
  agents (one SHA, Focus per review step), verifies each blocking finding with a second
  agent, and reports the Spec and Standards axes separately. Every check, including a Fowler smell
  baseline, lives in `harness/recipes/code-review.standards.md`, which the agent loads from
  `${CLAUDE_CONFIG_DIR}/recipes/`; a missing file turns the review into COMMENT. Repository standards
  (`CODING_STANDARDS.md`, `CONTRIBUTING.md`) override it.
  `stow/.config/claude/{agents,recipes,skills}` are relative symlinks into `harness/`.

- **Key backups** (`make backup`, `make test-restore`, `make restore`, `make docker-extract`, `make verify`):
  passphrase-protected backups of the gpg key, the plain age identity, the YubiKey identity stub
  and the sops ssh key, plus `pack`/`unpack` into a single encrypted archive.

- `age-yubikey-test-restore`: decrypts the YubiKey stub, checks it against the saved recipient
  and round-trips a probe through the device.

- `BACKUP_ROOT` and `BACKUP_DATE` settings, and a `latest` command. Read commands use the newest
  `BACKUP_ROOT/YYYYMMDD` (folder or archive) unless `BACKUP_DIR` is set, and say which one.

- sops recipient check: `ssh-restore` refuses a key that is not a recipient in `.sops.yaml`
  (stale backup) before touching `~/.ssh`. `FORCE=1` overrides.

- `scripts/secrets.sh` with `make encrypt`, `make decrypt`, `make hooks`: secrets in `private/`
  are tracked only sops-encrypted under `X.dist/` dirs and decrypted to `X/` (git-ignored).
  Unchanged files are not re-encrypted, newer local edits are never overwritten.

- `private/.githooks/pre-commit`: refuses commits of anything outside `*.dist/` or of plaintext.
  Enabled once per clone with `make hooks`.

- `tests/backup.bats` (25 tests) with test doubles in `tests/mocks/backup/`. `make test` now runs
  every suite under `tests/`, including `sel-install.bats`, which it skipped before.

- `docs/architecture.md` with the secrets and backup flows. The ssh-restore chart is reduced
  to two questions (right key? safe to install?), uses the default file names (`id_ed25519_sops.age`, `.pub`) and has a
  terminology table.
