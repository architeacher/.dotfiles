.DEFAULT: default
.DEFAULT_GOAL := default
# Delete targets on nonzero exit status.
.DELETE_ON_ERROR: ;
.EXPORT_ALL_VARIABLES: ;
.NOTPARALLEL: ;
.ONESHELL: ;
.SHELLFLAGS = -c

# Unless ECHO_RECIPES is defined we do not echo the line of the recipes before they are executed.
ifneq (true, ${ECHO_RECIPES})
.SILENT: ;
endif

SHELL := /bin/bash

# An empty, phony .FORCE target, that will cause external targets to always be built, so that the
# Makefile there will handle dependencies.
# https://gist.github.com/mschubert/a0e4f3aeaf3558431890
.PHONY: .FORCE
.FORCE: ;

include mk/config/settings.mk
include mk/*.mk

.PHONY: default
default: help ## to run default target.

DOT_ENV := .env

$(DOT_ENV): ## prepares a copy of the .env file.
	[ ! -f "$@" ] && cp "$@.dist" "$@" || true

.PHONY: install
install: $(DOT_ENV)  ## to install .dotfiles.
	bash scripts/install.sh -e ".env" -l 7

.PHONY: install
gpg-armor: ## gets the GPG key ID, in ASCII armor format for a given email.
	key_id="$$(gpg --list-keys --keyid-format LONG "${email}" 2>/dev/null | rg '^pub' | awk '{print $$2}' | cut -d'/' -f2)"; \
	gpg --armor --export "$${key_id}" | tee >(pbcopy) | { cat; }

.PHONY: install
sel-install: ## to select and run a function from the installation file.
	unset POSIXLY_CORRECT; \
	script_file="scripts/install.sh"; \
	script_functions="$$(rg -oP "^\s*(?:function\s+)?\K\w+(?=\s*\(\s*\)\s*\{)" $${script_file} | cat)"; \
	[ -n "$${script_functions}" ] && \
	selected_function="$$(echo "$${script_functions}" | fzf --prompt "Select a function: ")"; \
	[ -n "$${selected_function}" ] && { \
		temp_file="$$(mktemp -p scripts)"; \
		sed '$$d' "$${script_file}" > "$${temp_file}"; \
		cat "$${temp_file}"; \
		source "$${temp_file}" && \
		include_env_vars; \
		"$${selected_function}"; \
		rm -rf "$${temp_file}"; \
	} \
	|| echo "No functions found or no function selected"

.PHONY: stow
stow: ## to stow files under stow directory.
	stow --adopt stow

.PHONY: unstow
unstow: ## to un-stow files under stow directory.
	stow -D stow
