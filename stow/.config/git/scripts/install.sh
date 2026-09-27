#!/usr/bin/env bash

set -Eeuo pipefail

create_gpg_agent_data_dir() {
    local gpg_agent_data_dir="${XDG_DATA_HOME}/gnupg"

    [[ ! -d "${gpg_agent_data_dir}" ]] && {
        mkdir -p "${gpg_agent_data_dir}"
        chmod 700 "${gpg_agent_data_dir}"
    } || return 0
}

update_pinentry_path() {
    local gpg_agent_config_file="${XDG_DATA_HOME}/gnupg/gpg-agent.conf" \
          pinentry_path

    pinentry_path="$(which pinentry-mac)"

    log_debug "Updating pinentry path in config file (${pinentry_path}): ${gpg_agent_config_file}"

    [[ ! -f "${gpg_agent_config_file}" ]] && : >| "${gpg_agent_config_file}"

    [[ "${pinentry_path}" == "" ]] || rg -qF "${pinentry_path}" "${gpg_agent_config_file}" && {
        return
    }

    echo "pinentry-program ${pinentry_path}" | tee -a "${gpg_agent_config_file}" >/dev/null
    killall gpg-agent
}

get_gpg_keys() {
    local email="${1}"

    log_debug "Fetching GPG public keys for ${email}"

    gpg --list-keys --keyid-format LONG "${email}" 2>/dev/null | rg '^pub' | awk '{print $2}' | cut -d'/' -f2 || true
}

get_gpg_secret_keys_fingerprints() {
    local email="${1}"

    log_debug "Fetching GPG secret keys for ${email}"

    gpg --list-secret-keys --keyid-format LONG "${email}" 2>/dev/null | rg -A 1 '^sec' | rg '[0-9A-F]{40}' | xargs -r || true
}

get_gpg_public_key_string() {
    local email="${1}"

    log_debug "Fetching GPG public keys for ${email}"

    [[ -z "${email}" ]] && return

    echo "${USER} $(gpg --export-ssh-key "${email}")" | tee >(pbcopy) | { cat; }
}

delete_gpg_entries() {
    local email="${1}"

    log_warning "Deleting GPG entries for: ${email}"

    [[ -z "${email}" ]] && return

    local signing_key_id
    printf -v signing_key_id '%s' "$(get_gpg_keys "${email}" | head -n 1)"

    [[ -z "${signing_key_id}" ]] && return

    log_debug "Found a key for ${email} (key: ${signing_key_id})"

    local public_key_string
    public_key_string="$(get_gpg_public_key_string "${email}")"

    [[ -n "${public_key_string}" ]] && {
        rg -vF -- "${public_key_string}" ~/.ssh/allowed_singers | sponge ~/.ssh/allowed_singers || true
    }

    rg -v "${signing_key_id}" "${ZDOTDIR}/local/keychain.zsh" | sponge "${ZDOTDIR}/local/keychain.zsh" || true

    # Secret keys should be deleted first.
    get_gpg_secret_keys_fingerprints "${email}" | xargs -r gpg --batch --delete-secret-keys --yes
    echo "${signing_key_id}" | xargs -r gpg --batch --delete-keys --yes
}

get_gpg_armor() {
    local email="${1}"

   [[ -z "${email}" ]] && abort "Missing email"

   gpg --armor --export "${email}" 2>/dev/null | tee >(pbcopy) | { cat; }
}

create_gpg_key() {
    local email="${1}" \
          name="${2}" \
          pass_phrase="${3}"

    log_info "Creating GPG key for: ${name} <${email}>"

    create_gpg_agent_data_dir
    update_pinentry_path

    local signing_key_id
    printf -v signing_key_id '%s' "$(get_gpg_keys "${email}" | head -n 1)"

    [[ "${FORCE_REINSTALL}" != "true" ]] && [[ -n "${signing_key_id}" ]] && {
        log_warning "GPG key ${signing_key_id} already exists for email: ${email}"

        return
    }

    delete_gpg_entries "${email}"

    log_debug "Creating batch GPG key for: ${name} <${email}>"

    # export GNUPGHOME="$(mktemp -d)" # for debugging - setting gpg home to different location.
    # https://www.gnupg.org/documentation/manuals/gnupg/Unattended-GPG-key-generation.html
    gpg --batch --expert --generate-key -q <<eoGpgKeyParmas
        %echo "Generating ECC keys (auth, sign & encr) with no-expiry"
        Key-Type: EDDSA
        Key-Curve: ed25519
        Key-Usage: auth,sign
        Subkey-Type: ECDH
        Subkey-Curve: cv25519
        Subkey-Usage: encrypt
        Name-Comment: Git User
        Name-Email: ${email}
        Name-Real: ${name}
        Expire-Date: 0
        Passphrase: ${pass_phrase}
        # Do a commit here, so that we can later print "done" :-)
        %commit
        %echo done
eoGpgKeyParmas

    get_gpg_keys "${email}" | head -n 1
}

configure_git(){
    local email="${1}" \
          name="${2}" \
          signing_key_id="${3}" \
          github_username="${4}" \
          config_path="${XDG_CONFIG_HOME}/git/${PROFILE}-config"

    log_debug "Configuring git with: ${name} <${email}>, signing_key = ${signing_key_id} \n Github user: ${github_username}"

    case "${PROFILE}" in
        private|work)
            log_debug "Configuring ${PROFILE} git profile for ${email}"

            cp "${XDG_CONFIG_HOME}/git/${PROFILE}-config.dist" "${config_path}"
            sed -i '' "s|.*email.*|	email      = ${email}|g" "${config_path}"
            sed -i '' "s|.*name.*|	name       = ${name}|g" "${config_path}"
            sed -i '' "s|.*signingkey.*|	signingkey = ${signing_key_id}|g" "${config_path}"
            return
        ;;
    esac

    git config --global user.name "${name}"
    git config --global user.email "${email}"
    git config --global user.signingkey "${signing_key_id}"
    git config --global github.user "${github_username}"
}

configure_allowed_signers() {
    local email="${1}"

    log_info "Configuring SSH keys..."

    [[ "${FORCE_REINSTALL}" == "true" ]] && {
        echo "" >| ~/.ssh/allowed_singers
    }

    local keys=(
        "ed25519"
        "rsa"
    ) \
          key \
          key_file \
          public_key_string

    touch ~/.ssh/allowed_singers

    for key in "${!keys[@]}"; do
        key_file="id_${keys[${key}]}"
        public_key_string="$(cat "${HOME}/.ssh/${key_file}.pub")"

        [[ "${FORCE_REINSTALL}" == "true" ]] || ! rg -qF -- "${public_key_string}" ~/.ssh/allowed_singers && {
            echo "${USER} $(cat "${HOME}/.ssh/${key_file}.pub")" >> ~/.ssh/allowed_singers

            continue
        }

        log_notice "SSH key ${key_file} does not exist or FORCE_REINSTALL is not true. Skipping."
    done

    [[ -z "${email}" ]] && abort "Empty email."

    log_info "Exporting GPG key for ${email} as SSH key."

    public_key_string="$(get_gpg_public_key_string "${email}")"

    [[ -n "${public_key_string}" ]] && return

    [[ "${FORCE_REINSTALL}" == "true" ]] || ! rg -qF -- "${public_key_string}" ~/.ssh/allowed_singers && {
        echo "${public_key_string}" >> ~/.ssh/allowed_singers
    } || return 0
}

configure_keychain() {
    local signing_key_id="${1}"

    log_info "Configuring keychain for ${signing_key_id}"

    [[ "${FORCE_REINSTALL}" == "true" ]] || [[ ! -f "${ZDOTDIR}/local/keychain.zsh" ]] && {
        printf '%b' '#!/usr/bin/env zsh\n\n' >| "${ZDOTDIR}/local/keychain.zsh"
    }

    ! rg -qF "${signing_key_id}" "${ZDOTDIR}/local/keychain.zsh" && {
        printf '%b' "keychain --eval --agents gpg ${signing_key_id} >/dev/null 2>&1\n" >> "${ZDOTDIR}/local/keychain.zsh"
    } || return 0
}

create() {
    # shellcheck disable=SC2153
    create_gpg_key "${GIT_EMAIL}" "${GIT_USER}" "${PASS_PHRASE}"
}

configure() {
    local signing_key_id="${1}"

    # shellcheck disable=SC2153
    configure_allowed_signers "${GIT_EMAIL}"
    # shellcheck disable=SC2153
    configure_git "${GIT_EMAIL}" "${GIT_USER}" "${signing_key_id}" "${GITHUB_USERNAME}"

    configure_keychain "${signing_key_id}"
}

main() {
    {
        read -r signing_key_id
    } <<< "$(create)"

    configure "${signing_key_id}"
}

main "$@"
