#!/usr/bin/env zsh

# https://github.com/junegunn/fzf
# FZF - Set up key bindings and fuzzy completion
# shellcheck disable=SC1090
# shellcheck disable=SC2154
(( $+commands[fzf] )) && source <(fzf --zsh)

# Direnv
command -v direnv > /dev/null 2>&1 && source <(direnv hook zsh)

# Kubectl
# shellcheck disable=SC1090
hash kubectl > /dev/null 2>&1 && source <(kubectl completion zsh)

# Starship
# shellcheck disable=SC1090
type -p starship > /dev/null 2>&1 && source <(starship init zsh)

# Zoxide
# shellcheck disable=SC1090
which zoxide > /dev/null 2>&1 && source <(zoxide init --cmd cd zsh)
