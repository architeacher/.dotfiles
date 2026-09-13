#!/usr/bin/env bash

set -Eeuo pipefail

main() {
    log_info "Installing lazygit themes."

    install_theme "https://github.com/catppuccin/lazygit.git" "${XDG_CONFIG_HOME}/lazygit/themes"
}

main "$@"
