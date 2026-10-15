#!/usr/bin/env bash
#
# gpg: backup, restore and test-restore of a secret key.
# The backup is a tar of public, secret, ownertrust, fingerprints and a
# revocation certificate, symmetrically encrypted with gpg.
# Sourced by scripts/backup.sh, not run on its own.
# cmd_* run through backup.sh's dynamic dispatch, which ShellCheck cannot follow.
# shellcheck disable=SC2317,SC2329

# Strips spaces and upper-cases a fingerprint, so pasted values compare.
normalize_fingerprint() {
    printf '%s' "${1:-}" | tr -d ' ' | tr '[:lower:]' '[:upper:]'
}

# Prints the fingerprints of a secret key and its subkeys, primary first.
list_fingerprints() {
    gpg --with-colons --list-secret-keys --fingerprint "$@" | awk -F: '$1=="fpr"{print $10}'
}

# Checks the imported key against the list stored in the backup and, if given,
# against the fingerprint you noted before (the independent check).
# Sets PRIMARY for the checks that follow.
verify_fingerprints() {
    local stored="${1}" \
          want="${2:-}" \
          selector \
          got \
          primary

    [[ -f "${stored}" || -n "${want}" ]] || abort "No stored fingerprints in the backup, pass FPR."

    selector="$(normalize_fingerprint "${want}")"
    [[ -f "${stored}" ]] && selector="$(sed -n '1p' "${stored}")"

    got="$(list_fingerprints "${selector}")" || abort "Key not found after import: ${selector}"
    primary="$(printf '%s\n' "${got}" | sed -n '1p')"

    [[ -f "${stored}" ]] && {
        [[ "$(printf '%s\n' "${got}" | sort)" == "$(sort "${stored}")" ]] \
            || abort "Fingerprint MISMATCH vs the list stored in the backup."
    }

    [[ -n "${want}" ]] && {
        [[ "${primary}" == "$(normalize_fingerprint "${want}")" ]] \
            || abort "Fingerprint MISMATCH vs FPR: got ${primary}"
    }

    PRIMARY="${primary}"
    log_info "Fingerprints match: ${primary}"
}

# The key in PRIMARY must not be revoked or expired.
check_key_usable() {
    local state

    state="$(gpg --with-colons --list-secret-keys "${PRIMARY}" \
        | awk -F: '$1=="sec" && !seen++ {print $2}')" || abort "Cannot list key: ${PRIMARY}"

    [[ "${state}" != "r" ]] || abort "Key is REVOKED: ${PRIMARY}"
    [[ "${state}" != "e" ]] || abort "Key is EXPIRED: ${PRIMARY}"

    log_info "Key is not revoked or expired."
}

# Signs and verifies with PRIMARY. Asks for the key passphrase.
sign_test() {
    GPG_TTY="$(tty 2>/dev/null || true)"
    export GPG_TTY

    log_notice "Sign test, enter the key passphrase if asked."

    echo "test" | gpg --clearsign --local-user "${PRIMARY}" | gpg --verify \
        || abort "Sign or verify FAILED with ${PRIMARY}"

    log_info "Sign test ok."
}

cmd_gpg_fingerprint() {
    local key="${1:-}"

    require_value KEY "${key}"
    require_tools gpg

    gpg --fingerprint "${key}"
}

cmd_gpg_backup() {
    local key="${1:-}" \
          out="${GPG_OUT}" \
          data

    require_value KEY "${key}"
    require_tools gpg tar
    require_absent "${out}.tar.gpg"

    ensure_temp_dir
    data="${temp_dir}/data"
    mkdir -p "${data}"

    gpg --armor --export "${key}" > "${data}/public.asc"
    gpg --armor --export-secret-keys "${key}" > "${data}/secret.asc"
    gpg --export-ownertrust > "${data}/ownertrust.txt"
    list_fingerprints "${key}" > "${data}/fingerprints.txt"
    gpg --armor --output "${data}/revoke.asc" --gen-revoke "${key}"

    tar -C "${data}" -cf - . | gpg --symmetric --armor --output "${temp_dir}/backup.tar.gpg"

    ensure_parent_dir "${out}"
    mv "${temp_dir}/backup.tar.gpg" "${out}.tar.gpg"

    log_notice "Primary fingerprint, note it: $(sed -n '1p' "${data}/fingerprints.txt")"
    log_info "Done: ${out}.tar.gpg"
}

# Imports into a throwaway keyring. Your keyring is not touched.
cmd_gpg_test_restore() {
    local bak="${1:-${GPG_OUT}.tar.gpg}" \
          want="${2:-${FPR:-}}" \
          gnupg_home="${GNUPGHOME:-${HOME}/.gnupg}"

    require_backup "${bak}"
    require_tools gpg tar

    ensure_temp_dir
    mkdir -p "${temp_dir}/data" "${temp_dir}/home"
    chmod 700 "${temp_dir}/home"

    gpg --decrypt "${bak}" | tar -C "${temp_dir}/data" -xf -

    # Reuse your pinentry setup. A fresh home has none.
    [[ -f "${gnupg_home}/gpg-agent.conf" ]] && cp "${gnupg_home}/gpg-agent.conf" "${temp_dir}/home/gpg-agent.conf"

    export GNUPGHOME="${temp_dir}/home"
    gpg --import "${temp_dir}/data/secret.asc"
    gpg --import-ownertrust "${temp_dir}/data/ownertrust.txt"

    verify_fingerprints "${temp_dir}/data/fingerprints.txt" "${want}"
    check_key_usable
    sign_test
}

cmd_gpg_restore() {
    local bak="${1:-${GPG_OUT}.tar.gpg}" \
          want="${2:-${FPR:-}}"

    require_backup "${bak}"
    require_tools gpg tar

    ensure_temp_dir
    gpg --decrypt "${bak}" | tar -C "${temp_dir}" -xf -
    gpg --import "${temp_dir}/secret.asc"
    gpg --import-ownertrust "${temp_dir}/ownertrust.txt"

    verify_fingerprints "${temp_dir}/fingerprints.txt" "${want}"
    check_key_usable
    sign_test

    log_info "Restored and verified."
}
