#!/usr/bin/env bash
#
# Backs up, restores and checks the keys sops needs: gpg, age, YubiKey and ssh.
#
# The work is split by key type under scripts/backup/:
#   common.sh   argument checks, backup paths, temp dir
#   gpg.sh      gpg-*            age.sh      age-*
#   yubikey.sh  age-yubikey-*    ssh.sh      ssh-*
#   verify.sh   verify           pack.sh     pack, unpack, run, summary
#
# cmd_* run through dynamic dispatch and at_exit through a trap, which ShellCheck cannot follow.
# shellcheck disable=SC2317,SC2329

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# `run` starts each command as a new process of this script.
BACKUP_SCRIPT="${SCRIPT_DIR}/backup.sh"

. "${SCRIPT_DIR}/common.sh"
. "${SCRIPT_DIR}/backup/common.sh"
. "${SCRIPT_DIR}/backup/gpg.sh"
. "${SCRIPT_DIR}/backup/age.sh"
. "${SCRIPT_DIR}/backup/yubikey.sh"
. "${SCRIPT_DIR}/backup/ssh.sh"
. "${SCRIPT_DIR}/backup/verify.sh"
. "${SCRIPT_DIR}/backup/pack.sh"

PACK_EXT=".tar.gz.age"
# Prefix of ssh backups made before files were named after SSH_KEY.
SSH_LEGACY="ssh-key"
YK_PROBE="yubikey-probe"

# Settings. Override any of them from the environment, e.g. BACKUP_DIR=/Volumes/usb/bk.
# BACKUP_DATE is pinned once per multi-step run (the Makefile does), so a run
# crossing midnight still writes into a single folder.
DATE="${BACKUP_DATE:-$(date +%Y%m%d)}"
BACKUP_ROOT="${BACKUP_ROOT:-${HOME}/backup}"
# Defaults to BACKUP_ROOT/DATE when writing and to the latest backup when reading.
BACKUP_DIR="${BACKUP_DIR:-}"
AGE_KEY="${AGE_KEY:-${SOPS_AGE_KEY_FILE:-${HOME}/.config/sops/age/keys.txt}}"
SSH_KEY="${SSH_KEY:-${SOPS_AGE_SSH_PRIVATE_KEY_FILE:-${HOME}/.ssh/id_ed25519_sops}}"
SERIAL="${SERIAL:-}"
SLOT="${SLOT:-}"
# ssh-restore refuses keys that are not recipients here, unless FORCE=1.
SOPS_CONFIG="${SOPS_CONFIG:-$(dirname "${SCRIPT_DIR}")/.sops.yaml}"
FORCE="${FORCE:-}"

temp_dir=""
PRIMARY=""
failures=0

cmd_latest() {
    latest_backup
}

cmd_help() {
    cat <<HELP
$(basename "${0}"): back up, restore and check the gpg, age, YubiKey and ssh keys
Usage: $(basename "${0}") [-l] log level [-h] help [-x] verbose mode <command> [args]

Backup              gpg-backup KEY | age-backup | age-yubikey-backup | ssh-backup
Test restore        gpg-test-restore [BAK] [FPR] | age-test-restore [BAK] [PUB]
                    age-yubikey-test-restore [BAK] [PUB] | ssh-test-restore [BAK] [PUB]
Restore             gpg-restore [BAK] [FPR] | age-restore [BAK] [DEST] [PUB]
                    ssh-restore [BAK] [DEST] [PUB]
Archive             pack | unpack [PACK] [DEST_DIR]
Other               gpg-fingerprint KEY | verify | summary | latest | run COMMAND...

    -l sets the log priority: 2 => critical, 3 => error, 6 => info, 7 => debug.
    -h to get help about the usage.
    -x to see the executed statements.

Restore, test-restore, unpack and run read the latest backup under BACKUP_ROOT
unless BACKUP_DIR is set. Backups are written to BACKUP_ROOT/DATE.
BAK defaults to the matching *_OUT file (.tar.gpg or .age), DEST to AGE_KEY or SSH_KEY.
age-restore refuses to overwrite an existing DEST. ssh-restore moves an existing
DEST of another key aside (DEST.replaced-STAMP). test-restore never touches DEST.

Settings (current values, *_OUT are file prefixes):
  BACKUP_ROOT=${BACKUP_ROOT}
  BACKUP_DATE=${DATE}
  BACKUP_DIR=${BACKUP_DIR}
  GPG_OUT=${GPG_OUT}
  AGE_OUT=${AGE_OUT}
  SSH_OUT=${SSH_OUT}
  PACK_OUT=${PACK_OUT}
  AGE_KEY=${AGE_KEY}
  SSH_KEY=${SSH_KEY}
  SERIAL=${SERIAL:-<unset>}
  SLOT=${SLOT:-<unset>}
  SOPS_CONFIG=${SOPS_CONFIG}
  FORCE=${FORCE:-<unset>}
HELP
}

parse_args() {
    : "${LOG_LEVEL:=${_log_level}}"

    local arg
    while getopts "l:hx" arg; do
        case "${arg}" in
            l) LOG_LEVEL="${OPTARG}" ;;
            h) COMMAND="help" ;;
            x) set -x ;;
            *) COMMAND="help" ;;
        esac
    done

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

    umask 077
}

main() {
    local handler

    COMMAND=""
    prepare "$@"
    shift "$((OPTIND - 1))"

    COMMAND="${COMMAND:-${1:-help}}"
    [[ "$#" -gt 0 ]] && shift

    # Every command is a cmd_* function, e.g. ssh-test-restore -> cmd_ssh_test_restore.
    handler="cmd_${COMMAND//-/_}"
    declare -F "${handler}" >/dev/null || abort "Unknown command: ${COMMAND}. See: $(basename "${0}") help"

    resolve_backup_dir "${COMMAND}"
    "${handler}" "$@"
}

is_bash_sourced || main "$@"
