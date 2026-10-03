#!/usr/bin/env bash
#
# ssh: backup, restore and test-restore of the sops ssh key (sops key group 2).
# sops needs this key, so losing it locks you out. The backup is the private key
# encrypted with an age passphrase, plus the original .pub (comment included).
# Files are named after SSH_KEY, e.g. id_ed25519_sops.age and id_ed25519_sops.pub.
# Sourced by scripts/backup.sh, not run on its own.
# cmd_* run through backup.sh's dynamic dispatch, which ShellCheck cannot follow.
# shellcheck disable=SC2317,SC2329

# Prints "TYPE KEY" of a public key line, without the comment.
ssh_key_id() {
    printf '%s\n' "${1}" | awk 'NR==1{print $1" "$2}'
}

# Renames FILE to FILE.replaced-STAMP, keeping .pub as the last suffix.
set_aside() {
    local file="${1}" \
          stamp="${2}" \
          target

    target="${file%.pub}.replaced-${stamp}"
    [[ "${file}" == *.pub ]] && target="${target}.pub"

    require_absent "${target}"
    mv "${file}" "${target}"

    log_warning "Moved existing ${file} to ${target}, delete it once you are sure."
}

# The restored key must be a recipient in SOPS_CONFIG, unless FORCE=1.
# Skipped with a warning when there is no SOPS_CONFIG.
check_sops_recipient() {
    local key_id="${1}" \
          blob

    [[ -f "${SOPS_CONFIG}" ]] || {
        log_warning "No ${SOPS_CONFIG}, skipping the sops recipient check."

        return 0
    }

    blob="$(printf '%s\n' "${key_id}" | awk '{print $2}')"
    [[ -n "${blob}" ]] || abort "Cannot read the restored public key."

    rg -qF "${blob}" "${SOPS_CONFIG}" && {
        log_info "Sops recipient ok: ${SOPS_CONFIG}"

        return 0
    }

    [[ "${FORCE}" == "1" ]] \
        || abort "Key is not a recipient in ${SOPS_CONFIG}: ${key_id}. Stale backup? FORCE=1 restores anyway."

    log_warning "FORCE=1, restoring a key that is not a sops recipient."
}

# Prints the default backup file: SSH_OUT.age, else the legacy ssh-key.age.
default_ssh_backup() {
    local legacy="${BACKUP_DIR}/${SSH_LEGACY}.age"

    [[ ! -f "${SSH_OUT}.age" && -f "${legacy}" ]] && {
        printf '%s\n' "${legacy}"

        return 0
    }

    printf '%s\n' "${SSH_OUT}.age"
}

cmd_ssh_backup() {
    local src="${SSH_KEY}" \
          out="${SSH_OUT}" \
          pub

    require_file SSH_KEY "${src}"
    require_tools age ssh-keygen
    require_absent "${out}.age" "${out}.pub"

    ssh-keygen -y -P "" -f "${src}" >/dev/null 2>&1 && log_warning "The ssh key has no passphrase."

    pub="$(ssh-keygen -y -f "${src}")" || abort "Cannot read ssh key: ${src}"

    # Keep the original .pub (with its comment), but only if it belongs to the key.
    [[ -f "${src}.pub" ]] && {
        [[ "$(ssh_key_id "$(< "${src}.pub")")" == "$(ssh_key_id "${pub}")" ]] \
            || abort "${src}.pub does not match ${src}"

        pub="$(< "${src}.pub")"
    }

    ensure_temp_dir
    printf '%s\n' "${pub}" > "${temp_dir}/ssh.pub"

    log_notice "Public key, note it: ${pub}"
    log_notice "Sops recipient, compare with .sops.yaml: $(ssh_key_id "${pub}")"

    age -p -o "${temp_dir}/ssh.age" "${src}"

    ensure_parent_dir "${out}"
    mv "${temp_dir}/ssh.age" "${out}.age"
    mv "${temp_dir}/ssh.pub" "${out}.pub"

    log_info "Done: ${out}.age and ${out}.pub"
}

# Compares with PUB, else with the .pub file saved next to the backup.
# DEST always ends up holding the backup key. Existing files of another key
# are moved aside, never deleted. An identical DEST is left untouched.
cmd_ssh_restore() {
    local bak="${1:-$(default_ssh_backup)}" \
          dest="${2:-${SSH_KEY}}" \
          want="${3:-}" \
          got \
          pub_line \
          stamp
    local saved_pub="${bak%.age}.pub"

    require_backup "${bak}"
    require_value DEST "${dest}"
    require_tools age ssh-keygen rg

    ensure_temp_dir
    age -d -o "${temp_dir}/restored" "${bak}"
    chmod 600 "${temp_dir}/restored"

    got="$(ssh-keygen -y -f "${temp_dir}/restored")" || abort "The restored file is not a valid ssh key."
    got="$(ssh_key_id "${got}")"

    [[ -z "${want}" && -f "${saved_pub}" ]] && want="$(< "${saved_pub}")"
    [[ -n "${want}" ]] || abort "Nothing to compare with, pass PUB. Restored key: ${got}"
    [[ "${got}" == "$(ssh_key_id "${want}")" ]] || abort "ssh public key MISMATCH: got ${got}"

    # Checked before anything in DEST is touched.
    check_sops_recipient "${got}"

    # The backed-up .pub keeps its comment. Without one, write the bare key.
    pub_line="${got}"
    [[ -f "${saved_pub}" && "$(ssh_key_id "$(< "${saved_pub}")")" == "${got}" ]] && pub_line="$(< "${saved_pub}")"

    stamp="$(date +%Y%m%d-%H%M%S)"

    # An existing DEST.pub is kept only if it belongs to the restored key.
    [[ -e "${dest}.pub" && "$(ssh_key_id "$(< "${dest}.pub")")" != "${got}" ]] && set_aside "${dest}.pub" "${stamp}"

    # Byte compare: works for passphrase-protected keys without asking for it.
    if [[ -e "${dest}" ]] && cmp -s "${dest}" "${temp_dir}/restored"; then
        log_notice "Already in place, unchanged: ${dest}"
    else
        [[ -e "${dest}" ]] && set_aside "${dest}" "${stamp}"

        ensure_parent_dir "${dest}"
        mv "${temp_dir}/restored" "${dest}"
    fi

    [[ -e "${dest}.pub" ]] || printf '%s\n' "${pub_line}" > "${dest}.pub"

    log_info "Verified. Restored to ${dest}, key: ${got}"
}

# Restores into the temp dir and verifies. Your real key file is not touched.
cmd_ssh_test_restore() {
    local bak="${1:-}" \
          want="${2:-}"

    ensure_temp_dir
    cmd_ssh_restore "${bak}" "${temp_dir}/out/id" "${want}"
}
