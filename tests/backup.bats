#!/usr/bin/env bats
# Run: bats tests/backup.bats
# Needs: bats-core, rg, ssh-keygen, age-keygen. age, age-plugin-yubikey and gpg
# are replaced by the test doubles in mocks/backup/, so nothing prompts.
# gpg backup/restore are interactive (passphrase, revoke prompt) and not covered.

setup() {
    TEST_DIR="$(mktemp -d)"
    BACKUP="${BATS_TEST_DIRNAME}/../scripts/backup.sh"

    PATH="${BATS_TEST_DIRNAME}/mocks/backup:${PATH}"

    export HOME="${TEST_DIR}/home"
    export BACKUP_ROOT="${TEST_DIR}/backup"
    export BACKUP_DATE="20261013"
    export SOPS_CONFIG="${TEST_DIR}/sops.yaml"
    unset BACKUP_DIR SSH_KEY AGE_KEY SOPS_AGE_KEY_FILE SOPS_AGE_SSH_PRIVATE_KEY_FILE FORCE \
          GPG_OUT AGE_OUT SSH_OUT PACK_OUT FPR PUB LOG_LEVEL

    mkdir -p "${HOME}/.ssh"
    export SSH_KEY="${HOME}/.ssh/id_ed25519_sops"
    export AGE_KEY="${HOME}/keys.txt"

    # Same file name as SSH_KEY, so backup and restore agree on id_ed25519_sops.age.
    export SRC_KEY="${TEST_DIR}/src/id_ed25519_sops"
    mkdir -p "${TEST_DIR}/src"
    ssh-keygen -q -t ed25519 -N "" -C "me.sops" -f "${SRC_KEY}"
    age-keygen -o "${TEST_DIR}/age_key" 2>/dev/null
    printf 'creation_rules:\n  - age:\n      - "%s"\n' "$(cat "${SRC_KEY}.pub")" > "${SOPS_CONFIG}"
}

teardown() {
    rm -rf "${TEST_DIR}"
}

backup() {
    bash "${BACKUP}" "$@"
}

# Creates an ssh backup of the sops test key in BACKUP_ROOT/BACKUP_DATE.
make_ssh_backup() {
    SSH_KEY="${SRC_KEY}" backup ssh-backup
}

# True when the last `run` output contains the phrase, ignoring case.
has() {
    printf '%s' "${output}" | rg -qiF -- "${1}"
}

# Prints "TYPE KEY" of a public key file.
key_id() {
    awk '{print $1" "$2}' "${1}"
}

# --- dispatch ---------------------------------------------------------------

@test "help lists the commands" {
    run backup help
    [ "${status}" -eq 0 ]
    has "ssh-restore"
    has "BACKUP_ROOT="
}

@test "unknown command fails" {
    run backup nope
    [ "${status}" -ne 0 ]
    has "unknown command"
}

# --- latest -----------------------------------------------------------------

@test "latest picks the newest dated folder or archive" {
    local cases=(
        "20261012/|20261012"
        "20261012/ 20261105.tar.gz.age|20261105"
        "20261012/ 20261012-old/ 2026101/ 99notes.txt|20261012"
    )
    local case entries want entry

    for case in "${cases[@]}"; do
        entries="${case%%|*}"
        want="${case##*|}"
        rm -rf "${BACKUP_ROOT}"; mkdir -p "${BACKUP_ROOT}"
        for entry in ${entries}; do
            [[ "${entry}" == */ ]] && mkdir -p "${BACKUP_ROOT}/${entry}" || touch "${BACKUP_ROOT}/${entry}"
        done

        run backup latest
        [ "${status}" -eq 0 ]
        [ "${output}" = "${BACKUP_ROOT}/${want}" ]
    done
}

@test "latest fails without backups" {
    mkdir -p "${BACKUP_ROOT}"
    run backup latest
    [ "${status}" -ne 0 ]
    has "no backups in"
}

@test "read commands use the latest backup and say so" {
    make_ssh_backup
    run backup ssh-test-restore
    [ "${status}" -eq 0 ]
    has "using backup: ${BACKUP_ROOT}/20261013"
}

# --- age --------------------------------------------------------------------

@test "age backup then test-restore" {
    cp "${TEST_DIR}/age_key" "${AGE_KEY}"
    run backup age-backup
    [ "${status}" -eq 0 ]
    [ -f "${BACKUP_ROOT}/20261013/age-key.age" ]
    [ "$(cat "${BACKUP_ROOT}/20261013/age-key.pub")" = "$(age-keygen -y "${AGE_KEY}")" ]

    run backup age-test-restore
    [ "${status}" -eq 0 ]
}

@test "age backup refuses to overwrite an existing backup" {
    cp "${TEST_DIR}/age_key" "${AGE_KEY}"
    backup age-backup
    run backup age-backup
    [ "${status}" -ne 0 ]
    has "already exists"
}

@test "cancelled age backup leaves no folder" {
    cp "${TEST_DIR}/age_key" "${AGE_KEY}"
    AGE_FAIL=1 run backup age-backup
    [ "${status}" -ne 0 ]
    [ ! -e "${BACKUP_ROOT}/20261013" ]
}

@test "age restore refuses an existing destination and a wrong PUB" {
    cp "${TEST_DIR}/age_key" "${AGE_KEY}"
    backup age-backup

    run backup age-restore
    [ "${status}" -ne 0 ]
    has "already exists"

    run backup age-test-restore "" "age1notthekey"
    [ "${status}" -ne 0 ]
    has "PUB not among restored keys"
}

@test "age restore detects a tampered .pub" {
    cp "${TEST_DIR}/age_key" "${AGE_KEY}"
    backup age-backup
    echo "age1tampered" > "${BACKUP_ROOT}/20261013/age-key.pub"
    run backup age-test-restore
    [ "${status}" -ne 0 ]
    has "MISMATCH"
}

# --- yubikey ----------------------------------------------------------------

@test "yubikey backup then test-restore round trips" {
    run backup age-yubikey-backup
    [ "${status}" -eq 0 ]
    [ "$(cat "${BACKUP_ROOT}/20261013/age-key-yubikey.pub")" = "age1yubikey1qtestrecipient" ]

    run backup age-yubikey-test-restore
    [ "${status}" -eq 0 ]
    has "round trip ok"
}

@test "yubikey test-restore fails when the device decrypts wrongly" {
    backup age-yubikey-backup
    AGE_BAD=1 run backup age-yubikey-test-restore
    [ "${status}" -ne 0 ]
}

# --- ssh backup -------------------------------------------------------------

@test "ssh backup is named after the key and keeps the original .pub" {
    run make_ssh_backup
    [ "${status}" -eq 0 ]
    [ -f "${BACKUP_ROOT}/20261013/id_ed25519_sops.age" ]
    [ "$(cat "${BACKUP_ROOT}/20261013/id_ed25519_sops.pub")" = "$(cat "${SRC_KEY}.pub")" ]
}

@test "ssh backup refuses a .pub of another key and leaves no folder" {
    ssh-keygen -q -t ed25519 -N "" -f "${TEST_DIR}/other"
    cp "${TEST_DIR}/other.pub" "${SRC_KEY}.pub"
    run make_ssh_backup
    [ "${status}" -ne 0 ]
    has "does not match"
    [ ! -e "${BACKUP_ROOT}/20261013" ]
}

# --- ssh restore ------------------------------------------------------------

@test "ssh restore into an empty ~/.ssh writes the key and the original .pub" {
    make_ssh_backup
    run backup ssh-restore "${BACKUP_ROOT}/20261013/id_ed25519_sops.age"
    [ "${status}" -eq 0 ]
    cmp -s "${SSH_KEY}" "${SRC_KEY}"
    [ "$(cat "${SSH_KEY}.pub")" = "$(cat "${SRC_KEY}.pub")" ]
    [ "$(stat -f '%Lp' "${SSH_KEY}")" = "600" ]
}

@test "ssh restore of the same key changes nothing" {
    make_ssh_backup
    cp "${SRC_KEY}" "${SSH_KEY}"
    cp "${SRC_KEY}.pub" "${SSH_KEY}.pub"
    run backup ssh-restore "${BACKUP_ROOT}/20261013/id_ed25519_sops.age"
    [ "${status}" -eq 0 ]
    has "already in place"
    [ -z "$(ls "${HOME}/.ssh" | rg replaced || true)" ]
}

@test "ssh restore moves another key aside" {
    local cases=("key+pub" "pub only")
    local case

    make_ssh_backup
    for case in "${cases[@]}"; do
        rm -f "${HOME}/.ssh/"*
        ssh-keygen -q -t ed25519 -N "" -C other -f "${TEST_DIR}/other_${case// /_}"
        [ "${case}" = "pub only" ] || cp "${TEST_DIR}/other_${case// /_}" "${SSH_KEY}"
        cp "${TEST_DIR}/other_${case// /_}.pub" "${SSH_KEY}.pub"

        run backup ssh-restore "${BACKUP_ROOT}/20261013/id_ed25519_sops.age"
        [ "${status}" -eq 0 ]
        has "moved existing"
        cmp -s "${SSH_KEY}" "${SRC_KEY}"
        [ "$(key_id "${SSH_KEY}.pub")" = "$(key_id "${SRC_KEY}.pub")" ]
        ls "${HOME}/.ssh" | rg -q 'replaced-.*\.pub$'
    done
}

@test "ssh restore keeps a matching .pub with its own comment" {
    make_ssh_backup
    printf '%s my-comment\n' "$(key_id "${SRC_KEY}.pub")" > "${SSH_KEY}.pub"
    run backup ssh-restore "${BACKUP_ROOT}/20261013/id_ed25519_sops.age"
    [ "${status}" -eq 0 ]
    [[ "$(cat "${SSH_KEY}.pub")" == *"my-comment" ]]
}

@test "ssh restore falls back to a legacy ssh-key backup" {
    make_ssh_backup
    mv "${BACKUP_ROOT}/20261013/id_ed25519_sops.age" "${BACKUP_ROOT}/20261013/ssh-key.age"
    mv "${BACKUP_ROOT}/20261013/id_ed25519_sops.pub" "${BACKUP_ROOT}/20261013/ssh-key.pub"
    run backup ssh-test-restore
    [ "${status}" -eq 0 ]
}

# --- sops recipient check ---------------------------------------------------

@test "ssh restore refuses a key that is not a sops recipient" {
    make_ssh_backup
    echo 'creation_rules: []' > "${SOPS_CONFIG}"
    ssh-keygen -q -t ed25519 -N "" -C live -f "${SSH_KEY}"
    local before
    before="$(shasum "${SSH_KEY}")"

    run backup ssh-restore "${BACKUP_ROOT}/20261013/id_ed25519_sops.age"
    [ "${status}" -ne 0 ]
    has "not a recipient"
    [ "$(shasum "${SSH_KEY}")" = "${before}" ]
    [ -z "$(ls "${HOME}/.ssh" | rg replaced || true)" ]

    FORCE=1 run backup ssh-restore "${BACKUP_ROOT}/20261013/id_ed25519_sops.age"
    [ "${status}" -eq 0 ]
    cmp -s "${SSH_KEY}" "${SRC_KEY}"
}

@test "ssh restore skips the sops check without a .sops.yaml" {
    make_ssh_backup
    SOPS_CONFIG="${TEST_DIR}/missing.yaml" run backup ssh-test-restore
    [ "${status}" -eq 0 ]
    has "skipping the sops recipient check"
}

# --- pack / unpack / run ----------------------------------------------------

@test "pack, unpack and run from the archive" {
    make_ssh_backup
    run backup pack
    [ "${status}" -eq 0 ]
    [ -f "${BACKUP_ROOT}/20261013.tar.gz.age" ]

    run backup pack
    [ "${status}" -ne 0 ]

    rm -rf "${BACKUP_ROOT}/20261013"
    run backup run ssh-test-restore
    [ "${status}" -eq 0 ]
    [ ! -e "${BACKUP_ROOT}/20261013" ]

    run backup unpack
    [ "${status}" -eq 0 ]
    [ -f "${BACKUP_ROOT}/20261013/id_ed25519_sops.age" ]

    run backup unpack
    [ "${status}" -ne 0 ]
    has "already exists"
}

@test "run stops at the first failing command" {
    make_ssh_backup
    run backup run ssh-test-restore age-test-restore ssh-test-restore
    [ "${status}" -ne 0 ]
    has "age-test-restore failed"
}

# --- verify -----------------------------------------------------------------

@test "verify passes for complete keys and fails for wrong modes or stubs" {
    cp "${TEST_DIR}/age_key" "${AGE_KEY}"; chmod 600 "${AGE_KEY}"
    cp "${SRC_KEY}" "${SSH_KEY}"; cp "${SRC_KEY}.pub" "${SSH_KEY}.pub"

    run backup verify
    [ "${status}" -eq 0 ]
    has "verify ok"

    GPG_STUB=1 run backup verify
    [ "${status}" -ne 0 ]

    chmod 644 "${AGE_KEY}"
    run backup verify
    [ "${status}" -ne 0 ]
    has "not mode 600"
}

# --- temp files -------------------------------------------------------------

@test "no temp dirs are left behind" {
    local before
    before="$(ls -d /tmp/keys.* 2>/dev/null | wc -l)"
    make_ssh_backup
    backup ssh-test-restore
    AGE_FAIL=1 backup age-backup || true
    [ "$(ls -d /tmp/keys.* 2>/dev/null | wc -l)" = "${before}" ]
}
