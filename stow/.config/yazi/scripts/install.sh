#!/usr/bin/env bash

set -Eeuo pipefail

main() {
    log_info "Installing yazi themes."

    install_theme "https://github.com/catppuccin/yazi.git" "${XDG_CONFIG_HOME}/yazi/themes"
}

main "$@"
