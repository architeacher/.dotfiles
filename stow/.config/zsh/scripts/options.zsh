#!/usr/bin/env zsh

# +------------------------------------+
# | Using terminfo in Application Mode |
# +------------------------------------+

# Organized to match the Z Shell Manual's "Options" chapter
# https://zsh.sourceforge.io/Doc/Release/Options.html
#
# TIPS:
#   1) You can list the existing shell options with the `setopt` command.
#   2) You can get a list of all default zsh options with the `emulate -lLR zsh` command.
#   3) You can revert the options for the current shell to the default settings with the `emulate -LR zsh` command.

# This only sets options that exist
setopt_if_exists() {
    local option="${1}"
    if [[ "${options[${option}]+1}" ]]; then
        setopt "${option}"
    fi
}

# +-------------+
# | Completions |
# +-------------+

unsetopt FLOW_CONTROL    # If this option is unset, output flow control via start/stop characters (usually assigned to ^S/^Q) is disabled in the shell’s editor.

setopt ALWAYS_TO_END     # On completion, the cursor is moved to the end of the word.
setopt AUTO_LIST         # Automatically list choices on ambiguous completion.
setopt AUTO_MENU         # Show completion menu on a successive tab press.
setopt COMPLETE_ALIASES
setopt COMPLETE_IN_WORD  # Complete from both ends of a word.
setopt LIST_PACKED       # Try to make the completion list smaller (occupying less lines) by printing the matches in columns with different widths.
setopt LIST_ROWS_FIRST   # Lay out the matches in completion lists sorted horizontally, that is, the second match is to the right of the first one, not under it as usual.
setopt LIST_TYPES        # When listing files that are possible completions, show the type of each file with a trailing identifying mark.
setopt MENU_COMPLETE     # Automatically highlight first element of completion menu
setopt PATH_DIRS         # Perform path search even on command names with slashes.

# +------------------------+
# | Expansion and Globbing |
# +------------------------+

setopt EXTENDED_GLOB          # Treat the ‘#’, ‘~’ and ‘^’ characters as part of patterns for filename generation.

# +---------+
# | History |
# +---------+

setopt APPEND_HISTORY         # adds history.
setopt EXTENDED_HISTORY       # Write the history file in the ':start:elapsed;command' format.
setopt HIST_BEEP              # Beep in ZLE when a widget attempts to access a history entry which isn’t there.
setopt HIST_EXPIRE_DUPS_FIRST # Expire a duplicate event first when trimming history.
setopt HIST_FIND_NO_DUPS      # Do not find duplicate commands when searching.
setopt HIST_IGNORE_ALL_DUPS   # Delete an old recorded event if a new entry is a duplicate.
setopt HIST_IGNORE_DUPS       # Do not record an entry that was just recorded again.
setopt HIST_IGNORE_SPACE      # Do not record an entry starting with a space.
setopt HIST_REDUCE_BLANKS     # remove superfluous blanks before recording entry.
setopt HIST_SAVE_NO_DUPS      # Do not write a duplicate entry to the history file.
setopt HIST_VERIFY            # Do not execute immediately upon history expansion (!!, !$, etc.), present for user confirmation/editing.
setopt INC_APPEND_HISTORY     # Appends to the history file incrementally (as soon as they are entered), rather than waiting until the shell exits.
setopt SHARE_HISTORY          # Share history between all sessions.

# Do not append history entries to the history file
# NOTE: This has to be turned off for shared history to work.
setopt_if_exists NO_INC_APPEND_HISTORY

# Disable writing out the history entry to the file after the command is finished.
# NOTE: This has to be turned off for shared history to work.
setopt_if_exists NO_INC_APPEND_HISTORY_TIME

# +--------------+
# | Input/Output |
# +--------------+

# Prevent existing files from being overwritten by redirection operations (`>`).
# You can still override this with `>|`.
setopt_if_exists no_clobber

setopt CORRECT              # Autocorrect spelling correction for commands with typos and ask to run the correct command instead.

#setopt correct_all            # all arguments
setopt_if_exists interactive_comments   # Allow comments in interactive shells (like Bash does)

unset setopt_if_exists

# +------------+
# | Navigation |
# +------------+

setopt AUTO_CD           # Go to folder path without using cd.
setopt AUTO_PUSHD        # Push the old directory onto the stack on cd.
setopt CDABLE_VARS       # Change directory to a path stored in a variable.
setopt PUSHD_IGNORE_DUPS # Do not store duplicates in the stack.
setopt PUSHD_MINUS       # Exchanges the meanings of ‘+’ and ‘-’ when used with a number to specify a directory in the stack.
setopt PUSHD_SILENT      # Do not print the directory stack after pushd or popd.

# +---------------+
# | Safe Deletion |
# +---------------+

setopt RM_STAR_WAIT      # Wait 10 seconds until executing rm with a star rm folder/*
unsetopt RM_STAR_SILENT  # Ask before executing rm with a star rm folder/*
