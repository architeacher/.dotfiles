include build/mk/config/settings.mk
include build/mk/*.mk
include .envrc

BACKUP         := bash scripts/backup.sh
# Simply expanded and exported: one date for every step, even across midnight.
BACKUP_DATE    := $(or ${BACKUP_DATE},$(shell date +%Y%m%d))
export BACKUP_DATE
# Order matters. Everything prompts for passphrases, so no parallel runs.
BACKUP_TARGETS ?= gpg-backup age-backup ssh-backup age-yubikey-backup pack
RESTORE_TARGETS      ?= gpg-restore age-restore ssh-restore
TEST_RESTORE_TARGETS ?= gpg-test-restore age-test-restore ssh-test-restore
IMAGE                ?= keys-restore-test
# User input. Paths and key defaults live in scripts/backup.sh.
# Env overrides it reads: BACKUP_DIR GPG_OUT AGE_OUT SSH_OUT AGE_KEY SSH_KEY SERIAL SLOT
KEY            ?=
BAK            ?=
DEST           ?=
FPR            ?=
PUB            ?=
PACK           ?=
NOCACHE        ?=

.NOTPARALLEL:

.PHONY: default
default: help ## to run default target.

.PHONY: .envrc
.envrc: ## prepares a copy of the .envrc file.
	[ ! -f "$@" ] && cp "$@.dist" "$@" || true

.PHONY: install
install: $(DOT_ENV_FILE)  ## to install .dotfiles.
	bash scripts/install.sh -e "${DOT_ENV_FILE}" -p "${PROFILE}" -l "${LOG_LEVEL}"

.PHONY: sel-install
sel-install: ## to select and run a function from an installation file; prompts for args interactively.
	scripts/sel-install.sh

.PHONY: stow
stow: ## to stow files under stow directory.
	stow -v --adopt stow

.PHONY: unstow
unstow: ## to un-stow files under stow directory.
	stow -D stow

.PHONY: test
test: ## to run every test suite under tests/
	bats tests

.PHONY: encrypt
encrypt: ## encrypt private/X/* into private/X.dist/* with sops
	bash scripts/secrets.sh encrypt

.PHONY: decrypt
decrypt: ## decrypt private/X.dist/* into local private/X/* copies
	bash scripts/secrets.sh decrypt

.PHONY: hooks
hooks: ## enable the private repo pre-commit guard against plaintext secrets
	bash scripts/secrets.sh hooks

.PHONY: gpg-fingerprint
gpg-fingerprint: ## get gpg fingerprint by KEY=john.doe@foo.bar
	$(BACKUP) gpg-fingerprint "$(KEY)"

.PHONY: gpg-backup
gpg-backup: ## create gpg backup by KEY=john.doe@foo.bar [env: GPG_OUT]
	$(BACKUP) gpg-backup "$(KEY)"

.PHONY: gpg-test-restore
gpg-test-restore: ## test gpg restore in a temp keyring [BAK=path FPR=noted fingerprint]
	$(BACKUP) gpg-test-restore "$(BAK)" "$(FPR)"

.PHONY: gpg-restore
gpg-restore: ## restore gpg keys [BAK=path FPR=noted fingerprint]
	$(BACKUP) gpg-restore "$(BAK)" "$(FPR)"

.PHONY: age-backup
age-backup: ## back up the plain age identity [env: AGE_KEY AGE_OUT]
	$(BACKUP) age-backup

.PHONY: age-test-restore
age-test-restore: ## test a plain age restore, your key file is untouched. For the yubikey stub use age-yubikey-test-restore [BAK=file.age PUB=noted key]
	$(BACKUP) age-test-restore "$(BAK)" "$(PUB)"

.PHONY: age-restore
age-restore: ## restore an age backup (plain or yubikey) [BAK=file.age DEST=path PUB=noted key]
	$(BACKUP) age-restore "$(BAK)" "$(DEST)" "$(PUB)"

.PHONY: age-yubikey-backup
age-yubikey-backup: ## back up the yubikey identity stub [env: SERIAL SLOT AGE_OUT]
	$(BACKUP) age-yubikey-backup

.PHONY: age-yubikey-test-restore
age-yubikey-test-restore: ## test the yubikey stub backup end to end, needs the device [BAK=file.age PUB=noted recipient]
	$(BACKUP) age-yubikey-test-restore "$(BAK)" "$(PUB)"

.PHONY: ssh-backup
ssh-backup: ## back up the ssh private key [env: SSH_KEY SSH_OUT]
	$(BACKUP) ssh-backup

.PHONY: ssh-test-restore
ssh-test-restore: ## test an ssh restore, your key file is untouched [BAK=file.age PUB=noted key]
	$(BACKUP) ssh-test-restore "$(BAK)" "$(PUB)"

.PHONY: ssh-restore
ssh-restore: ## restore the sops ssh key, another key at DEST is moved aside. Refuses non-recipients of .sops.yaml unless FORCE=1 [BAK=file.age DEST=path PUB=noted key]
	$(BACKUP) ssh-restore "$(BAK)" "$(DEST)" "$(PUB)"

.PHONY: backup
backup: $(BACKUP_TARGETS) ## back up everything into BACKUP_DIR (default ~/backup/DATE). Needs KEY=gpg key id
	$(BACKUP) summary

.PHONY: restore
restore: ## restore everything from BACKUP_DIR or BACKUP_DIR.tar.gz.age. Set BACKUP_DIR=<backup folder>
	$(BACKUP) run $(RESTORE_TARGETS)
	echo "restore done"

.PHONY: test-restore
test-restore: ## test restoring everything, nothing is overwritten. Reads BACKUP_DIR or BACKUP_DIR.tar.gz.age
	$(BACKUP) run $(TEST_RESTORE_TARGETS)
	echo "test-restore done"

.PHONY: docker-build
docker-build: ## 🐳 build the throwaway restore image. NOCACHE=1 refreshes the packages
	docker build $(if $(NOCACHE),--no-cache --pull) -t $(IMAGE) build/docker/

.PHONY: docker-extract
docker-extract: docker-build ## 🐳 run a full restore in a fresh container (builds the image first). Set BACKUP_DIR=<backup folder>. An archive is extracted next to itself so you can inspect it
	set -e; \
	dir="$${BACKUP_DIR:-$$($(BACKUP) latest)}"; \
	parent="$$(dirname "$${dir}")"; \
	cmd="bash /scripts/backup.sh run $(RESTORE_TARGETS) && bash /scripts/backup.sh verify"; \
	extracted=""; \
	{ [ -d "$${dir}" ] && set -- -v "$${dir}:$${dir}:ro"; } \
	  || { [ -f "$${dir}.tar.gz.age" ] \
	       && set -- -v "$${parent}:$${parent}" \
	       && cmd="bash /scripts/backup.sh unpack && $${cmd}" \
	       && extracted=1; } \
	  || { echo "no backup folder or archive: $${dir}" >&2; exit 1; }; \
	[ -z "$${extracted}" ] || { [ "$${parent}" != "$$HOME" ] && [ "$${parent}" != "/" ]; } \
	  || { echo "refusing to mount $${parent} read-write, put the archive in its own folder" >&2; exit 1; }; \
	rc=0; \
	docker run \
	  	   --rm \
	  	   -it \
	  	   --network none \
	  	   "$$@" \
	  	   -v "$(CURDIR)/scripts:/scripts:ro" \
	  	   -v "$(CURDIR)/.sops.yaml:/.sops.yaml:ro" \
	  	   -e FORCE="$${FORCE:-}" \
	  	   -e BACKUP_DIR="$${dir}" \
	  	   -e HOST_UID="$$(id -u)" \
	  	   -e HOST_GID="$$(id -g)" \
	  	   "$(IMAGE)" \
	  	   bash -c "$${cmd}" || rc=$$?; \
	[ -z "$${extracted}" ] || echo "extracted backup left at: $${dir} (files are encrypted, delete when done)"; \
	exit $$rc

.PHONY: verify
verify: ## show and check restored gpg, age and ssh keys. Never prints private keys
	$(BACKUP) verify

.PHONY: pack
pack: ## compress and encrypt the whole BACKUP_DIR into one passphrase-protected file (BACKUP_DIR.tar.gz.age)
	$(BACKUP) pack

.PHONY: unpack
unpack: ## decrypt and extract a packed backup [PACK=file.tar.gz.age DEST=parent dir]
	$(BACKUP) unpack "$(PACK)" "$(DEST)"
