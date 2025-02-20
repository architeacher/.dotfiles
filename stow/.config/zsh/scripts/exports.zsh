#!/usr/bin/env zsh

# Only vars used by external commands or non-interactive sub
# shells need to be exported. Note that you can export vars
# without assigning values to them.

# +-----+
# | XDG |
# +-----+

export XDG_CACHE_HOME
export XDG_CONFIG_HOME
export XDG_DATA_HOME

# +----------+
# | Dotfiles |
# +----------+

export DOTFILES="${HOME}/.dotfiles"

# +----------+
# | LANGUAGE |
# +----------+

[ -z "${LANG+x}" ] && {
    export LC_ALL="en_US.UTF-8"     # Prefer US English and use UTF-8
    export LANG="en_US.UTF-8"
    export LANGUAGE="en_US.UTF-8"
}

# +-----------------------+
# | Bat (The better cat!) |
# +-----------------------+

# Bat: https://github.com/sharkdp/bat
# highlighting theme: https://github.com/sharkdp/bat?tab=readme-ov-file#adding-new-themes
export BAT_THEME="Catppuccin Mocha"

# +-------------+
# | COMPLETIONS |
# +-------------+

# carapace
# shellcheck disable=SC2154
(( $+commands[carapace] )) &&  {
    export CARAPACE_BRIDGES='zsh,fish,bash,inshellisense'
}

# Don't offer history completion; we have fzf, C-r, and
# zsh-history-substring-search for that.
#ZSH_AUTOSUGGEST_STRATEGY=(completion)
export ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=30

# +--------+
# | EDITOR |
# +--------+

export EDITOR='vi'
# nvim
type nvim &>/dev/null && {
    export EDITOR='nvim'
}

export VISUAL="${EDITOR}"

# +-----+
# | EZA |
# +-----+

# Customize LS colors
# Used by: ls, fd
LS_COLORS="$(vivid generate "$(vivid themes | shuf -n 1)")"

export LS_COLORS

# Eza colors: https://github.com/eza-community/eza/blob/main/man/eza_colors.5.md
EZA_COLORS="reset:${LS_COLORS}"                     # Reset default colors, like making everything yellow
EZA_COLORS+="co=35:*.zip=35:"                       # Archives
#EZA_COLORS+="da=36:"                                # Timestamps
EZA_COLORS+="di=0;38;2;137;180;250:"                # Directory
#EZA_COLORS+="do=32:*.md=32:"                        # Documents
#EZA_COLORS+="ex=1;38;2;243;139;168:"                # Executable
#EZA_COLORS+="fi=0:"                                 # Regular file
#EZA_COLORS+="ln=0;38;2;245;194;231:"                # Symbolic link
#EZA_COLORS+="gr=0:gw=0:gx=0:"                       # Group permissions
EZA_COLORS+="nb=38;5;240:"                          # Files under 1 KB
EZA_COLORS+="ng=38;5;250:"                          # Files under 1 TB
EZA_COLORS+="nk=0:"                                 # Files under 1 MB
EZA_COLORS+="nm=37:"                                # Files under 1 GB
EZA_COLORS+="nt=38;5;255:"                          # Files over 1 TB
#EZA_COLORS+="or=0;38;2;17;17;27;48;2;243;139;168:"  # Orphaned/Broken symbolic link
#EZA_COLORS+="so=0;38;2;17;17;27;48;2;245;194;231:"  # Socket
EZA_COLORS+="tm=38;5;242:cm=38;5;242:.*=38;5;242:"  # Hidden and temporary files
#EZA_COLORS+="tr=0:tw=0:tx=0:"                      # Other permissions
#EZA_COLORS+="ur=0:uw=0:ux=0:ue=0:"                 # User permissions
#EZA_COLORS+="xa=0:"                                 # Extended attribute marker ('@')
EZA_COLORS+="xx=38;5;240:"                          # Punctuation ('-')

export EZA_COLORS

# +----+
# | FD |
# +----+

export FD_IGNORE_FILE="${XDG_CONFIG_HOME}/fd/.fdignore"

# +-----+
# | FZF |
# +-----+

show_file_or_dir_preview="if [ -d {} ]; then eza --tree --color=always {} | head -200; else bat -n --color=always --line-range :500 {}; fi"

# --- Use fd instead of fzf ---
export FZF_DEFAULT_COMMAND="fd --exclude .git --hidden --strip-cwd-prefix"
export FZF_ALT_C_COMMAND="fd --exclude .git --hidden --strip-cwd-prefix --type=d"
export FZF_ALT_C_OPTS="--preview 'eza --tree --color=always {} | head -300'"
export FZF_CTRL_T_COMMAND="${FZF_DEFAULT_COMMAND}"
export FZF_CTRL_T_OPTS="--preview '${show_file_or_dir_preview}'"

# CTRL-R − Paste the selected command from history onto the command-line.
# CTRL-/ to toggle small preview window to see the full command
# CTRL-Y to copy the command into clipboard using pbcopy
export FZF_CTRL_R_OPTS="
  --preview 'echo {}' --preview-window down:3:hidden:wrap
  --bind 'ctrl-/:toggle-preview'
  --bind 'ctrl-y:execute-silent(echo -n {2..} | pbcopy)+abort'
  --color header:italic
  --header 'Press CTRL-Y to copy command into clipboard'"

export FZF_COMPLETION_TRIGGER='**'
export FZF_COMPLETION_OPTS='--border --info=inline'

# --- Setup fzf theme ---

# https://vitormv.github.io/fzf-themes/
bg="#1e1e2e"
bg_highlight="#313244"
ext_highlight="#f38ba8"
ext_sel_highlight="#f38ba8"
fg="#cdd6f4"
fg_highlight="#cdd6f4"
header="#f38ba8"
info="#cba6f7"
marker="#f5e0dc"
pointer="#f5e0dc"
prompt_clr="#cba6f7"
spinner="#f5e0dc"

export FZF_COLORS="bg:${bg},\
bg+:${bg_highlight},\
fg:${fg},\
fg+:${fg_highlight},\
header:${header},\
hl:${ext_highlight},\
hl+:${ext_sel_highlight},\
info:${info},\
marker:${marker},\
pointer:${pointer},\
prompt:${prompt_clr},\
spinner:${spinner}"

# Use generator to customize:
# https://vitormv.github.io/fzf-themes/
# To add wrap lines add:
# --preview-window=wrap
export FZF_DEFAULT_OPTS=" \
--bind 'ctrl-a:toggle' \
--bind='ctrl-b:preview-page-up,ctrl-f:preview-page-down' \
--bind 'ctrl-h:change-preview-window(hidden|)' \
--bind='ctrl-o:execute(code {})+abort' \
--bind='ctrl-q:abort' \
--bind='ctrl-s:toggle-sort' \
--border sharp \
--color ${FZF_COLORS} \
--cycle \
--height 60% \
--info right \
--layout reverse-list \
--marker '✔ ' \
--pointer ▶ \
--preview-window='border-sharp' \
--prompt '∷ ' \
-i"

# fzf-git configuration:
export FZF_GIT_COLOR='never'
export FZF_GIT_PREVIEW_COLOR='always'

# +-----+
# | Git |
# +-----+

export GIT_CONFIG_GLOBAL="${XDG_CONFIG_HOME}/git/config"
export GIT_EDITOR="${EDITOR}"

# +-----+
# | GPG |
# +-----+

export GNUPGHOME="${XDG_DATA_HOME}/gnupg"
GPG_TTY="$(tty)"

export GPG_TTY

# +---------+
# | History |
# +---------+

# HISTFILE is used by interactive shells only. Plus,
# non-interactive shells & external commands don't need this var.
# Hence, we put it in the exports.zsh file, since that's sourced for
# each interactive shell, and don't export it
HISTFILE="${XDG_STATE_HOME}/zsh/history" # History filepath
HISTSIZE=100000                          # Maximum events remembered for internal history
# shellcheck disable=SC2034
SAVEHIST="${HISTSIZE}"                   # Maximum events stored in history file

# +----------+
# | Homebrew |
# +----------+

# Homebrew: https://docs.brew.sh/Manpage#environment
export HOMEBREW_BUNDLE_FILE="${XDG_CONFIG_HOME}/homebrew/Brewfile"
export HOMEBREW_BUNDLE_FILE_GLOBAL="${XDG_CONFIG_HOME}/homebrew/Brewfile-global"
export HOMEBREW_CASK_OPTS="--appdir=/Applications --require-sha"
export HOMEBREW_INSTALL_BADGE='☕'
export HOMEBREW_NO_ANALYTICS=1
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ENV_HINTS=1
export HOMEBREW_NO_GITHUB_API=1
export HOMEBREW_NO_INSECURE_REDIRECT=1

# +---------+
# | Lazygit |
# +---------+

export LG_CONFIG_FILE="${XDG_CONFIG_HOME}/lazygit/config.yaml,${XDG_CONFIG_HOME}/lazygit/themes/mocha/blue.yml"

# +------+
# | Less |
# +------+

# Set the default Less options.
# Mouse-wheel scrolling has been disabled by -X (disable screen clearing).
# Remove -X and -F (exit if the content fits on one screen) to enable it.
export LESS='-F -g -i -M -R -S -w -X -z-4'

# Make less the default pager with added options.

# Set up a preprocessor for the less pager.
[ -n "${LESSPIPE}" ] && export LESSOPEN="| ${LESSPIPE} %s"

less_options=(
    # Do not automatically fold long lines to the next line.
    --chop-long-lines

    # Do not complain when we are on a dumb terminal.
    --dumb

    # Like "smartcase" in Vim: ignore case unless the search pattern is mixed
    --ignore-case

    # Do not clear the screen first
    --no-init

    # Do not ring the bell when trying to scroll past the end of the buffer.
    --quiet

    # If the entire text fits on one screen, just show it and quit. (Be more
    # like "cat" and less like "more")
    --quit-if-one-screen

    # Allow ANSI colour escapes, but no other escapes.
    --RAW-CONTROL-CHARS
)

export LESS="${less_options[*]}"

# Disable the history file to not leave a trail of previously viewed files on the system.
export LESSHISTFILE='-'

export PAGER='less'

# +-------+
# | Netrc |
# +-------+

export NETRC="${DOTFILES}/private/.config/netrc"

# +----------+
# | Starship |
# +----------+

export STARSHIP_CONFIG="${XDG_CONFIG_HOME}/starship/starship.toml"
