# Guidelines

## Feedback Style
- Interview me using the AskUserQuestion tool.
- Be a caring critic: honest feedback serving my success, not validation
- Challenge when helpful, encourage when true

## Scope
- Apply to new code; adapt to existing project patterns when they conflict

## Autonomy
- Proceed without asking: formatting, tests, obvious fixes, lint errors
- Ask first: deletions, API changes, new dependencies, architecture decisions

## Reasoning
- [MUST] Answer these questions: is it a fact, induction, deduction, abduction, or inference?

## Workflow
- [MUST] Think VERY HARD before acting — no scope creep
- [MUST] Explain understanding and ask confirmation before major changes
- [MUST] Provide 3+ alternatives for non-trivial architectural decisions
- [MUST] Use TDD for application code (not config/scripts)
- [MUST] Show commit messages and ask for confirmation before committing
- [SHOULD] Use sub-agents for deep exploration when trade-offs are complex
- [SHOULD] Write plan under `.claude/plans/feature-{name}.md`

## Verification
- [MUST] Run linters and unit tests — ensure passing
- [SHOULD] Run integration, E2E tests — ensure passing
- [SHOULD] Run benchmarks — ensure no regression

## Documentation
- [MUST] Update `docs/CHANGELOG.md` with changes
- [SHOULD] Update `docs/AGENTS.md`, `docs/architecture.md` (Mermaid — choose diagram that best illustrates change: C4, sequence, ERD, flowchart, state), `docs/features.md`, `docs/README.md`

## Code Style (All Languages)
- [MUST] Prioritize Security first, then Performance
- [MUST] Prefer early returns over nested blocks
- [MUST] Use table-driven tests, name variable `cases`
- [MUST] Follow SOLID, DRY, KISS, YAGNI, TDA principles
- [SHOULD] Avoid: unnecessary comments, long functions/lines, magic numbers, string literals, global variables
- [SHOULD] Use meaningful variable names (e.g., `index` not `i`)

## Architecture (When Applicable)
- [MUST] Clean Hexagonal: adapters (inbound, outbound, repos, services), domain/model, ports, presenters
- [MUST] CQRS: separate commands and queries in usecases, use decorators for cross-cutting concerns
- [MUST] Repository Pattern for data access

## Commit Format
- [MUST] Format: `type(scope): :gitmoji: description.`
- [MUST] Signed commits with conventional commits
- [MUST] Commit message relevant to staged files ONLY
- [MUST] No Claude attribution unless requested
- [SHOULD] Check if docs need updating based on staged changes
- [SHOULD] Add body ONLY for complex changes

## Golang
- [MUST] Follow Effective Go practices
- [MUST] Return errors, don't panic (except truly unrecoverable)
- [MUST] File order: constants → types → variables → exported methods
- [MUST] Architecture paths: `internal/adapters/{inbound,outbound,repos,services}/`, `internal/domain/model/`, `internal/ports/`, `internal/usecases/{commands,queries}/`, `pkg/shared/`
- [MUST] Wrap errors with context: `fmt.Errorf("operation failed: %w", err)`
- [MUST] Never log sensitive data (tokens, passwords, PII)
- [MUST] Tests: parallel, testify/require, counterfeiter mocks, test context, integration testcontainers
- [SHOULD] Keep `main.go` minimal: `runtime.New().Run()`
- [SHOULD] Wrap declarations: `const (...)`, `type (...)`, `var (...)`
- [SHOULD] Prefer `fmt.Sprintf` over string concatenation
- [SHOULD] Use sentinel errors for expected conditions
- [SHOULD] Database: PostgreSQL, pgx, squirrel, scany (sqlx for MySQL), migrate/migrate Docker for migrations

## Shell Script
- [MUST] Shebang: `#!/usr/bin/env bash`
- [MUST] Use `set -euo pipefail`
- [MUST] Write functions, not plain steps
- [MUST] Quote variables: `"${var}"` not `$var`
- [SHOULD] Support Bash 3.2 (Linux + macOS)

## Makefiles
- [MUST] Precede targets with `.PHONY`
- [MUST] Use `${var}` not `$(var)`
- [MUST] Use `.SILENT` instead of `@`
- [SHOULD] Add help: `target: ## Description`

## Docker
- [MUST] Use `compose.yaml` (not docker-compose.yaml)
- [SHOULD] Use `compose-tools.yaml` for monitoring

## YAML
- [MUST] Extension: `.yaml` (not `.yml`)
- [SHOULD] Use double quotes, anchors for shared blocks

## General
- [SHOULD] Use `rg` instead of `grep`/`find`
- [SHOULD] Target OS: macOS unless stated otherwise
