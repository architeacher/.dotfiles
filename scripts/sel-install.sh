#!/usr/bin/env bash

set -Eeuo pipefail

# Interactively select and run a function from any scattered install.sh file.
#
# Usage:
#   scripts/sel-install.sh
#
# Layout assumed:
#   scripts/install.sh          <- root caller, defines shared helper functions + main
#   scripts/common.sh           <- shared helpers, pulled in by scripts/install.sh
#   <name>/scripts/install.sh   <- nested installer, labeled "<name>" in the picker
#
# Loading model:
#   Installers are staged into TMP_DIR with their trailing `main "$@"` removed and
#   their sibling-relative sources rewritten to absolute paths. Nothing is written
#   inside the repository, and no installer needs to know it is being sourced
#   rather than executed.

readonly ROOT_INSTALL="scripts/install.sh"
readonly MAIN_CALL_PATTERN='^\s*main\s+"\$@"\s*$'
readonly FN_DEF_PATTERN='^\s*(?:function\s+)?\K\w+(?=\s*\(\s*\)\s*\{)'
readonly SIBLING_DIR_PATTERN='\$(dirname "\${BASH_SOURCE\[0\]}")'

TMP_DIR="$(mktemp -d)"
readonly TMP_DIR

trap 'rm -rf "${TMP_DIR}"' EXIT

find_install_scripts() {
    local pattern='.*/scripts/install\.sh$'

    fd -t f -p -H -I -0 --strip-cwd-prefix "${pattern}"
}

# Collapses "./x" and symlinks so two spellings of the same file compare equal.
resolve_path() {
    local file="${1}" \
          dir

    dir="$(cd "$(dirname "${file}")" && pwd -P)"

    echo "${dir}/$(basename "${file}")"
}

# Prints "<label>:<function>:<file>" for every non-main function in a file.
label_for() {
    local file="${1}" \
          scripts_dir \
          parent_dir

    scripts_dir="$(dirname "${file}")"
    parent_dir="$(dirname "${scripts_dir}")"

    [[ "${parent_dir}" == "." ]] && { echo "main"; return 0; }

    basename "${parent_dir}"
}

list_functions() {
    local file="${1}" \
          label \
          fn

    label="$(label_for "${file}")"

    rg -oP "${FN_DEF_PATTERN}" "${file}" | while IFS= read -r fn; do
        [[ "${fn}" == "main" ]] && continue
        echo "${label}:${fn}:${file}"
    done
}

collect_all_functions() {
    local file

    while IFS= read -r -d '' file; do
        list_functions "${file}"
    done < <(find_install_scripts)
}

# Prints the body of a single shell function from a file (used as the
# fzf --preview command). Exported so fzf's preview subshell can call it.
show_function_body() {
    local fn="${1}" \
          file="${2}" \
          body

    body="$(awk -v fn="${fn}" '
        $0 ~ "^[[:space:]]*(function[[:space:]]+)?" fn "[[:space:]]*\\([[:space:]]*\\)[[:space:]]*\\{" { in_fn = 1 }
        in_fn { print }
        in_fn && /^}/ { exit }
    ' "${file}")"

    if command -v bat > /dev/null; then
        echo "${body}" | bat \
                    --language bash \
                    --color always \
                    --style plain \
                    --paging never \
                    --terminal-width "${FZF_PREVIEW_COLUMNS:-80}"

        return
    fi

    echo "${body}"
}

export -f show_function_body

pick_function() {
    local candidates="${1}"

    echo "${candidates}" | SHELL="$(command -v bash)" fzf \
        --prompt "Select a function: " \
        --delimiter ':' \
        --with-nth 1,2 \
        --preview 'show_function_body {2} {3}'
}

# Strips the trailing `main "$@"` self-exec call so a file can be sourced
# without immediately re-running its own main.
strip_main_call() {
    local file="${1}"
    grep -Ev "${MAIN_CALL_PATTERN}" "${file}"
}

# Rewrites the sibling-resolution idiom to an absolute path, so a staged copy can
# live outside the repo without losing track of scripts/common.sh.
rewrite_sibling_paths() {
    local origin_dir="${1}" \
          escaped

    # Escape sed replacement metacharacters (\, &) and our chosen delimiter (|),
    # in that order, so origin_dir is treated as a literal string regardless
    # of what characters it contains.
    escaped="${origin_dir//\\/\\\\}"
    escaped="${escaped//&/\\&}"
    escaped="${escaped//|/\\|}"

    sed "s|${SIBLING_DIR_PATTERN}|${escaped}|g"
}

# Copies an installer into TMP_DIR with its self-exec call removed and its
# sibling sources absolutised. Prints the staged path.
stage_installer() {
    local file="${1}" \
          origin_dir \
          dest

    origin_dir="$(cd "$(dirname "${file}")" && pwd -P)"
    dest="$(mktemp "${TMP_DIR}/install-XXXXXX")"

    strip_main_call "${file}" | rewrite_sibling_paths "${origin_dir}" > "${dest}"

    echo "${dest}"
}

source_installer() {
    local staged

    staged="$(stage_installer "${1}")"

    # shellcheck disable=SC1090
    source "${staged}"
}

load_shared_context() {
    local picked_file="${1}"

    [[ -f "${ROOT_INSTALL}" ]] || return 0
    [[ "$(resolve_path "${picked_file}")" != "$(resolve_path "${ROOT_INSTALL}")" ]] || return 0

    source_installer "${ROOT_INSTALL}"
}

parse_selection() {
    local selection="${1}" \
          file \
          rest \
          fn

    file="${selection##*:}"
    rest="${selection%:*}"
    fn="${rest##*:}"

    printf '%s\n%s\n' "${fn}" "${file}"
}

# Populates the global SELECTED_ARGS array from user input, respecting
# shell-style quoting so "foo bar" is captured as a single argument.
prompt_for_args() {
    local fn="${1}" \
          raw

    read -rp "Args for '${fn}' (leave blank for none): " raw
    eval "SELECTED_ARGS=(${raw})"
}


run_selected_function() {
    local fn="${1}" \
          file="${2}"

    load_shared_context "${file}"
    source_installer "${file}"

    declare -F "include_env_vars" > /dev/null && include_env_vars
    declare -F "declare_global_vars" > /dev/null && declare_global_vars

    [[ ${#SELECTED_ARGS[@]} -gt 0 ]] && {
        "${fn}" "${SELECTED_ARGS[@]}"

        return
    }

    "${fn}"
}

main() {
    local candidates \
          selection \
          fn \
          file

    declare -a SELECTED_ARGS=()

    candidates="$(collect_all_functions)"
    [[ -n "${candidates}" ]] || { log_error "No functions found" >&2; return 1; }

    selection="$(pick_function "${candidates}")"
    [[ -n "${selection}" ]] || { log_error "No function selected" >&2; return 1; }

    read -r fn file <<< "$(parse_selection "${selection}" | tr '\n' ' ')"
    prompt_for_args "${fn}"

    run_selected_function "${fn}" "${file}"
}

main "$@"
