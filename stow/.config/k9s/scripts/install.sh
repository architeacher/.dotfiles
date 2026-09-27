#!/usr/bin/env bash

set -Eeuo pipefail

main() {
    log_info "Installing k9s themes."

    install_theme "https://github.com/catppuccin/k9s.git" "${XDG_CONFIG_HOME}/k9s/skins" "dist"
    install_theme "https://github.com/derailed/k9s.git" "${XDG_CONFIG_HOME}/k9s/skins" "skins"
}

main "$@"
