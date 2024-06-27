#!/usr/bin/env zsh

# Fuzzy search Git branches in a repo
# Looks for local and remote branches
function fco() {
    local pattern="$*"

    git branch -a \
               --sort=-committerdate | \
        awk "tolower($0) ~ /${pattern}/" | \
        fzf-tmux -1 \
            --ansi \
            --bind "ctrl-o:become:(echo {} | rg -o '[a-f0-9]\{7\}' | head -1 | xargs git checkout)" \
            --bind=ctrl-s:toggle-sort \
            --bind "q:abort,ctrl-f:preview-page-down,ctrl-b:preview-page-up" \
            --header "Checkout Recent Branch" \
            --no-sort \
            -p \
            --pointer="" \
            --preview "git diff --color=always {1}" \
            --preview-window=right:65% \
            --tiebreak=index | \
        sed "s/.* //" | \
        sed "s#remotes/[^/]*/##" | \
        xargs git checkout
}

# Fuzzy search over Git commits
# Enter will view the commit
# Ctrl-o will checkout the selected commit
function fshow() {
  git log \
      --color=always \
      --format="%C(auto)%h%d %s %C(black)%C(bold)%cr" "$@" \
      --graph |
      fzf --ansi \
          --bind "ctrl-o:become:(echo {} | rg -o '[a-f0-9]\{7\}' | head -1 | xargs git checkout)" \
          --bind=ctrl-s:toggle-sort \
          --bind "q:abort,ctrl-f:preview-page-down,ctrl-b:preview-page-up" \
          --header "Enter to view, ctrl-o to checkout" \
          --no-sort \
          --pointer="" \
          --preview \
             'f() { set -- $(echo -- "$@" | grep -o "[a-f0-9]\{7\}"); [ $# -eq 0 ] || git show --color=always $1 ; }; f {}' \
          --preview-window=right:65% \
          --reverse \
          --tiebreak=index \
          --bind "ctrl-m:execute:
                    (grep -o '[a-f0-9]\{7\}' | head -1 |
                    xargs -I % sh -c 'git show --color=always % | less -R') << 'FZF-EOF'
                    {}
FZF-EOF"
}
