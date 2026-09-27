#!/usr/bin/env bash

set -Eeuo pipefail

install_bottom_themes() {
    log_info "Installing bottom themes."

    install_theme "https://github.com/catppuccin/bottom.git" "${XDG_CONFIG_HOME}/bottom/themes"
}

main() {
    install_bottom_themes
}

main "$@"
