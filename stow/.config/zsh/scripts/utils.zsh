#!/usr/bin/env zsh

# +-------+
# | Atuin |
# +-------+

# shellcheck disable=SC1090
# shellcheck disable=SC2154
(( $+commands[atuin] )) && source <(atuin init zsh)

# +----------+
# | Carapace |
# +----------+

command -v carapace > /dev/null 2>&1 && {
    source <(carapace _carapace)
}

# +--------+
# | Direnv |
# +--------+

# shellcheck disable=SC1090
hash direnv > /dev/null 2>&1 && source <(direnv hook zsh)

# +-----+
# | FZF |
# +-----+

# https://github.com/junegunn/fzf
# FZF - Set up key bindings and fuzzy completion
# shellcheck disable=SC1090
type -p fzf > /dev/null 2>&1 && source <(fzf --zsh)

# +---------+
# | Kubectl |
# +---------+

# shellcheck disable=SC1090
whereis kubectl | rg -q '/' 2>&1 && source <(kubectl completion zsh)

# +--------+
# | Orbctl |
# +--------+

which orbctl > /dev/null 2>&1 && {
    source <(orbctl completion zsh)
    compdef _orb orbctl
    compdef _orb orb
}

# +----------+
# | Starship |
# +----------+

# shellcheck disable=SC1090
which starship > /dev/null 2>&1 && source <(starship init zsh)

# +--------+
# | Zoxide |
# +--------+

# shellcheck disable=SC1090
which zoxide > /dev/null 2>&1 && source <(zoxide init --cmd cd zsh)
