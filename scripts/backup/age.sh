#!/usr/bin/env bash
#
# age: backup, restore and test-restore of an identity file (keys.txt).
# The backup is the file encrypted with an age passphrase, plus its public keys.
# Restore works for plain and yubikey backups alike.
# Sourced by scripts/backup.sh, not run on its own.
# cmd_* run through backup.sh's dynamic dispatch, which ShellCheck cannot follow.
# shellcheck disable=SC2317,SC2329

# Prints the public keys of an identity file, one per line, sorted.
# age-keygen -y rejects plugin identities (AGE-PLUGIN-YUBIKEY-...), so native
# keys go through it and yubikey recipients are read from the "Recipient:" comments.
age_public_keys() {
    local identity="${1}" \
          native_count

    {
        native_count="$(rg -c '^AGE-SECRET-KEY-' "${identity}" || true)"
        [[ "${native_count:-0}" -gt 0 ]] && rg '^AGE-SECRET-KEY-' "${identity}" | age-keygen -y
        rg -o 'age1yubikey1[a-z0-9]+' "${identity}" || true
    } | sort -u
}

cmd_age_backup() {
    local src="${AGE_KEY}" \
          out="${AGE_OUT}" \
          pubs \
          pub

    require_file AGE_KEY "${src}"
    require_tools age age-keygen rg
    require_absent "${out}.age" "${out}.pub"

    pubs="$(age_public_keys "${src}")" || abort "Cannot derive public keys from ${src}"
    [[ -n "${pubs}" ]] || abort "No public keys found in ${src}"

    ensure_temp_dir
    printf '%s\n' "${pubs}" > "${temp_dir}/age.pub"

    log_notice "Public key(s), note them:"
    while IFS= read -r pub; do
        log_notice "  ${pub}"
    done <<< "${pubs}"

    age -p -o "${temp_dir}/age.age" "${src}"

    ensure_parent_dir "${out}"
    mv "${temp_dir}/age.age" "${out}.age"
    mv "${temp_dir}/age.pub" "${out}.pub"

    log_info "Done: ${out}.age and ${out}.pub"
}

# PUB must be one of the restored keys. Without PUB, the whole list is
# compared with the .pub file saved next to the backup.
cmd_age_restore() {
    local bak="${1:-${AGE_OUT}.age}" \
          dest="${2:-${AGE_KEY}}" \
          want="${3:-}" \
          got
    local pub="${bak%.age}.pub"

    require_backup "${bak}"
    require_value DEST "${dest}"
    require_tools age age-keygen rg
    require_absent "${dest}"

    ensure_temp_dir
    age -d -o "${temp_dir}/restored" "${bak}"
    chmod 600 "${temp_dir}/restored"

    got="$(age_public_keys "${temp_dir}/restored")" || abort "Cannot derive public keys from the backup."
    [[ -n "${got}" ]] || abort "No public keys found in the backup."

    if [[ -n "${want}" ]]; then
        rg -qxF "${want}" <<< "${got}" || abort "PUB not among restored keys: ${got}"
    else
        [[ -f "${pub}" ]] || abort "Nothing to compare with, pass PUB. Restored keys: ${got}"
        [[ "${got}" == "$(< "${pub}")" ]] || abort "Public keys MISMATCH, got: ${got}"
    fi

    ensure_parent_dir "${dest}"
    mv "${temp_dir}/restored" "${dest}"

    log_info "Verified. Restored to ${dest}, keys: ${got}"
}

# Restores into the temp dir and verifies. Your real key file is not touched.
cmd_age_test_restore() {
    local bak="${1:-${AGE_OUT}.age}" \
          want="${2:-}"

    ensure_temp_dir
    cmd_age_restore "${bak}" "${temp_dir}/out/keys.txt" "${want}"
}
