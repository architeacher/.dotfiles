.DEFAULT: default
.DEFAULT_GOAL := default
# Delete targets on nonzero exit status.
.DELETE_ON_ERROR: ;
.EXPORT_ALL_VARIABLES: ;
.NOTPARALLEL: ;
.ONESHELL: ;
.SHELLFLAGS = -c

# Unless ECHO_RECIPES is defined we do not echo the line of the recipes before they are executed.
ifneq (true, ${ECHO_RECIPES})
.SILENT: ;
endif

SHELL := /bin/bash

# An empty, phony .FORCE target, that will cause external targets to always be built, so that the
# Makefile there will handle dependencies.
# https://gist.github.com/mschubert/a0e4f3aeaf3558431890
.PHONY: .FORCE
.FORCE: ;

# See https://en.wikipedia.org/wiki/ANSI_escape_code#8-bit
NO_CLR = \033[0m
AZURE = \x1b[1;38;5;45m
CYAN = \x1b[96m
GREEN = \x1b[1;38;5;113m
OLIVE = \x1b[1;36;5;113m
MAGENTA = \x1b[38;5;170m
ORANGE =  \x1b[1;38;5;208m
RED = \x1b[91m
YELLOW = \x1b[1;38;5;227m

INFO_CLR := ${AZURE}
DISCLAIMER_CLR := ${MAGENTA}
ERROR_CLR := ${RED}
HELP_CLR := ${CYAN}
OK_CLR := ${GREEN}
ITEM_CLR := ${OLIVE}
LIST_CLR := ${ORANGE}
WARN_CLR := ${YELLOW}

STAR := ${ITEM_CLR}[${NO_CLR}${LIST_CLR}*${NO_CLR}${ITEM_CLR}]${NO_CLR}
PLUS := ${ITEM_CLR}[${NO_CLR}${WARN_CLR}+${NO_CLR}${ITEM_CLR}]${NO_CLR}

MSG_PRFX := ==>
MSG_SFX := ...

## Path to .env file.
DOT_ENV_FILE ?= $(CURDIR)/.env

## To echo recipes, you can do "make ECHO_RECIPES=true".
ECHO_RECIPES ?= false

##  Log level of the messages.
LOG_LEVEL = 7 # Debug

## To disable root, you can do "make SUDO=".
SUDO ?= $(shell echo "sudo -E" 2> /dev/null)
