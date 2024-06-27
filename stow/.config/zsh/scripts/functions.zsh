#!/usr/bin/env zsh

function brew() {
    local action="${1}"

    if [ -z "${action+x}" ] || [ "${action}" != "add" ]
    then
        # Call the original brew command with all original arguments
        command brew "$@"

        return 0
    fi

    # Remove the first argument ("add")
    shift
    # Install the package
    command brew install "$@"
    # Update the global Brewfile
    command brew bundle dump --force --global
}

# +-----+
# | Fun |
# +-----+

emo() {
    local selected_emoji

    selected_emoji="$(curl --compressed -m 10 -s "https://raw.githubusercontent.com/github/gemoji/master/db/emoji.json" | \
                        jq -r ".[] | \"\(.emoji) :\(.aliases[0]): \(.description)\"" | \
                        fzf-tmux -1 \
                            --ansi \
                            --header "Emojify" \
                            --preview "echo {} | awk -F \":\" '{print \$1,\$3}'" \
                            --preview-window=right:55% \
                            --tiebreak=index | \
                        awk "{print \":\" \$2 \":\"}" | \
                        tr -d " " | \
                        sed "s/^://; s/:$//" | \
                        tr -d "\\n" \
                       )"

    printf "%s" "${selected_emoji}" | tee >(pbcopy)
}

# function Extract for common file formats
#
# This is a Bash function called "extract" that is designed to extract a variety of file formats.
# It takes one or more arguments, each of which represents a file or path that needs to be extracted.
# If no arguments are provided, the function displays usage instructions.
#
# This bash script allows to download a file from Github storage https://github.com/xvoland/Extract/blob/master/extract.sh
#
# Usage:
#     extract <path/file_name>.<zip|rar|bz2|gz|tar|tbz2|tgz|Z|7z|xz|ex|tar.bz2|tar.gz|tar.xz|.zlib|.cso|.zst>
#
# Example:
# $ extract file_name.zip
#
# Author: Vitalii Tereshchuk, 2013
# Web:    https://dotoca.net
# Github: https://github.com/xvoland/Extract/blob/master/extract.sh


SAVEIFS="${IFS}"
IFS="$(printf '\n\t')"

function extract {
    if [ $# -eq 0 ]; then
        # display usage if no parameters given
        echo "Usage: extract <path/file_name>.<zip|rar|bz2|gz|tar|tbz2|tgz|Z|7z|xz|ex|tar.bz2|tar.gz|tar.xz|.zlib|.cso|.zst>"
        echo "       extract <path/file_name_1.ext> [path/file_name_2.ext] [path/file_name_3.ext]"
    fi
    for n in "$@"; do
        if [ ! -f "$n" ]; then
            echo "'$n' - file doesn't exist"
            return 1
        fi

        case "${n%,}" in
          *.cbt|*.tar.bz2|*.tar.gz|*.tar.xz|*.tbz2|*.tgz|*.txz|*.tar)
                       tar zxvf "$n"       ;;
          *.lzma)      unlzma ./"$n"      ;;
          *.bz2)       bunzip2 ./"$n"     ;;
          *.cbr|*.rar) unrar x -ad ./"$n" ;;
          *.gz)        gunzip ./"$n"      ;;
          *.cbz|*.epub|*.zip) unzip ./"$n"   ;;
          *.z)         uncompress ./"$n"  ;;
          *.7z|*.apk|*.arj|*.cab|*.cb7|*.chm|*.deb|*.iso|*.lzh|*.msi|*.pkg|*.rpm|*.udf|*.wim|*.xar|*.vhd)
                       7z x ./"$n"        ;;
          *.xz)        unxz ./"$n"        ;;
          *.exe)       cabextract ./"$n"  ;;
          *.cpio)      cpio -id < ./"$n"  ;;
          *.cba|*.ace) unace x ./"$n"     ;;
          *.zpaq)      zpaq x ./"$n"      ;;
          *.arc)       arc e ./"$n"       ;;
          *.cso)       ciso 0 ./"$n" ./"$n.iso" && \
                            extract "$n.iso" && \rm -f "$n" ;;
          *.zlib)      zlib-flate -uncompress < ./"$n" > ./"$n.tmp" && \
                            mv ./"$n.tmp" ./"${n%.*zlib}" && rm -f "$n"   ;;
          *.dmg)
                      hdiutil mount ./"$n" -mountpoint "./$n.mounted" ;;
          *.tar.zst)  tar -I zstd -xvf ./"$n"  ;;
          *.zst)      zstd -d ./"$n"  ;;
          *)
                      echo "extract: '$n' - unknown archive method"
                      return 1
                      ;;
        esac
    done
}

IFS="${SAVEIFS}"

# +-----+
# | Man |
# +-----+

man() {
	env \
		LESS_TERMCAP_mb="$(printf '\e[1;31m')" \
		LESS_TERMCAP_md="$(printf '\e[1;31m')" \
		LESS_TERMCAP_me="$(printf '\e[0m')" \
		LESS_TERMCAP_se="$(printf '\e[0m')" \
		LESS_TERMCAP_so="$(printf '\e[1;44;33m')" \
		LESS_TERMCAP_ue="$(printf '\e[0m')" \
		LESS_TERMCAP_us="$(printf '\e[1;32m')" \
		man "$@"
}

# +------------+
# | Navigation |
# +------------+

cl() { cd "$@" && ls; }

# Cd into the directory shown by the front-most Finder window
# Based on https://scriptingosx.com/2017/02/terminal-finder-interaction/
cdf() {
    cd "$(osascript -e 'tell app "Finder" to POSIX path of (insertion location as alias)')" || return 0
}

function d () {
    if [[ -n "${1}" ]]; then
        dirs "$@"
    else
        dirs -v | head -n 10
    fi
}

# shellcheck disable=SC2154
(( $+commands[compdef] )) && {
    compdef _dirs d
}

fcd() { cd "$(fd . -t d -H | fzf)" && ls; }

f() { fd . -t f -H | fzf | pbcopy; }

fv() { nvim "$(fd . -t f -H | fzf)"; }
