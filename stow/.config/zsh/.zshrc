#!/usr/bin/env zsh

brew_prefix="${HOMEBREW_PREFIX:-$(brew --prefix)}"
export fpath=(
    "${fpath[@]}"
    "${brew_prefix}/share/zsh-completions"
    "${brew_prefix}/share/zsh/site-functions"
)

# https://gist.github.com/ctechols/ca1035271ad134841284
() {
    setopt local_options
    setopt extended_glob

    local zcomp_file="${1}"
    local zcomp_hours="${2:-24}" # how often to rescan fpath and rebuild the dump

    autoload -Uz compinit

    # Based on https://carlosbecker.com/posts/speeding-up-zsh/
    # - '#q' is an explicit glob qualifier that makes globbing work within zsh's [[ ]] construct.
    # - 'N' makes the glob pattern evaluate to nothing when it doesn't match (rather than throw a globbing error)
    # - '.' matches "regular files"
    # - 'mh+24' matches files (or directories or whatever) that are older than 24 hours.
    if [[ ! -s "${zcomp_file}" || -n "${zcomp_file}"(#qN.mh+${zcomp_hours}) ]]; then
        # The dump is missing or old: rescan fpath, then mark it fresh.
        compinit -i -u -d "${zcomp_file}"
        touch "${zcomp_file}"
    else
        # The dump is fresh: load it without looking for new functions.
        compinit -i -u -C -d "${zcomp_file}"
    fi

    # Disable zsh bundled function mtools command mcd
    # which causes a conflict.
    compdef -d mcd
} "${ZDOTDIR}/.zcompdump"

# Note: This should be called after the compdef is loaded, to avoid warnings.
# Load the shell .dotfiles, and then some:
# * ~/.config/zsh/scripts can be used to extend some functionalities.
for file in "${ZDOTDIR}/scripts/"{cache,aliases,completions,exports,functions,options,plugins,key-bindings,utils}.zsh; do
    [ -r "${file}" ] && [ -f "${file}" ] && source "${file}";
done;

unset file;
