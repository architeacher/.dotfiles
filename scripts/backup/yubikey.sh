#!/usr/bin/env bash
#
# age on a YubiKey: backup and test-restore of the identity stub.
# The private key never leaves the device. This saves only the stub that points
# at it. Real protection: encrypt to a second recipient (spare key or plain key).
# Sourced by scripts/backup.sh, not run on its own.
# cmd_* run through backup.sh's dynamic dispatch, which ShellCheck cannot follow.
# shellcheck disable=SC2317,SC2329

# Prints the first age1yubikey1... recipient of an identity file.
yubikey_recipient() {
    rg -o 'age1yubikey1[a-z0-9]+' "${1}" | head -n1 || true
}

# Encrypts a probe to the recipient and decrypts it on the device.
yubikey_round_trip() {
    local identity="${1:-}" \
          recipient

    require_file IDENTITY "${identity}"
    require_tools age rg

    recipient="$(yubikey_recipient "${identity}")"
    require_value RECIPIENT "${recipient}"

    log_notice "Enter the PIN, touch the key if it blinks."

    [[ "$(echo "${YK_PROBE}" | age -r "${recipient}" | age -d -i "${identity}")" == "${YK_PROBE}" ]] \
        || abort "YubiKey round trip FAILED for ${recipient}"

    log_info "YubiKey round trip ok: ${recipient}"
}

cmd_age_yubikey_backup() {
    local out="${AGE_OUT}" \
          args=() \
          recipient

    require_tools age age-plugin-yubikey rg
    require_absent "${out}-yubikey.age" "${out}-yubikey.pub"

    [[ -n "${SERIAL}" ]] && args+=(--serial "${SERIAL}")
    [[ -n "${SLOT}" ]] && args+=(--slot "${SLOT}")

    ensure_temp_dir
    # ${args[@]+...} avoids the empty array + set -u error in Bash < 4.4.
    age-plugin-yubikey --identity ${args[@]+"${args[@]}"} > "${temp_dir}/identity.txt"

    recipient="$(yubikey_recipient "${temp_dir}/identity.txt")"
    require_value RECIPIENT "${recipient}"
    printf '%s\n' "${recipient}" > "${temp_dir}/yk.pub"

    log_notice "Recipient, note it: ${recipient}"

    age -p -o "${temp_dir}/yk.age" "${temp_dir}/identity.txt"

    ensure_parent_dir "${out}"
    mv "${temp_dir}/yk.age" "${out}-yubikey.age"
    mv "${temp_dir}/yk.pub" "${out}-yubikey.pub"

    log_info "Done: ${out}-yubikey.age and ${out}-yubikey.pub"
    log_warning "This is a stub. Lose the key, lose the data. Add a 2nd recipient."
}

# Decrypts the stub into the temp dir, checks it against the saved .pub, then
# round-trips a message through the YubiKey. Needs the device, PIN and touch.
cmd_age_yubikey_test_restore() {
    local bak="${1:-${AGE_OUT}-yubikey.age}" \
          want="${2:-}"

    require_tools age-plugin-yubikey

    ensure_temp_dir
    cmd_age_restore "${bak}" "${temp_dir}/out/identity.txt" "${want}"
    yubikey_round_trip "${temp_dir}/out/identity.txt"
}
