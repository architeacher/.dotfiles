#!/usr/bin/env zsh

# The following have to go in .zprofile, because they are used by
# macOS's /etc/zshrc file, which is sourced _before_ your`.zshrc`
# file.
export SHELL_SESSION_DIR="${XDG_STATE_HOME}/zsh/sessions"
export SHELL_SESSION_FILE="${SHELL_SESSION_DIR}/${TERM_SESSION_ID}"

eval "$(/opt/homebrew/bin/brew shellenv)"

# Ensure path arrays do not contain duplicates.
typeset -gU cdpath fpath mailpath path

# https://www.funtoo.org/Funtoo:Keychain
type keychain >/dev/null 2>&1 && {
    for file in ~/.ssh/{id_dsa,id_ed25519,id_rsa}; do
        [ -e ~/.ssh/"${file}" ] && {
            eval `keychain --eval --agents ssh --inherit --quiet any "${file}" >/dev/null`
        }
    done

    [ -f "${ZDOTDIR}/local/keychain.zsh" ] && source "${ZDOTDIR}/local/keychain.zsh"
}

[ -f ~/.orbstack/shell/init.zsh ] && {
    # Added by OrbStack: command-line tools and integration
    # Comment this line if you don't want it to be added again.
    source ~/.orbstack/shell/init.zsh 2>/dev/null || :
}
