# Changelog

All notable changes to this repository. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

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
  to two questions (right key? safe to install?), uses the default file names
  (`id_ed25519_sops.age`, `.pub`) and has a terminology table.

### Security

- Plaintext secrets were staged in the `private` submodule. They were unstaged, and the
  `.gitignore` allowlist plus the pre-commit guard now prevent it.
- Public docs no longer describe what `private/` holds (file names, paths, key layout, backup
  locations). `AGENTS.md` makes this a rule.
