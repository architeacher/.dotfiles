include mk/config/settings.mk
include mk/*.mk

define get_gpg_keys
    [ -z "$(email)" ] && { printf "${ERR_CLR}Email is missing, please set ${INFO_CLR}email${NO_CLR} ${ERR_CLR}variable.${NO_CLR}" >&2; exit 1; } || true; \
	SIGNING_KEY_ID="$$(gpg --list-keys --keyid-format LONG "$(email)" 2>/dev/null | rg '^pub' | awk '{print $$2}' | cut -d'/' -f2)"; \
	[ -z "$${SIGNING_KEY_ID}" ] && { echo "${ERR_CLR}Error: No GPG key found for ${email}${NO_CLR}" >&2; exit 1; }; \
	echo "$${SIGNING_KEY_ID}"
endef

define get_gpg_secret_keys
    [ -z "$(email)" ] && { printf "${ERR_CLR} Email is missing, please set ${INFO_CLR}email${NO_CLR} ${ERR_CLR}variable.${NO_CLR}" >&2; exit 1; } || true; \
	SECRET_SIGNING_KEY_ID="$$(gpg --list-secret-keys --keyid-format LONG "${email}" 2>/dev/null | rg -A 1 '^sec' | rg '[0-9A-F]{40}' | xargs)"; \
	[ -z "$${SECRET_SIGNING_KEY_ID}" ] && { echo "${ERR_CLR}Error: No secret GPG key found for ${email}${NO_CLR}" >&2; exit 1; }; \
	echo "$${SECRET_SIGNING_KEY_ID}"
endef

.PHONY: default
default: help ## to run default target.

.PHONY: .env
.env: ## prepares a copy of the .env file.
	[ ! -f "$@" ] && cp "$@.dist" "$@" || true

.PHONY: install
install: $(DOT_ENV_FILE)  ## to install .dotfiles.
	bash scripts/install.sh -e "${DOT_ENV_FILE}" -p "${PROFILE}" -l "${LOG_LEVEL}"

.PHONY: get-gpg-keys
get-gpg-keys: ## gets the GPG keys IDs for a given email.
	$(call get_gpg_keys)

.PHONY: get-gpg-secret-keys
get-gpg-secret-keys: ## gets the GPG secret keys IDs for a given email.
	$(call get_gpg_secret_keys)

.PHONY: get-gpg-ssh-key
get-gpg-ssh-key: ## exports the GPG public key in ssh key format.
	signing_key_id="${signing_key_id}"; \
    [ -n "$${signing_key_id}" ] || { signing_key_id="$(shell make get-gpg-keys email="${email}")"; }; \
    [ -n "$${signing_key_id}" ] || { printf "Error: Either 'signing_key_id' or 'email' must be provided." >&2; exit 1; }; \
	echo "${USER} $$(gpg --export-ssh-key "$${signing_key_id}" 2>/dev/null)"

.PHONY: delete-gpg-keys
delete-gpg-keys: ## deletes the GPG keys IDs for a given email.
	echo "$(shell make get-gpg-secret-keys email="${email}")" | xargs gpg --batch --delete-secret-keys --yes 2>&1; \
	$(eval signing_key_id := "$(shell make get-gpg-keys email="${email}")")
	echo "${signing_key_id}" | xargs gpg --batch --delete-keys --yes 2>&1; \
	ZDOTDIR="$${XDG_CONFIG_HOME}/zsh"; \
	rg -v "$(shell make get-gpg-ssh-key signing_key_id="${signing_key_id}")" ~/.ssh/allowed_singers | sponge ~/.ssh/allowed_singers; \
	rg -v "${signing_key_id}" "$${ZDOTDIR}/local/keychain.zsh" | sponge "$${ZDOTDIR}/local/keychain.zsh";

.PHONY: gpg-armor
gpg-armor: ## gets the GPG key ID, in ASCII armor format for a given email.
	gpg --armor --export "$(shell make get-gpg-keys email="${email}")" 2>/dev/null | tee >(pbcopy) | { cat; };

.PHONY: sel-install
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
