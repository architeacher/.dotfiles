#!/usr/bin/env bash

set -Eeuo pipefail

main() {
    log_info "Installing btop themes."

    install_theme "https://github.com/catppuccin/btop.git" "${XDG_CONFIG_HOME}/btop/themes"
    install_theme "https://github.com/rose-pine/btop.git" "${XDG_CONFIG_HOME}/btop/themes" "."
}

main "$@"
