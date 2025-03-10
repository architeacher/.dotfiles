#!/usr/bin/env zsh

brew_prefix="$(brew --prefix)"
export fpath=(
    "${fpath[@]}"
    "${brew_prefix}/share/zsh-completions"
    "${brew_prefix}/share/zsh/site-functions"
)

# https://gist.github.com/ctechols/ca1035271ad134841284
() {
    ! (( $+commands[brew] )) && return 0

    setopt local_options
    setopt extended_glob

    local zcomp_file="${1}"
    local zcomp_hours="${2:-24}" # how often to regenerate the file
    local lock_timeout="${3:-1}" # change this if compinit normally takes longer to run
    local lock_file="${zcomp_file}.lock"

    [ -f "${lock_file}" ] && {
        if [[ -f "${lock_file}"(#qN.mm+${lock_timeout}) ]]; then
            (
                echo "${lock_file} has been held by $(< "${lock_file}") for longer than ${lock_timeout} minute(s)."
                echo "This may indicate a problem with compinit"
            ) >&2
        fi
        # Exit if there's a lock_file; another process is handling things
        return
    } || {
        # Create the lock_file with this shell's PID for debugging
        echo "$$" > "${lock_file}"
        # Ensure the lock_file is removed
        trap "rm -f ${lock_file}" EXIT
    }

    autoload -Uz compinit

    # Based on https://carlosbecker.com/posts/speeding-up-zsh/
    # - '#q' is an explicit glob qualifier that makes globbing work within zsh's [[ ]] construct.
    # - 'N' makes the glob pattern evaluate to nothing when it doesn't match (rather than throw a globbing error)
    # - '.' matches "regular files"
    # - 'mh+24' matches files (or directories or whatever) that are older than 24 hours.
    if [[ -n "${zcomp_file}"(#qN.mh+${zcomp_hours}) ]]; then
        # The file is old and needs to be regenerated.
        compinit -d "${zcomp_file}" -i -u -C;
    else
        # The file is either new or does not exist. Either way, -C will handle it correctly
        compinit -i -u -C;
    fi

    # Disable zsh bundled function mtools command mcd
    # which causes a conflict.
    compdef -d mcd
} "${ZDOTDIR}/.zcompdump"

# Note: This should be called after the compdef is loaded, to avoid warnings.
# Load the shell .dotfiles, and then some:
# * ~/.config/zsh/scripts can be used to extend some functionalities.
for file in "${ZDOTDIR}/scripts/"{aliases,completion,exports,functions,key-bindings,options,plugins,utils}.zsh; do
    [ -r "${file}" ] && [ -f "${file}" ] && source "${file}";
done;

unset file;
