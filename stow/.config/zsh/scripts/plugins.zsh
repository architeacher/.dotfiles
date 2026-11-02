#!/usr/bin/env zsh

brew_prefix="${HOMEBREW_PREFIX:-$(brew --prefix)}"

plugins=(
    "${brew_prefix}/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
    "${brew_prefix}/share/zsh-fast-syntax-highlighting/fast-syntax-highlighting.plugin.zsh"
    # History substring search should come after the syntax highlighting.
    "${brew_prefix}/share/zsh-history-substring-search/zsh-history-substring-search.zsh"
    "${ZDOTDIR}/fzf/fzf.zsh"
    "${ZDOTDIR}/fzf/fzf-git.zsh"
)

for plugin_path in "${plugins[@]}"; do
    # shellcheck disable=SC1090
    [[ -r "${plugin_path}" ]] && source "${plugin_path}" 2>&1;
done
