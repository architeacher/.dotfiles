#!/usr/bin/env zsh

show_file_or_dir_preview="if [ -d {} ]; then eza --tree --color=always {} | head -200; else bat -n --color=always --line-range :500 {}; fi"

# Use fd (https://github.com/sharkdp/fd) for listing path candidates.
# - The first argument to the function ($1) is the base path to start traversal
# - See the source code (completion.{bash,zsh}) for the details.
_fzf_compgen_path() {
    fd --hidden --no-ignore-vcs --exclude .git . "${1}"
}

# Use fd to generate the list for directory completion
_fzf_compgen_dir() {
    fd --type=d --hidden --no-ignore-vcs --exclude .git . "${1}"
}

# Advanced customization of fzf options via _fzf_comprun function
# - The first argument to the function is the name of the command.
# - You should make sure to pass the rest of the arguments to fzf.
_fzf_comprun() {
    local command="${1}"
    shift

    case "${command}" in
        # cd **<TAB>
        cd)           fzf --preview 'eza --tree --color=always {} | head -200' "$@" ;;
        export|unset) fzf --preview "eval 'echo \${}'"         "$@" ;;
        # llt **<TAB>
        llt)          fd --type d --hidden | fzf --preview 'eza --tree --color=always {} | head -200' "$@" ;;
        # llt **<TAB>
        ssh)          fzf --preview 'dig {}'                   "$@" ;;
        # any_other_command **<TAB>
        *)            fzf --preview "${show_file_or_dir_preview}" "$@" ;;
    esac
}
