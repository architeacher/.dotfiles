#!/usr/bin/env zsh

# Each init script is cached by source_cached (see cache.zsh) and rebuilt
# only when the tool binary changes. Run `clear_init_cache` to force it.

# +-------+
# | Atuin |
# +-------+

source_cached atuin atuin init zsh

# +----------+
# | Carapace |
# +----------+

source_cached carapace carapace _carapace

# +--------+
# | Direnv |
# +--------+

source_cached direnv direnv hook zsh

# +-----+
# | FZF |
# +-----+

# https://github.com/junegunn/fzf
# FZF - Set up key bindings and fuzzy completion
source_cached fzf fzf --zsh

# +---------+
# | Kubectl |
# +---------+

source_cached kubectl kubectl completion zsh

# +----------+
# | Starship |
# +----------+

source_cached starship starship init zsh --print-full-init

# +--------+
# | Zoxide |
# +--------+

source_cached zoxide zoxide init --cmd cd zsh
