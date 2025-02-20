#!/usr/bin/env zsh

# ===================================
# ===   Useful list of Aliases    ===
# ===================================

alias forecast='curl -4 --compressed -m 10 -s "https://wttr.in?F"'
alias hollywood='docker run -it --name "holllywood-${RANDOM}" --rm jess/hollywood'
alias password!='uuidgen | md5'
alias reload!='. ${ZDOTDIR}/.zshrc && echo "Shell config reloaded from ${ZDOTDIR}/.zshrc"'
alias shrug='printf "¯\_(ツ)_/¯" | tee >(pbcopy) | { printf "🤷 = "; cat; } | lolcat'
alias starwar='telnet towel.blinkenlights.nl'
alias starwars='nc starwarstel.net 23'
alias token!='LC_ALL=C tr -dc A-Za-z0-9 </dev/urandom | head -c 15; echo'
alias weather='curl --compressed -m 10 -s "https://wttr.in/?format=%l:+(%C)+%c++%t+\[%h,+%w\]"'

# +-----------------------+
# | Bat (The better cat!) |
# +-----------------------+

# shellcheck disable=SC2154
(( $+commands[bat] )) && {
    alias cat='bat -pp'
    alias catt='bat'
}

# +--------------+
# | Certificates |
# +--------------+

alias certify='openssl req -new -x509 -nodes -out cert.pem -keyout cert.key -days 365'

# +---------+
# | Docker |
# +--------+

command docker > /dev/null 2>&1 && {
    alias dco='docker compose'
}

# +-----+
# | Eza |
# +-----+

hash eza > /dev/null 2>&1 && {
    # ls
    alias ls='eza'
    # one column, just names
    alias lS='ls -1'
    alias l='ls -lb --git --git-ignore --group-directories-first --icons'
    alias lt='l --tree'
    alias ll='eza -lab --group-directories-first --git --icons'
    alias llt='ll --tree --level 5'
    # all list
    alias la='eza -labhHigUmuS --color-scale --git --group-directories-first --icons --sort=modified --time-style=long-iso'
    # all + extended list
    alias lx='la -@'
}

# +---------+
# | Helpers |
# +---------+

# easier to read disk
alias df='duf'     # human-readable sizes

alias dev='brew leaves | fzf --height 20% --header Commands | zsh'

type fd > /dev/null 2>&1 && {
    alias find='fd'
    alias v='fd --type f --hidden --exclude .git | fzf-tmux --bind "q:abort" -p --preview "bat --color \"always\" {}" | xargs nvim'
}

which nvim > /dev/null 2>&1 && {
    alias vi='nvim'
    alias vim='nvim'
}

# +------+
# | K8s |
# +-----+

which kubectl > /dev/null 2>&1 && {
    alias k='kubectl'
    alias ka='kubectl apply -f'
    alias kcns='kubectl config set-context --current --namespace'
    alias kd='kubectl describe'
    alias kdel='kubectl delete'
    alias ke='kubectl exec -it'
    alias kg='kubectl get'
    alias kgd='kubectl get deployments'
    alias kgpo='kubectl get pod'
    alias kl='kubectl logs -f'
}

which kubectl > /dev/null 2>&1 && {
    alias kc='kubectx'
    alias kns='kubens'
}

# +------------+
# | Monitoring |
# +------------+

which btm > /dev/null 2>&1 && {
    alias htop='btm'
}

which btop > /dev/null 2>&1 && {
    alias top='btop'
}

# +------------+
# | Navigation |
# +------------+

alias -g ...='../..'
alias -g ....='../../..'
alias -g .....='../../../..'
alias -g ......='../../../../..'

alias -- -='cd -'
alias 1='cd -1'
alias 2='cd -2'
alias 3='cd -3'
alias 4='cd -4'
alias 5='cd -5'
alias 6='cd -6'
alias 7='cd -7'
alias 8='cd -8'
alias 9='cd -9'

alias md='mkdir -p'
alias rd=rmdir

# +------------+
# | Networking |
# +------------+

alias flushdns='dscacheutil -flushcache; sudo killall -HUP mDNSResponder;echo DNS cache flushed'
alias ip='ipconfig getifaddr en0'

# +--------+
# | Search |
# +--------+

# shellcheck disable=SC2154
(( $+commands[rg] )) && {
    alias search='rg --color="always" -. --follow --glob "!{.git/*,node_modules/*}" --heading --line-number --no-ignore --no-messages --smart-case -e'
}

# +--------+
# | System |
# +--------+

alias reboot='sudo shutdown -r now'
alias shutdownmac='sudo shutdown -h now'

# Show/hide hidden files in Finder
alias show='defaults write com.apple.finder AppleShowAllFiles -bool true && killall Finder'
alias hide='defaults write com.apple.finder AppleShowAllFiles -bool false && killall Finder'

# Show/hide all desktop icons (useful when presenting)
alias showdesktop='defaults write com.apple.finder CreateDesktop -bool true && killall Finder'
alias hidedesktop='defaults write com.apple.finder CreateDesktop -bool false && killall Finder'

# +------+
# | Time |
# +------+

# Display the current date in local zone and ISO-8601 format `YYYY-MM-DDThh:mm:ss+mmss`.
alias now='date +"%d-%m-%YT%H:%M:%S%z"'

# Display the current date in UTC and ISO 8601 format `YYYY-MM-DDThh:mm:ss`
alias unow='date -u +"%d-%m-%YT%H:%M:%S"'

# Gets the local time in `hh:mm:ss` format`
alias nowtime='date +"%T"'

# Gets the UTC time in `hh:mm:ss` format
alias unowtime='date -u +"%T"'

# Gets Unix time stamp
alias timestamp='date -u +%s'

# +------+
# | Tmux |
# +------+

alias tmxa='tmux attach -t'                    # Attaches tmux to a session (example: tmxa portal).
alias tmxc='clear; tmux clear-history; clear'  # Clears Tmux pane.
alias tmxd='tmux detach'                       # Detaches from a session.
alias tmxk='tmux kill-session -t'              # Kills a session.
alias tmxl='tmux list-sessions'                # Lists all ongoing sessions.
alias tmxn='tmux new-session -s'               # Creates a new session.

# +-------+
# | Trash |
# +-------+

# https://github.com/sindresorhus/guides/blob/main/how-not-to-rm-yourself.md#safeguard-rm
# -I prompt once before removing more than three files, or when removing recursively.
# Less intrusive than -i, while still giving protection against most mistakes.
alias rm='rm -I'

# Safer reversible file removal: https://github.com/sindresorhus/trash-cli
which trash > /dev/null 2>&1 && {
    alias purge='unalias rm && sudo rm -rf ${XDG_DATA_HOME}/Trash/*; alias rm="trash -i"'
    alias rm='trash'
}

# +-----+
# | Web |
# +-----+

which xh > /dev/null 2>&1 && {
    alias http='xh'
    # One of @janmoesen’s ProTip™s
    for method in GET HEAD POST PUT DELETE TRACE OPTIONS; do
    	# shellcheck disable=SC2139
    	alias "${method}"="xh ${method}"
    done
}
