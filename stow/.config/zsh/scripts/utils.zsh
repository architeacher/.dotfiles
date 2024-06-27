#!/usr/bin/env zsh

# atuin
(( $+commands[atuin] )) && source <(atuin init zsh)

# Direnv
command -v direnv > /dev/null 2>&1 && source <(direnv hook zsh)

# https://github.com/junegunn/fzf
# FZF - Set up key bindings and fuzzy completion
# shellcheck disable=SC1090
# shellcheck disable=SC2154
hash fzf > /dev/null 2>&1 && source <(fzf --zsh)

# Kubectl
# shellcheck disable=SC1090
type -p kubectl > /dev/null 2>&1 && source <(kubectl completion zsh)

# orbctl
whereis orbctl | rg -q '/' 2>&1 && {
    source <(orbctl completion zsh)
    compdef _orb orbctl
    compdef _orb orb
}

# Starship
# shellcheck disable=SC1090
which starship > /dev/null 2>&1 && source <(starship init zsh)

# Zoxide
# shellcheck disable=SC1090
which zoxide > /dev/null 2>&1 && source <(zoxide init --cmd cd zsh)
