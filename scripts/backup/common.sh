#!/usr/bin/env bash
#
# Helpers shared by the backup modules: argument checks, paths, temp dir.
# Sourced by scripts/backup.sh, not run on its own.

# --- argument checks ----------------------------------------------------------

require_tools() {
    local tool

    for tool in "$@"; do
        is_command "${tool}" || abort "Missing tool: ${tool}"
    done
}

require_value() {
    local name="${1}" \
          value="${2:-}"

    [[ -n "${value}" ]] || abort "${name} is required."
}

require_file() {
    local name="${1}" \
          path="${2:-}"

    [[ -f "${path}" ]] || abort "${name} must be an existing file: ${path:-<empty>}"
}

require_backup() {
    local path="${1}"

    [[ -f "${path}" ]] || abort "Backup not found: ${path}. Set BACKUP_DIR to the backup folder."
}

# Every command refuses to overwrite what it writes, unless stated otherwise.
require_absent() {
    local path

    for path in "$@"; do
        [[ ! -e "${path}" ]] || abort "Already exists: ${path}"
    done
}

ensure_parent_dir() {
    mkdir -p "$(dirname "${1}")"
}

# Prints the permission string, e.g. -rw-------.
# GNU/busybox stat first: on GNU, -f means filesystem status and would print noise.
mode_of() {
    stat -c '%A' "${1}" 2>/dev/null || stat -f '%Sp' "${1}"
}

# --- temp dir -----------------------------------------------------------------
# Outputs are staged in temp_dir and moved into place at the end.
# A failed or aborted run leaves no files behind, so you can just rerun it.

ensure_temp_dir() {
    [[ -n "${temp_dir}" ]] && return 0

    temp_dir="$(mktemp -d /tmp/keys.XXXXXX)"
}

remove_temp_dir() {
    [[ -z "${temp_dir}" ]] && return 0

    # gpg-test-restore starts an agent for its throwaway keyring.
    [[ -d "${temp_dir}/home" ]] && { gpgconf --homedir "${temp_dir}/home" --kill all >/dev/null 2>&1 || true; }

    rm -rf "${temp_dir}"
}

# --- backup paths -------------------------------------------------------------

# Fills BACKUP_DIR (if unset) and the file prefixes derived from it.
set_paths() {
    local default_dir="${1}"

    BACKUP_DIR="${BACKUP_DIR:-${default_dir}}"
    GPG_OUT="${GPG_OUT:-${BACKUP_DIR}/gpg-key}"
    AGE_OUT="${AGE_OUT:-${BACKUP_DIR}/age-key}"
    SSH_OUT="${SSH_OUT:-${BACKUP_DIR}/$(basename "${SSH_KEY}")}"
    PACK_OUT="${PACK_OUT:-${BACKUP_DIR}${PACK_EXT}}"
}

# Prints BACKUP_ROOT/<newest YYYYMMDD>, counting folders and packed archives.
latest_backup() {
    local entry \
          name \
          best=""

    # Globs expand sorted and YYYYMMDD sorts as a date, so the last match wins.
    for entry in "${BACKUP_ROOT}"/[0-9]*; do
        [[ -e "${entry}" ]] || continue

        name="$(basename "${entry}")"
        name="${name%"${PACK_EXT}"}"
        [[ "${name}" =~ ^[0-9]{8}$ ]] || continue

        best="${name}"
    done

    [[ -n "${best}" ]] || abort "No backups in ${BACKUP_ROOT}. Set BACKUP_DIR."

    printf '%s\n' "${BACKUP_ROOT}/${best}"
}

# Commands that read a backup default to the latest one, the others to today's.
resolve_backup_dir() {
    local command="${1}"

    case "${command}" in
        *restore | unpack | run)
            if [[ -z "${BACKUP_DIR}" ]]; then
                BACKUP_DIR="$(latest_backup)"
                log_notice "Using backup: ${BACKUP_DIR}"
            fi
        ;;
    esac

    set_paths "${BACKUP_ROOT}/${DATE}"
}
