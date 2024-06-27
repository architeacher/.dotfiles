#!/usr/bin/env zsh

# +---------+
# | zstyles |
# +---------+

# Ztyle pattern
# :completion:<function>:<completer>:<command>:<argument>:<tag>


# +----------------+
# | Fuzzy Matching |
# +----------------+

# Define completers
zstyle ':completion:*' completer _approximate _complete _extensions _match _list
zstyle ':completion:*' matcher-list 'm:{[:lower:]-}={[:upper:]_}' 'r:[[:ascii:]]||[[:ascii:]]=** r:|?=**'
zstyle ':completion:*:approximate:*' max-errors 1 numeric
zstyle ':completion:*:match:*' original only

# +---------+
# | Aliases |
# +---------+

zle -C alias-expension complete-word _generic
bindkey '^Xa' alias-expension
zstyle ':completion:alias-expension:*' completer _expand_alias

# +---------+
# | Caching |
# +---------+

# Use cache for commands which use it
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "${XDG_CACHE_HOME}/zsh/.zcompcache"

# +--------+
# | Colors |
# +--------+

zstyle ':completion:*:default' list-colors "${(s.:.)LS_COLORS}"      # activate color-completion(!)

# +----------+
# | Grouping |
# +----------+

zstyle ':completion:*:corrections' format '%B%F{green}%d (errors: %e)%f%b'
zstyle ':completion:*:default' list-prompt '%S%M matches%s'
zstyle ':completion:*:descriptions' format $'%{\e[35;1m%}%d%{\e[0m%}'
zstyle ':completion:*:errors' format '%B%F{red}No such %d%f%b'
zstyle ':completion:*:messages' format '%B%F{yellow}%d%f%b'
zstyle ':completion:*:warnings' format '%B%F{red}No such %d%f%b'

# +---------+
# | History |
# +---------+

# Don't wrap around when navigating to either end of history
zstyle ':completion:*:history-words' stop yes
zstyle ':completion:*:history-words' remove-all-dups yes
zstyle ':completion:*:history-words' list false
zstyle ':completion:*:history-words' menu yes

# +-----+
# | K8S |
# +-----+

zstyle ':completion:*:*:kubectl:*' list-grouped false

# +-----+
# | Man |
# +-----+

zstyle ':completion:*:manuals' separate-sections true
zstyle ':completion:*:manuals.(^1*)' insert-sections true

# +------------+
# | Navigation |
# +------------+

# Required for completion to be in good groups (named after the tags)
zstyle ':completion:*' group-name ''
zstyle ':completion:*:*:-command-:*:*' group-order aliases builtins commands functions

# Omit parent and current directories from completion results when they are
# already named in the input.
zstyle ':completion:*:*:cd:*' ignore-parents parent pwd

zstyle ':completion:*' keep-prefix true

# See ZSHCOMPWID "completion matching control"
zstyle ':completion:*' matcher-list '' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'

# Expand partial paths, e.g. cd f/b/z == cd foo/bar/baz (assuming no ambiguity)
zstyle ':completion:*:paths' path-completion yes

# remove slash if argument is a directory
zstyle ':completion:*' squeeze-slashes true

# Only display some tags for the command cd
zstyle ':completion:*:*:cd:*' tag-order directory-stack local-directories path-directories

# +-----------+
# | Processes |
# +-----------+

zstyle ':completion:*:*:kill:*' force-list always
zstyle ':completion:*:*:kill:*' insert-ids single
zstyle ':completion:*:*:kill:*' menu yes select
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;36=0=01'
zstyle ':completion:*:*:*:*:processes' command 'ps -u $LOGNAME -o pid,user,command -w'

# +-------+
# | Setup |
# +-------+

# Complete the alias when _expand_alias is used as a function
zstyle ':completion:*' complete true

# Autocomplete options for cd instead of directory stack
zstyle ':completion:*' complete-options true

zstyle ':completion:*' file-sort modification

# Don't complete unavailable commands.
zstyle ':completion:*:(functions|parameters)' ignored-patterns '(_*|.*|-*|+*|autosuggest-*|pre(cmd|exec))'

# Increase the number of errors based on the length of the typed word.
zstyle -e ':completion:*:approximate:*' max-errors 'reply=($((($#PREFIX+$#SUFFIX)/3))numeric)'

# Allow you to select in a menu
zstyle ':completion:*' menu select

# Ignore multiple entries.
zstyle ':completion:*:(rm|kill|diff):*' ignore-line other
zstyle ':completion:*:rm:*' file-patterns '*:all-files'

# Sorry array completion candidates
zstyle ':completion:*:*:-subscript-:*' tag-order indexes parameters

# +-----+
# | SSH |
# +-----+

zstyle ':completion:*:(scp|rsync):*' tag-order 'hosts:-host:host hosts:-domain:domain hosts:-ipaddr:ip\ address *'
zstyle ':completion:*:(scp|rsync):*' group-order users files all-files hosts-domain hosts-host hosts-ipaddr
zstyle ':completion:*:ssh:*' tag-order 'hosts:-host:host hosts:-domain:domain hosts:-ipaddr:ip\ address *'
zstyle ':completion:*:ssh:*' group-order hosts-domain hosts-host users hosts-ipaddr
zstyle ':completion:*:(ssh|scp|rsync):*:hosts-domain' ignored-patterns '<->.<->.<->.<->' '^[-[:alnum:]]##(.[-[:alnum:]]##)##' '*@*'
zstyle ':completion:*:(ssh|scp|rsync):*:hosts-host' ignored-patterns '*(.|:)*' loopback ip6-loopback localhost ip6-localhost broadcasthost
zstyle ':completion:*:(ssh|scp|rsync):*:hosts-ipaddr' ignored-patterns '^(<->.<->.<->.<->|(|::)([[:xdigit:].]##:(#c,2))##(|%*))' '127.0.0.<->' '255.255.255.255' '::1' 'fe80::*'

zstyle -e ':completion:*:(ssh|scp|sftp|rsh|rsync):hosts' hosts 'reply=(${=${${(f)"$(cat {/etc/ssh_,~/.ssh/known_}hosts(|2)(N) /dev/null)"}%%[# ]*}//,/ })'

# Complete hostnames from ssh files too
zstyle -e ':completion:*:hosts' hosts 'reply=(
  ${=${=${=${${(f)"$(cat {/etc/ssh_,~/.{config/,}ssh/known_}hosts(|2)(N) 2>/dev/null)"}%%[#| ]*}//\]:[0-9]*/ }//,/ }//\[/ }
  ${=${${${${(@M)${(f)"$(cat ~/.{config/,}ssh/config 2>/dev/null)"}:#Host *}#Host }:#*\**}:#*\?*}}
)'
