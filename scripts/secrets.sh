#!/usr/bin/env bash
#
# Encrypts and decrypts the secrets in private/ with sops.
#
#   private/.ssh.dist/conf.d/work   encrypted, committed
#   private/.ssh/conf.d/work        decrypted, git-ignored, what ssh and the stow symlinks read
#
# Every top-level dir ending in .dist holds the encrypted files.
# The same path without .dist holds the decrypted copies.
#
# at_exit runs through a trap, which ShellCheck cannot follow.
# shellcheck disable=SC2317,SC2329

set -Eeuo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRIVATE_DIR="private"
DIST_SUFFIX=".dist"
HOOKS_DIR=".githooks"
# Starts every value sops encrypts. A plaintext file that only mentions sops does not match.
SOPS_MARKER='ENC\[AES256_GCM'

temp_dir=""
conflicts=0

# Prints the decrypted path of an encrypted file.
#   private/.ssh.dist/conf.d/work -> private/.ssh/conf.d/work
plain_path_of() {
    local relative="${1#"${PRIVATE_DIR}/"}" \
          top \
          rest

    top="${relative%%/*}"
    rest="${relative#*/}"

    printf '%s/%s/%s\n' "${PRIVATE_DIR}" "${top%"${DIST_SUFFIX}"}" "${rest}"
}

# Prints the encrypted path of a decrypted file.
#   private/.ssh/conf.d/work -> private/.ssh.dist/conf.d/work
dist_path_of() {
    local relative="${1#"${PRIVATE_DIR}/"}" \
          top \
          rest

    top="${relative%%/*}"
    rest="${relative#*/}"

    printf '%s/%s%s/%s\n' "${PRIVATE_DIR}" "${top}" "${DIST_SUFFIX}" "${rest}"
}

# Prints the sops file type: aws files are ini, everything else is opaque.
sops_type_of() {
    case "${1}" in
        */aws/*) printf 'ini\n' ;;
        *) printf 'binary\n' ;;
    esac
}

is_encrypted() {
    rg -q "${SOPS_MARKER}" "${1}"
}

# Both copies get the same mtime at the end of every run. After that a decrypted copy is
#   newer  edited since
#   same   in sync
#   older  left behind: a pull, checkout or reset rewrote the encrypted file

# The copies differ and the decrypted one is not the newer, so only you know which is right.
# The run goes on with the other files and fails at the end.
report_conflict() {
    local plain="${1}"

    conflicts=$((conflicts + 1))

    log_error "${plain} differs from its encrypted copy and is not newer (that file changed after the last run)."
    log_error "  Keep yours: ${LOG_CODE}touch ${plain} && make encrypt${LOG_CODE}"
    log_error "  Take the encrypted one: ${LOG_CODE}FORCE=1 make decrypt${LOG_CODE}"
}

fail_on_conflicts() {
    [[ "${conflicts}" -eq 0 ]] || abort "${conflicts} file(s) need your decision, see above."
}

# True when decrypt must leave the decrypted copy alone.
keeps_plain_file() {
    local plain="${1}" \
          dist="${2}" \
          opened="${3}"

    [[ -f "${plain}" ]] || return 1
    cmp -s "${plain}" "${opened}" && return 1

    [[ "${plain}" -nt "${dist}" ]] && {
        log_warning "Kept local edits in ${plain}, run encrypt first."

        return 0
    }

    [[ "${FORCE}" == "1" ]] && {
        log_warning "FORCE=1, replacing ${plain} with its encrypted copy."

        return 1
    }

    report_conflict "${plain}"
}

ensure_temp_dir() {
    [[ -n "${temp_dir}" ]] && return 0

    temp_dir="$(mktemp -d /tmp/secrets.XXXXXX)"
}

remove_temp_dir() {
    [[ -z "${temp_dir}" ]] && return 0

    rm -rf "${temp_dir}"
}

# Lists the files under every *.dist dir, or under their decrypted twins.
list_files() {
    local kind="${1}" \
          dist_dir \
          dir

    # A plain * skips dot dirs such as .ssh.dist, so they are matched explicitly.
    for dist_dir in "${PRIVATE_DIR}"/*"${DIST_SUFFIX}" "${PRIVATE_DIR}"/.*"${DIST_SUFFIX}"; do
        [[ -d "${dist_dir}" ]] || continue

        dir="${dist_dir}"
        [[ "${kind}" == "plain" ]] && dir="${dist_dir%"${DIST_SUFFIX}"}"
        [[ -d "${dir}" ]] || continue

        fd -H -I -t f -E .DS_Store . "${dir}"
    done
}

# Moves a decrypted file into place, readable by you only.
install_plain_file() {
    local source="${1}" \
          plain="${2}" \
          dist="${3}"

    mkdir -p "$(dirname "${plain}")"
    mv "${source}" "${plain}"
    chmod 600 "${plain}"
    touch -r "${dist}" "${plain}"
}

# Decrypts an encrypted file into ${temp_dir}/opened.
open_dist() {
    local dist="${1}" \
          type="${2}"

    ensure_temp_dir

    sops decrypt \
         --input-type "${type}" \
         --output-type "${type}" \
         "${dist}" > "${temp_dir}/opened" || abort "sops failed to decrypt ${dist}."
}

# A decrypted copy older than its encrypted file needs a look inside: the same content is
# back in sync, other content is a conflict. Only this case makes encrypt decrypt.
check_stale_copy() {
    local plain="${1}" \
          dist="${2}" \
          type="${3}"

    [[ "${DRY_RUN}" == "true" ]] && { log_notice "DRY RUN: would compare ${plain} with ${dist}"; return 0; }

    open_dist "${dist}" "${type}"

    cmp -s "${plain}" "${temp_dir}/opened" || {
        report_conflict "${plain}"

        return 0
    }

    touch -r "${dist}" "${plain}"

    log_debug "Unchanged: ${plain}"
}

encrypt_file() {
    local plain="${1}" \
          dist \
          type

    dist="$(dist_path_of "${plain}")"
    type="$(sops_type_of "${plain}")"

    [[ -f "${dist}" ]] && {
        is_encrypted "${dist}" || abort "${dist} is plaintext, move it to ${plain}."

        [[ "${plain}" -ot "${dist}" ]] && {
            check_stale_copy "${plain}" "${dist}" "${type}"

            return 0
        }

        [[ "${plain}" -nt "${dist}" ]] || {
            log_debug "Unchanged: ${plain}"

            return 0
        }
    }

    [[ "${DRY_RUN}" == "true" ]] && { log_notice "DRY RUN: would encrypt ${plain} -> ${dist}"; return 0; }

    ensure_temp_dir

    # .sops.yaml picks the creation rule by path, so it must see the .dist path.
    sops encrypt \
         --filename-override "${dist}" \
         --input-type "${type}" \
         --output-type "${type}" \
         "${plain}" > "${temp_dir}/sealed" || abort "sops failed to encrypt ${plain}."

    mkdir -p "$(dirname "${dist}")"
    mv "${temp_dir}/sealed" "${dist}"
    touch -r "${dist}" "${plain}"

    log_info "Encrypted: ${plain} -> ${dist}"
}

decrypt_file() {
    local dist="${1}" \
          plain \
          type

    plain="$(plain_path_of "${dist}")"
    type="$(sops_type_of "${dist}")"

    is_encrypted "${dist}" || abort "${dist} is plaintext, move it to ${plain} and run encrypt."

    [[ "${DRY_RUN}" == "true" ]] && { log_notice "DRY RUN: would decrypt ${dist} -> ${plain}"; return 0; }

    open_dist "${dist}" "${type}"

    keeps_plain_file "${plain}" "${dist}" "${temp_dir}/opened" && return 0

    install_plain_file "${temp_dir}/opened" "${plain}" "${dist}"

    log_info "Decrypted: ${dist} -> ${plain}"
}

encrypt_all() {
    local file

    log_info "Encrypting files under ${PRIVATE_DIR}/."

    while IFS= read -r file; do
        encrypt_file "${file}"
    done < <(list_files plain)

    fail_on_conflicts
}

decrypt_all() {
    local file

    log_info "Decrypting files under ${PRIVATE_DIR}/."

    while IFS= read -r file; do
        decrypt_file "${file}"
    done < <(list_files dist)

    fail_on_conflicts
}

# Turns on the pre-commit guard that refuses plaintext secrets.
enable_hooks() {
    local hook="${PRIVATE_DIR}/${HOOKS_DIR}/pre-commit"

    [[ -x "${hook}" ]] || abort "Missing or not executable: ${hook}"

    [[ "${DRY_RUN}" == "true" ]] && { log_notice "DRY RUN: would set core.hooksPath in ${PRIVATE_DIR}"; return 0; }

    git -C "${PRIVATE_DIR}" config core.hooksPath "${HOOKS_DIR}"

    log_info "Pre-commit guard enabled in ${PRIVATE_DIR}."
}

check_tools() {
    local tool

    for tool in sops fd rg; do
        is_command "${tool}" || abort "Missing tool: ${tool}"
    done
}

usage() {
    local this="${1}"

    cat <<HELP
${this}: encrypt and decrypt the secrets in ${PRIVATE_DIR}/ with sops
Usage: ${this} [-l] log level [-n] dry run [-h] help [-x] verbose mode <encrypt|decrypt|hooks>
    encrypt  ${PRIVATE_DIR}/X/... -> ${PRIVATE_DIR}/X${DIST_SUFFIX}/... (unchanged files are skipped)
    decrypt  ${PRIVATE_DIR}/X${DIST_SUFFIX}/... -> ${PRIVATE_DIR}/X/... (local edits are kept)
    hooks    enable the pre-commit guard in ${PRIVATE_DIR}/
    A copy that differs from its encrypted file and is not newer stops both: FORCE=1 decrypt replaces it.
    -l sets the log priority: 2 => critical, 3 => error, 6 => info, 7 => debug.
    -n dry run, prints actions without running them.
    -h to get help about the usage.
    -x to see the executed statements.
HELP

    exit 0
}

parse_args() {
    : "${LOG_LEVEL:=${_log_level}}"
    : "${DRY_RUN:=false}"
    : "${FORCE:=}"

    local arg
    while getopts "l:nh?x" arg; do
        case "${arg}" in
            l) LOG_LEVEL="${OPTARG}" ;;
            n) DRY_RUN="true" ;;
            h | \?) usage "${0}" ;;
            x) set -x ;;
        esac
    done
    shift $((OPTIND - 1))

    COMMAND="${1:-}"

    log_set_level "$((LOG_LEVEL))"
}

at_exit() {
    local signal="${1}" \
          ret="${2}"

    remove_temp_dir

    [[ "${signal}" == "EXIT" ]] || {
        log_critical "Interrupted (${signal})."

        exit 1
    }

    exit "${ret}"
}

prepare() {
    # @see: scripts/common.sh
    validate_bash
    trap_with_arg at_exit EXIT INT QUIT TERM

    parse_args "$@"
    check_tools

    umask 077
    cd "${ROOT_DIR}"
}

main() {
    prepare "$@"

    case "${COMMAND}" in
        encrypt) encrypt_all ;;
        decrypt) decrypt_all ;;
        hooks) enable_hooks ;;
        *) usage "${0}" ;;
    esac
}

is_bash_sourced || main "$@"
