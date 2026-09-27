include mk/config/settings.mk
include mk/*.mk
include .envrc

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
test: ## to test the main installation script
	bats tests/install.bats
