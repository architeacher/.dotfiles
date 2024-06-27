#!/usr/bin/env bash

set -eou pipefail

main() {
    local source="https://github.com/architeacher/.dotfiles"
    local tarball="${source}/tarball/main"
    local target_dir="${HOME}/.dotfiles"
    local tar_cmd="tar -xzvf -C ${target_dir} --exclude='{.gitignore}' --overwrite --overwrite-dir --strip-components=1"

    is_executable() {
        type "${1}" >/dev/null 2>&1
    }

    if is_executable "git"; then
        cmd="git clone ${source} ${target_dir}"
    elif is_executable "curl"; then
        cmd="curl --compressed -#L -m 10 ${tarball} | ${tar_cmd}"
    elif is_executable "wget"; then
        cmd="wget --no-check-certificate -O - ${tarball} | ${tar_cmd}"
    fi

    [ -z "${cmd+x}" ] && {
        echo "No git, curl or wget available. Aborting."
        exit 1
    }

    echo "Installing .dotfiles..."
    mkdir -p "${target_dir}"

    echo "Extracting to ~/.dotfiles..."
    eval "${cmd}"
}

main
