#!/usr/bin/env zsh

# +------------+
# | Init Cache |
# +------------+

# Tools like starship or zoxide print their shell integration on every start,
# which costs one process fork each. Cache that output and source the file.
: ${ZSH_INIT_CACHE_DIR:="${XDG_CACHE_HOME}/zsh/init"}

# Usage: source_cached <name> <command> [args...]
# Skips silently when <command> is not installed.
source_cached() {
    local name="${1}"
    shift
    local binary="${commands[${1}]}"
    [[ -n "${binary}" ]] || return 0

    local cache_file="${ZSH_INIT_CACHE_DIR}/${name}.zsh"
    local stamp_file="${cache_file}.stamp"
    local stamp="${binary:A} ${*}"

    if [[ -s "${cache_file}" && -r "${stamp_file}" && "$(<"${stamp_file}")" == "${stamp}" ]]; then
        source "${cache_file}"
        return
    fi

    # Write to a temp file first so a failing tool or a parallel shell
    # never sees a partial script.
    local temp_file="${cache_file}.${$}"
    mkdir -p "${ZSH_INIT_CACHE_DIR}"
    if ! "${@}" >| "${temp_file}" 2>/dev/null || [[ ! -s "${temp_file}" ]]; then
        rm -f "${temp_file}"
        source <("${@}")
        return
    fi

    mv -f "${temp_file}" "${cache_file}"
    print -r -- "${stamp}" >| "${stamp_file}"
    source "${cache_file}"
}

# Drop every cached init script, e.g. after changing a tool's config.
clear_init_cache() {
    rm -f "${ZSH_INIT_CACHE_DIR}"/*.zsh(N) "${ZSH_INIT_CACHE_DIR}"/*.stamp(N)
}
