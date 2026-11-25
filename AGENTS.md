# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

macOS dotfiles management system using GNU Stow for symlink-based configuration deployment. Supports multiple profiles (private/work) and manages 28+ tool configurations. Secrets live sops-encrypted in the `private/` submodule; the keys sops needs have their own backup tooling.

## Common Commands

```bash
make                    # Show all available targets
make .envrc             # Create environment file from template
make install            # Run full installation
make stow               # Symlink configs to home directory
make unstow             # Remove symlinks
make sel-install        # Interactive function selector (fzf)
make test               # Run every bats suite under tests/
make stats              # Code statistics with tokei
```

### Secrets (`private/`)

```bash
make decrypt            # private/X.dist/* -> private/X/* (mode 600, local edits kept)
make encrypt            # private/X/* -> private/X.dist/* (unchanged files skipped)
make hooks              # Enable the plaintext pre-commit guard in private/ (once per clone)
```

Both stop on a copy that differs from its encrypted file and is not newer (a pull, checkout or reset rewrote that file). `touch` the copy and `make encrypt` to keep it, `FORCE=1 make decrypt` to replace it.

### Key Backups

```bash
make backup KEY=<gpg id>     # gpg, age, YubiKey stub, ssh key + pack into one encrypted archive
make test-restore            # Check the latest backup in temp dirs, nothing is touched
make restore                 # Restore gpg, age and ssh keys from the latest backup
make docker-extract          # Full restore + verify in a clean bash:3.2 container
make verify                  # Check the installed keys, never prints private keys
make gpg-fingerprint KEY=<id>
```

Per key type: `gpg-`, `age-`, `age-yubikey-`, `ssh-` + `backup` / `test-restore` / `restore`. Pass `BAK=`, `PUB=`, `FPR=`, `DEST=` for one-off paths and independent checks; `BACKUP_DIR=` picks a backup other than the latest. See `bash scripts/backup.sh help` for every setting.

## Architecture

See [docs/architecture.md](docs/architecture.md) for the secrets and backup flows (Mermaid).

### Directory Structure

- `stow/` - Symlink farm (deployed to ~/ via GNU Stow)
  - `.config/` - XDG config directory (28+ tools: git, zsh, nvim, tmux, etc.)
  - `.config/claude/` - Claude Code user-wide config
  - `.local/` - User data (nvim, mkcert, delta)
  - `.ssh/` - SSH configuration
- `scripts/` - Installation and setup scripts
  - `install.sh` - Main installation orchestrator
  - `common.sh` - Shared helpers (`is_command`, `notify`, `speak`, `abort` via logger, traps)
  - `logger.sh` - Syslog-style logging framework: theme table, palettes (`LOG_PALETTE`), colors (`LOG_COLOR=auto|always|never`, `NO_COLOR`), syntax highlighting
  - `progress.sh` - Terminal UI for `install.sh`: banner with the block logo (`assets/logo-blocks.txt`) whose letters fall into place like blocks, yes or no question (`progress_confirm`), progress line pinned to the bottom row with the percentage of the steps done (`progress_steps_of <function>`, `progress_run <label> <command>`); animated only when stderr is a terminal
  - `macos.sh` - macOS system defaults
  - `secrets.sh` - sops encrypt/decrypt for `private/`, enables the guard
  - `backup.sh` - Key backup entry point; modules in `backup/` (`common`, `gpg`, `age`, `yubikey`, `ssh`, `verify`, `pack`)
- `build/mk/` - Makefile system (`Makefile` at the root is a symlink to `build/mk/Makefile`)
  - `Makefile` - Core targets
  - `utils.mk` - Helper targets (help, list, stats, todo)
  - `config/settings.mk` - Colors and variables
- `build/docker/` - Throwaway `bash:3.2` image for `docker-extract`
- `tests/` - bats suites; test doubles in `tests/mocks/` (`mocks/backup/` fakes age, the YubiKey plugin and gpg; `mocks/{pi,opencode,codex,claude,tuios}` fake the delegation executors and tuios); `tests/fixtures/rest-api-openapi/` is the scaffold the REST API skill's endpoint template is laid over (its lint and bundle tests need a `redocly` binary on `PATH` or in `REDOCLY_BIN`, and are skipped without one)
- `harness/` - `agents/`, `skills/` and `recipes/` for coding harnesses; `stow/.config/claude/{agents,recipes,skills}` link into it
  - `skills/delegation/` - orchestrator/executor loop: `SKILL.md`, `executor-prompt.md`, `scripts/delegate.sh` (self-contained: it runs from the stowed symlink, outside this repo, so it does not source `scripts/common.sh`)
  - `skills/rest-api-openapi/` - spec-first REST API design for any project that keeps its contract under `docs/contracts/openapi`: `SKILL.md`, `references/` (layout, endpoint template, status codes, headers, errors, media types, pagination, toolchain), `assets/` (generic redocly ruleset, project config and profile templates a project installs)
- `docs/` - `CHANGELOG.md`, `architecture.md`
- `private/`, `wallpapers/` - Git submodules

### Configuration Flow

1. `.envrc` defines environment (GIT_EMAIL, GIT_USER, GITHUB_USERNAME, PASS_PHRASE, PROFILE)
2. `make install` runs `scripts/install.sh`, which asks for confirmation on a terminal
3. Stow creates symlinks from `stow/` to `~/`
4. `make decrypt` writes the decrypted secrets the stow symlinks and ssh `Include` point at

### Key Configuration Files

- `stow/.config/git/config` - Git settings with signing, aliases, colors
- `stow/.config/homebrew/Brewfile` - Package definitions
- `stow/.config/nix-darwin/flake.nix` - Nix system configuration
- `stow/.config/zsh/.zshrc` - Shell configuration
- `stow/.config/zsh/scripts/exports.zsh` - Environment, including where sops finds its keys
- `.sops.yaml` - sops creation rules and key groups

### Secrets Rules

- Never commit plaintext under `private/`: only `X.dist/**` (encrypted), `.gitignore`, `.githooks/`.
- New secret: create `private/X/<file>`, make sure `.sops.yaml` matches `private/X.dist/<file>`, run `make encrypt`.
- Never print or log private keys, passphrases or decrypted secrets.
- This repository is public: never describe what `private/` holds (file names, paths, key
  layout, backup locations) in docs, commit messages, PRs or issues. Name the mechanism, not the contents.

### Shell Scripts

- Use `#!/usr/bin/env bash` shebang
- Write functions, not plain steps
- Quote variables: `"${var}"` not `$var`
- Source `scripts/common.sh` and log with `log_info` / `log_notice` / `log_warning` / `abort`, like `install.sh`
- Wrap a command line in `${LOG_CODE}` inside a log message, `log_notice "DRY RUN: ${LOG_CODE}$*${LOG_CODE}"`: the logger colors its command words and flags and never prints the marker
- Keep Bash 3.2 compatible (macOS `/bin/bash`, the restore image): no `mapfile`, assoc arrays, `${x,,}`, or `@(a|b)` in `[[ ]]`
- Do not parse `ls`; use globs, `stat`, or `find` (where `fd` may be missing, e.g. the restore image)
- Every ShellCheck `disable=` needs a one-line reason above it
- Cover behavior with bats tests in `tests/`; `make test` must pass

### Makefiles

- Precede targets with `.PHONY`
- Add `## comment` after target definition for help display
- Use curly braces for variables: `${var}` not `$(var)`
- Use `.SILENT` directive instead of `@` prefix
