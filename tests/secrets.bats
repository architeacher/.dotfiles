#!/usr/bin/env bats
# Run: bats tests/secrets.bats
# Needs: bats-core >= 1.4, fd, rg, git on PATH. sops is replaced by the test double in mocks/secrets/.
# The script runs from a temp tree (ROOT), so the real private/ is never read or written.

setup() {
    ROOT="${BATS_TEST_TMPDIR}/repo"
    PLAIN="private/.ssh/conf.d/host"
    DIST="private/.ssh.dist/conf.d/host"
    # Fixed mtimes on either side of "now", the stamp a run leaves on both copies.
    OLDER="200001010000"
    NEWER="203701010000"

    mkdir -p "${ROOT}/scripts" "${ROOT}/private/.ssh/conf.d" "${ROOT}/private/.ssh.dist/conf.d"

    local script
    for script in secrets.sh common.sh logger.sh; do
        ln -s "${BATS_TEST_DIRNAME}/../scripts/${script}" "${ROOT}/scripts/${script}"
    done

    PATH="${BATS_TEST_DIRNAME}/mocks/secrets:${PATH}"

    export SOPS_CALLS="${BATS_TEST_TMPDIR}/sops-calls"
    : > "${SOPS_CALLS}"
    unset FORCE DRY_RUN LOG_LEVEL

    cd "${ROOT}"
}

secrets() {
    bash "${ROOT}/scripts/secrets.sh" "$@"
}

# Prints the sops commands run since the last call, on one line.
sops_calls() {
    tr '\n' ' ' < "${SOPS_CALLS}"
    : > "${SOPS_CALLS}"
}

# Writes an encrypted copy the way a git pull, checkout or reset would: new content, mtime "now".
pull_dist() {
    printf 'ENC[AES256_GCM,data:fake]\n%s\n' "${1}" > "${DIST}"
}

# True when the last `run` output contains the phrase.
has() {
    printf '%s' "${output}" | rg -qF -- "${1}"
}

# --- encrypt ------------------------------------------------------------------

@test "encrypt: writes the encrypted copy and leaves both copies with the same mtime" {
    printf 'secret\n' > "${PLAIN}"

    run secrets encrypt
    [ "${status}" -eq 0 ]
    [ "$(sops_calls)" == "encrypt " ]
    rg -q 'ENC\[AES256_GCM' "${DIST}"
    [[ ! "${PLAIN}" -nt "${DIST}" && ! "${PLAIN}" -ot "${DIST}" ]]
}

@test "encrypt: skips a file in sync without decrypting, re-encrypts an edited one" {
    printf 'secret\n' > "${PLAIN}"
    secrets encrypt
    sops_calls > /dev/null

    run secrets encrypt
    [ "${status}" -eq 0 ]
    [ -z "$(sops_calls)" ]

    printf 'edited\n' > "${PLAIN}"
    touch -t "${NEWER}" "${PLAIN}"

    run secrets encrypt
    [ "${status}" -eq 0 ]
    [ "$(sops_calls)" == "encrypt " ]
    rg -q '^edited$' "${DIST}"
}

@test "encrypt: reports a copy that differs and is older than its encrypted file, changes nothing" {
    printf 'mine\n' > "${PLAIN}"
    touch -t "${OLDER}" "${PLAIN}"
    pull_dist "theirs"

    run secrets encrypt
    [ "${status}" -eq 1 ]
    [ "$(sops_calls)" == "decrypt " ]
    rg -q '^theirs$' "${DIST}"
    [ "$(cat "${PLAIN}")" == "mine" ]

    local cases=(
        "${PLAIN} differs from its encrypted copy"
        "touch ${PLAIN} && make encrypt"
        "FORCE=1 make decrypt"
    ) \
        phrase

    for phrase in "${cases[@]}"; do
        has "${phrase}"
    done
}

@test "encrypt: an older copy with the same content is in sync again after one check" {
    printf 'same\n' > "${PLAIN}"
    touch -t "${OLDER}" "${PLAIN}"
    pull_dist "same"

    run secrets encrypt
    [ "${status}" -eq 0 ]
    [ "$(sops_calls)" == "decrypt " ]

    run secrets encrypt
    [ "${status}" -eq 0 ]
    [ -z "$(sops_calls)" ]
}

# --- decrypt ------------------------------------------------------------------

@test "decrypt: writes a missing copy, readable by the owner only" {
    pull_dist "theirs"

    run secrets decrypt
    [ "${status}" -eq 0 ]
    [ "$(cat "${PLAIN}")" == "theirs" ]
    [ "$(stat -c '%a' "${PLAIN}" 2>/dev/null || stat -f '%Lp' "${PLAIN}")" == "600" ]
}

@test "decrypt: keeps a copy edited after the last run, also under FORCE=1" {
    local cases=("" "1") \
        force

    pull_dist "theirs"
    printf 'mine\n' > "${PLAIN}"
    touch -t "${NEWER}" "${PLAIN}"

    for force in "${cases[@]}"; do
        FORCE="${force}" run secrets decrypt
        [ "${status}" -eq 0 ]
        has "Kept local edits in ${PLAIN}"
        [ "$(cat "${PLAIN}")" == "mine" ]
    done
}

@test "decrypt: stops on a copy that differs and is not newer, FORCE=1 replaces it" {
    printf 'mine\n' > "${PLAIN}"
    touch -t "${OLDER}" "${PLAIN}"
    pull_dist "theirs"

    run secrets decrypt
    [ "${status}" -eq 1 ]
    has "${PLAIN} differs from its encrypted copy"
    [ "$(cat "${PLAIN}")" == "mine" ]

    FORCE=1 run secrets decrypt
    [ "${status}" -eq 0 ]
    [ "$(cat "${PLAIN}")" == "theirs" ]
}

@test "decrypt: one file that needs a decision does not stop the others" {
    printf 'mine\n' > "${PLAIN}"
    touch -t "${OLDER}" "${PLAIN}"
    pull_dist "theirs"
    printf 'ENC[AES256_GCM,data:fake]\nother\n' > "private/.ssh.dist/conf.d/zz-other"

    run secrets decrypt
    [ "${status}" -eq 1 ]
    has "1 file(s) need your decision"
    [ "$(cat "private/.ssh/conf.d/zz-other")" == "other" ]
}

# --- plaintext detection ------------------------------------------------------

@test "a plaintext file that only mentions sops is not taken for encrypted" {
    local cases=("encrypt" "decrypt") \
        command

    printf 'alias s="sops"\n' > "${DIST}"
    printf 'mine\n' > "${PLAIN}"

    for command in "${cases[@]}"; do
        run secrets "${command}"
        [ "${status}" -ne 0 ]
        has "${DIST} is plaintext"
    done
}

# --- pre-commit guard (lives in the private submodule) ------------------------

@test "guard: accepts only encrypted files under *.dist/" {
    local hook="${BATS_TEST_DIRNAME}/../private/.githooks/pre-commit"

    [[ -x "${hook}" ]] || skip "private submodule is not checked out"

    # path|content|expected exit status
    local cases=(
        'x.dist/secret|ENC[AES256_GCM,data:abc]|0'
        'x.dist/secret|alias s="sops"|1'
        'x/secret|ENC[AES256_GCM,data:abc]|1'
        '.gitignore|*|0'
    ) \
        entry \
        path \
        rest \
        repo \
        index=0

    for entry in "${cases[@]}"; do
        path="${entry%%|*}"
        rest="${entry#*|}"
        repo="${BATS_TEST_TMPDIR}/guard-${index}"
        index=$((index + 1))

        git init -q "${repo}"
        mkdir -p "$(dirname "${repo}/${path}")"
        printf '%s\n' "${rest%|*}" > "${repo}/${path}"
        git -C "${repo}" add -f "${path}"

        cd "${repo}"
        run bash "${hook}"
        [ "${status}" -eq "${rest##*|}" ]
    done
}
