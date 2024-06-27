#!/usr/bin/env zsh

###############################
# EXPORT ENVIRONMENT VARIABLE #
###############################
# Zsh start up sequence:
#  1) /etc/zshenv   -> Always run for every zsh.   (login + interactive + other)
#  2)   ~/.zshenv   -> Usually run for every zsh.  (login + interactive + other)
#  3) /etc/zprofile -> Run for login shells.       (login)
#  4)   ~/.zprofile -> Run for login shells.       (login)
#  5) /etc/zshrc    -> Run for interactive shells. (login + interactive)
#  6)   ~/.zshrc    -> Run for interactive shells. (login + interactive)
#  7) /etc/zlogin   -> Run for login shells.       (login)
#  8)   ~/.zlogin   -> Run for login shells.       (login)

# https://unix.stackexchange.com/questions/654663/problem-with-zsh-history-file
# No need to export anything here, as .zshenv is sourced for
# _every_ shell (unless invoked with `zsh -f`).
# Only vars used by external commands or non-interactive sub
# shells need to be exported. Note that you can export vars
# without assigning values to them.

# The easiest way to discover exactly where it's overridden, is to start Zsh with

# +-----------------------------+
# | zsh --sourcetrace --verbose |
# +-----------------------------+

# This will:
# -> print each file before it gets sourced (incl. files not sourced directly by Zsh) and
# -> print each command (incl. parameter assignments) before it gets evaluated.

# ----- XDG -----

# Assign these only if they don't have value yet.
: ${XDG_CACHE_HOME:=~/.cache}
: ${XDG_CONFIG_HOME:=~/.config}
: ${XDG_DATA_HOME:=~/.local/share}
: ${XDG_STATE_HOME:=~/.local/state}

# link to .config folder for configs.
: ${ZDOTDIR:="${XDG_CONFIG_HOME}/zsh"}
