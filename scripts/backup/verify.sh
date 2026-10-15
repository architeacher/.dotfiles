#!/usr/bin/env bash
#
# verify: shows the installed gpg, age and ssh keys and runs sanity checks.
# Never prints private keys. For ssh it proves the private key matches the public one.
# Sourced by scripts/backup.sh, not run on its own.
# cmd_* run through backup.sh's dynamic dispatch, which ShellCheck cannot follow.
# shellcheck disable=SC2317,SC2329

# Logs a failed check and keeps going, so one run shows every problem.
record_failure() {
    log_error "FAIL: $*"
    failures=$((failures + 1))
}

verify_gpg() {
    local secret

    log_info "gpg public keys:"
    gpg --list-keys --keyid-format long --fingerprint

    log_info "gpg secret keys (sec# or ssb# means the secret part is missing):"
    secret="$(gpg --list-secret-keys --keyid-format long --fingerprint)" || {
        record_failure "Cannot list gpg secret keys."

        return 0
    }
    printf '%s\n' "${secret}"

    rg -q '^sec' <<< "${secret}" || record_failure "No gpg secret key."
    rg -q '^(sec|ssb)#' <<< "${secret}" && record_failure "gpg secret key is a stub, the secret part is missing."
    rg -q 'revoked|expired' <<< "${secret}" && log_warning "A gpg key or subkey is revoked or expired, check the list above."

    return 0
}

verify_age() {
    local pubs

    log_info "age identities in ${AGE_KEY}:"
    [[ -f "${AGE_KEY}" ]] || { record_failure "Missing ${AGE_KEY}"; return 0; }
    ls -l "${AGE_KEY}"

    pubs="$(age_public_keys "${AGE_KEY}")" || { record_failure "Cannot derive age public keys."; return 0; }
    [[ -n "${pubs}" ]] || record_failure "No age public keys found."

    log_info "Public keys:"
    printf '%s\n' "${pubs}"

    [[ "$(mode_of "${AGE_KEY}")" == "-rw-------" ]] || record_failure "${AGE_KEY} is not mode 600."
}

verify_ssh() {
    local dir \
          raw

    dir="$(dirname "${SSH_KEY}")"
    log_info "ssh files in ${dir}:"
    ls -la "${dir}"

    [[ -f "${SSH_KEY}" ]] || { record_failure "Missing ${SSH_KEY}"; return 0; }
    [[ -f "${SSH_KEY}.pub" ]] || { record_failure "Missing ${SSH_KEY}.pub"; return 0; }

    log_info "Public key, ${SSH_KEY}.pub:"
    cat "${SSH_KEY}.pub"
    ssh-keygen -lf "${SSH_KEY}.pub"

    [[ "$(mode_of "${SSH_KEY}")" == "-rw-------" ]] || record_failure "${SSH_KEY} is not mode 600."

    raw="$(ssh-keygen -y -f "${SSH_KEY}")" || { record_failure "Cannot read ${SSH_KEY}, wrong passphrase?"; return 0; }
    [[ "$(ssh_key_id "${raw}")" == "$(ssh_key_id "$(< "${SSH_KEY}.pub")")" ]] || {
        record_failure "The private key does not match ${SSH_KEY}.pub"

        return 0
    }

    log_info "The private key matches the public key."
}

cmd_verify() {
    require_tools gpg rg age-keygen ssh-keygen

    failures=0
    verify_gpg
    verify_age
    verify_ssh

    [[ "${failures}" -eq 0 ]] || abort "Verify FAILED with ${failures} problem(s), see the FAIL lines above."

    log_info "Verify ok."
}
