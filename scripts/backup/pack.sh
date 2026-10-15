#!/usr/bin/env bash
#
# pack: one passphrase-protected file for the whole backup folder (tar, gzip, age -p).
# The files inside are already encrypted, so gzip saves almost nothing.
# What you gain: one file to copy, and the file names are hidden.
# Sourced by scripts/backup.sh, not run on its own.
# cmd_* run through backup.sh's dynamic dispatch, which ShellCheck cannot follow.
# shellcheck disable=SC2317,SC2329

# Prints the entry names without the top dir, sorted. Asks for the passphrase.
pack_entries() {
    age -d "${1}" | tar -tzf - | sed -e 's#^[^/]*/##' -e '/^$/d' | sort
}

# Prints the names directly inside DIR, sorted.
list_entries() {
    find "${1}" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort
}

# Extracts an archive into DIR and prints its single top-level folder name.
extract_pack() {
    local pack="${1}" \
          dir="${2}" \
          entries

    mkdir -p "${dir}"
    age -d "${pack}" | tar -C "${dir}" -xzf -

    entries=("${dir}"/*)
    [[ "${#entries[@]}" -eq 1 && -d "${entries[0]}" ]] || abort "Unexpected archive layout in ${pack}"

    basename "${entries[0]}"
}

cmd_pack() {
    local src="${BACKUP_DIR}" \
          out="${PACK_OUT}"

    [[ -d "${src}" ]] || abort "No backup dir: ${src}"
    require_tools age tar
    require_absent "${out}"
    ensure_parent_dir "${out}"

    ensure_temp_dir
    COPYFILE_DISABLE=1 tar -C "$(dirname "${src}")" -czf - "$(basename "${src}")" \
        | age -p -o "${temp_dir}/pack.age"

    log_notice "Verifying, enter the passphrase again."
    [[ "$(pack_entries "${temp_dir}/pack.age")" == "$(list_entries "${src}")" ]] \
        || abort "The archive contents differ from ${src}"

    mv "${temp_dir}/pack.age" "${out}"

    log_info "Packed: ${out}"
    ls -l "${out}"
}

# Extracts next to the packed folder by default. Refuses to overwrite.
cmd_unpack() {
    local pack="${1:-${PACK_OUT}}" \
          dest="${2:-$(dirname "${BACKUP_DIR}")}" \
          top

    require_file PACK "${pack}"
    require_tools age tar

    ensure_temp_dir
    top="$(extract_pack "${pack}" "${temp_dir}/x")"

    require_absent "${dest}/${top}"
    mkdir -p "${dest}"
    mv "${temp_dir}/x/${top}" "${dest}/${top}"

    # In the docker test the files would stay root-owned on a Linux host.
    [[ -n "${HOST_UID:-}" ]] && { chown -R "${HOST_UID}:${HOST_GID:-${HOST_UID}}" "${dest}/${top}" 2>/dev/null || true; }

    log_info "Unpacked to ${dest}/${top}"
    ls -l "${dest}/${top}"
}

# Runs the given commands in order, each in its own process.
# If BACKUP_DIR is missing but its archive exists, it is unpacked once into the
# temp dir, so the archive passphrase is asked once. The temp dir is deleted on
# exit, even when a command fails.
cmd_run() {
    local command \
          top

    [[ "$#" -gt 0 ]] || abort "run needs at least one command."

    if [[ ! -d "${BACKUP_DIR}" && -f "${PACK_OUT}" ]]; then
        require_tools age tar
        ensure_temp_dir

        log_info "Unpacking ${PACK_OUT}"
        top="$(extract_pack "${PACK_OUT}" "${temp_dir}/x")"
        BACKUP_DIR="${temp_dir}/x/${top}"
    fi

    # Children must not re-resolve "latest" on their own.
    export BACKUP_DIR

    for command in "$@"; do
        bash "${BACKUP_SCRIPT}" -l "${LOG_LEVEL}" "${command}" || abort "${command} failed."
    done
}

cmd_summary() {
    [[ -d "${BACKUP_DIR}" ]] || abort "No backup dir: ${BACKUP_DIR}"

    log_info "Backup dir: ${BACKUP_DIR}"
    ls -l "${BACKUP_DIR}"
    [[ -f "${PACK_OUT}" ]] && ls -l "${PACK_OUT}"

    log_notice "Next: copy the archive (or the folder) to 2 offline media, then run test-restore."
}
