#!/usr/bin/env zsh

#
# Executes commands at login post-zshrc.
#
# Authors:
#   Sorin Ionescu <sorin.ionescu@gmail.com>
#

# Execute code that does not affect the current session in the background.
{
    # Compile the completion dump to increase startup speed.
    zcompdump="${ZDOTDIR}/.zcompdump"
    if [[ -s "${zcompdump}" && (! -s "${zcompdump}.zwc" || "${zcompdump}" -nt "${zcompdump}.zwc") ]]; then
        zcompile "${zcompdump}"
    fi
} &!

# Execute code only if STDERR is bound to a TTY.
[[ -o INTERACTIVE && -t 2 ]] && {
    # Print a random, hopefully interesting, adage.
    if (( $+commands[fortune] )) && command -v cowsay >/dev/null 2>&1 && hash lolcat >/dev/null 2>&1; then
        fortune -s computers | cowsay -f "$(cowsay -l | sed '1d' | tr ' ' '\n' | shuf -n 1)" -nW80 | lolcat -a -d 1
    else which neofetch >/dev/null 2>&1
        neofetch
    fi
} >&2
