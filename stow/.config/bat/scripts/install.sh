#!/usr/bin/env bash

set -Eeuo pipefail

main() {
    log_info "Installing bat themes."

    install_theme "https://github.com/catppuccin/bat.git" "$(bat --config-dir)/themes"

    {
        bat cache --build
        bat --list-themes -P
        bat "$(bat --config-file)"
    } 2>/dev/null
}

main "$@"
