#!/usr/bin/env bash

set -Eeuo pipefail

create_ssh_key() {
    local key_file="${1}" \
          key_type="${2}" \
          pass_phrase="${3}" \
          email="${4}"

    log_debug "Creating SSH key: ${key_file}"

    # https://stackoverflow.com/questions/43235179/how-to-execute-ssh-keygen-without-prompt
    ssh-keygen -f ~/.ssh/"${key_file}" -t "${key_type}" -N "${pass_phrase}" -C "${email}" -q <<<y >/dev/null 2>&1
}

create_ssh_keys() {
    local email="${1}" \
          pass_phrase="${2}"

    log_info "Generating SSH keys for ${email}..."

    local keys=(
        "ed25519"
        "rsa"
    ) \
          key \
          key_file

    for key in "${!keys[@]}"; do
        key_file="id_${keys[${key}]}"

        [ "${FORCE_REINSTALL}" == "true" ] || [ ! -f ~/.ssh/"${key_file}" ] && {
            create_ssh_key "${key_file}" "${keys[${key}]}" "${pass_phrase}" "${email}"

            continue
        }

        log_debug "SSH key ${key_file} already exists and FORCE_REINSTALL is not true. Skipping."
    done
}

main() {
    # shellcheck disable=SC2153
    create_ssh_keys "${GIT_EMAIL}" "${PASS_PHRASE}" >&2
}

main "$@"
