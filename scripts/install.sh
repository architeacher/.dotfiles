#!/usr/bin/env bash

set -eou pipefail

. "$(dirname "${BASH_SOURCE[0]}")/common.sh"

cleanup_list=()
exit_status=0

configure_git(){
    local email="${1}" \
          name="${2}" \
          signing_key_id="${3}" \
          github_username="${4}" \
          config_path="${XDG_CONFIG_HOME}/git/${PROFILE}-config"

    log_debug "Configuring git with: ${name} <${email}>, signing_key = ${signing_key_id} \n Github user: ${github_username}"

    case "${PROFILE}" in
      private|work)
        log_debug "Configuring ${PROFILE} git profile for ${email}"

        cp "${XDG_CONFIG_HOME}/git/${PROFILE}-config.dist" "${config_path}"
        sed -i '' "s|.*email.*|	email      = ${email}|g" "${config_path}"
        sed -i '' "s|.*name.*|	name       = ${name}|g" "${config_path}"
        sed -i '' "s|.*signingkey.*|	signingkey = ${signing_key_id}|g" "${config_path}"
        return
        ;;
    esac

    git config --global user.name "${name}"
    git config --global user.email "${email}"
    git config --global user.signingkey "${signing_key_id}"
    git config --global github.user "${github_username}"
}

create_dirs() {
    local dirs=(
        "${XDG_STATE_HOME}/zsh/sessions"
    ) \
    dir

    for dir in "${!dirs[@]}"; do
        log_debug "Creating directory: ${dirs[${dir}]}"

        mkdir -p "${dirs[${dir}]}"
    done
}

get_gpg_keys() {
    local email="${1}"

    log_debug "Fetching GPG public keys for ${email}"

    gpg --list-keys --keyid-format LONG "${email}" 2>/dev/null | rg '^pub' | awk '{print $2}' | cut -d'/' -f2
}

get_gpg_secret_keys_fingerprints() {
    local email="${1}"

    log_debug "Fetching GPG secret keys for ${email}"

    gpg --list-secret-keys --keyid-format LONG "${email}" 2>/dev/null | rg -A 1 '^sec' | rg '[0-9A-F]{40}' | xargs
}

get_gpg_public_key_string() {
    local signing_key_id="${1}"

    echo "${USER} $(gpg --export-ssh-key "${signing_key_id}" 2>/dev/null)"
}

delete_gpg_entries() {
    local email="${1}" \
          signing_key_id

    log_warning "Deleting GPG entries for: ${email}"

    signing_key_id="$(get_gpg_keys "${email}")"

    rg -v "$(get_gpg_public_key_string "${signing_key_id}")" ~/.ssh/allowed_singers | sponge ~/.ssh/allowed_singers
    rg -v "${signing_key_id}" "${ZDOTDIR}/local/keychain.zsh" | sponge "${ZDOTDIR}/local/keychain.zsh"

    # Secret keys should be deleted first.
    get_gpg_secret_keys_fingerprints "${email}" | xargs gpg --batch --delete-secret-keys --yes
    echo "${signing_key_id}" | xargs gpg --batch --delete-keys --yes
}

create_gpg_agent_data_dir() {
    local gpg_agent_data_dir="${XDG_DATA_HOME}/gnupg"

    [ ! -d "${gpg_agent_data_dir}" ] && {
        mkdir -p "${gpg_agent_data_dir}"
        chmod 700 "${gpg_agent_data_dir}"
    } || return 0
}

update_pinentry_path() {
    local gpg_agent_config_file="${XDG_DATA_HOME}/gnupg/gpg-agent.conf" \
          pinentry_path

    pinentry_path="$(which pinentry-mac)"

    [ "${pinentry_path}" != "" ] && ! rg "${pinentry_path}" "${gpg_agent_config_file}" >/dev/null && {
        echo "pinentry-program ${pinentry_path}" | tee -a "${gpg_agent_config_file}" >/dev/null
        killall gpg-agent
    }
}

create_gpg_key() {
    local email="${1}" \
          name="${2}" \
          pass_phrase="${3}"

    log_info "Creating GPG key for: ${name} <${email}>"

    create_gpg_agent_data_dir
    update_pinentry_path

    local key_id
    key_id="$(get_gpg_keys "${email}" | head -n 1)"

    [ "${FORCE_REINSTALL}" == "true" ] || [ -z "${key_id}" ] && {
        delete_gpg_entries "${email}"

        log_debug "Creating batch GPG key for: ${name} <${email}>"

#       export GNUPGHOME="$(mktemp -d)" # for debugging - setting gpg home to different location.
        # https://www.gnupg.org/documentation/manuals/gnupg/Unattended-GPG-key-generation.html
        gpg --batch --expert --generate-key -q <<eoGpgKeyParmas
            %echo "Generating ECC keys (auth, sign & encr) with no-expiry"
            Key-Type: EDDSA
            Key-Curve: ed25519
            Key-Usage: auth,sign
            Subkey-Type: ECDH
            Subkey-Curve: cv25519
            Subkey-Usage: encrypt
            Name-Comment: Git User
            Name-Email: ${email}
            Name-Real: ${name}
            Expire-Date: 0
            Passphrase: ${pass_phrase}
            # Do a commit here, so that we can later print "done" :-)
            %commit
            %echo done
eoGpgKeyParmas

        key_id="$(get_gpg_keys "${email}" | head -n 1)"
    } || {
        log_info "GPG key ${key_id} already exists for email: ${email}"
    }

    echo "${key_id}"
}

create_ssh_key() {
    local key_file="${1}" \
          key_type="${2}" \
          pass_phrase="${3}" \
          email="${4}"

    log_debug "Creating SSH key: ${key_file}"

    # https://stackoverflow.com/questions/43235179/how-to-execute-ssh-keygen-without-prompt
    ssh-keygen -f ~/.ssh/"${key_file}" -t "${key_type}" -N "${pass_phrase}" -C "${email}" -q <<<y >/dev/null 2>&1
}

create_ssh_keys() {
    local email="${1}" \
          pass_phrase="${2}"

    log_info "Generating SSH keys for ${email}..."

    local keys=(
        "ed25519"
        "rsa"
    ) \
    key \
    key_file \
    public_key_string

    for key in "${!keys[@]}"; do
        key_file="id_${keys[${key}]}"

        [ "${FORCE_REINSTALL}" == "true" ] || [ ! -f ~/.ssh/"${key_file}" ] && {
            create_ssh_key "${key_file}" "${keys[${key}]}" "${pass_phrase}" "${email}"

            continue
        }

        log_debug "SSH key ${key_file} already exists and FORCE_REINSTALL is not true. Skipping."
    done
}

configure_ssh_keys() {
    local signing_key_id="${1}"

    log_info "Configuring SSH keys..."

    [ "${FORCE_REINSTALL}" == "true" ] && {
        echo "" >| ~/.ssh/allowed_singers
    }

    local keys=(
        "ed25519"
        "rsa"
    ) \
    key \
    key_file \
    public_key_string

    for key in "${!keys[@]}"; do
        key_file="id_${keys[${key}]}"
        public_key_string="$(cat "${HOME}/.ssh/${key_file}.pub")"

        [ "${FORCE_REINSTALL}" == "true" ] || ! rg -F "${public_key_string}" ~/.ssh/allowed_singers >/dev/null && {
            echo "${USER} $(cat "${HOME}/.ssh/${key_file}.pub")" | tee -a ~/.ssh/allowed_singers

            continue
        }

        log_notice "SSH key ${key_file} does not exist or FORCE_REINSTALL is not true. Skipping."
    done

    if [ -z "${signing_key_id}" ]
    then
        abort "Empty signing key id."
    fi

    log_info "Exporting GPG key ${signing_key_id} as SSH key."

    public_key_string="$(get_gpg_public_key_string "${signing_key_id}")"

    ! rg -F "${public_key_string}" ~/.ssh/allowed_singers >/dev/null && {
        echo "${public_key_string}" | tee -a ~/.ssh/allowed_singers
    } || return 0
}

configure_keychain() {
    local signing_key_id="${1}"

    [ "${FORCE_REINSTALL}" == "true" ] || [ ! -f "${ZDOTDIR}/local/keychain.zsh" ] && {
        printf '%b' '#!/usr/bin/env zsh\n\n' >| "${ZDOTDIR}/local/keychain.zsh"
    }

    ! rg -F "${signing_key_id}" "${ZDOTDIR}/local/keychain.zsh" >/dev/null && {
        printf '%b' "keychain --eval --agents gpg ${signing_key_id} >/dev/null 2>&1\n" >> "${ZDOTDIR}/local/keychain.zsh"
    } || return 0

}

declare_global_vars() {
    : "${XDG_CONFIG_HOME:=${HOME}/.config}"
    : "${XDG_DATA_HOME:=${HOME}/.local/share}"
    : "${XDG_STATE_HOME:=${HOME}/.local/state}"

    : "${ZDOTDIR:=${XDG_CONFIG_HOME}/zsh}"

    : "${GNUPGHOME="${XDG_DATA_HOME}/gnupg"}"

    export GNUPGHOME
}

install_brew() {
    log_info "Installing Homebrew for you."

    # @see: scripts/common.sh
    if [ "${FORCE_REINSTALL}" == "true" ] || ! is_command brew > /dev/null 2>&1
    then
        bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        eval "$(/opt/homebrew/bin/brew shellenv)"
        sudo chmod 755 /opt/homebrew/share

        return 0
    fi

    log_notice "Homebrew is already installed."
}

install_brew_deps() {
    log_info "Installing brew dependencies."

    local opts=(
        "--file" "./stow/.config/homebrew/Brewfile"
    )

    if [ "${FORCE_REINSTALL}" == "true" ]
    then
        opts+=("-f")
    fi

    brew up
    brew upgrade
    brew bundle "${opts[@]}" || return 0
}

install_nix() {
    log_info "Installing nix."

    if [ "${FORCE_REINSTALL}" == "true" ] || [ ! -x /nix/var/nix/profiles/default/bin/nix ]
    then
        curl -L https://nixos.org/nix/install | sh

        return 0
   fi

   log_debug "Nix OS is already installed!"
}

install_nix_darwin() {
    install_nix

    log_info "Installing nix_darwin."

    if [ -x /nix/var/nix/profiles/default/bin/nix ]
    then
        /nix/var/nix/profiles/default/bin/nix run nix-darwin -- switch --flake "./stow/.config/nix-darwin" --impure

        return 0
    fi

    abort "Nix OS is not installed!"
#    darwin-rebuild switch --flake "./stow/.config/nix-darwin"
}

install_theme() {
    local themes_url="${1}" \
          target_dir="${2}" \
          src_dir="${3:-themes}"

    log_debug "Installing themes to ${target_dir}"

    [ "${FORCE_REINSTALL}" == "true" ] || [ ! "$(ls -A "${target_dir}" 2>/dev/null)" ] && {
        local temp_dir
        temp_dir="$(mktemp -d)"

        log_debug "Cloning ${themes_url}"

        git clone --depth 1 --filter=blob:none --sparse "${themes_url}" "${temp_dir}" || {
            abort "Failed to clone the theme."
        }

        cd "${temp_dir}"
            git sparse-checkout set "${src_dir}"

            mkdir -p "${target_dir}"

            log_debug "Synchronizing to ${target_dir}"

            rsync -arv --exclude='*.md' --exclude='assets' --exclude='license' --remove-source-files "${temp_dir}/${src_dir}"/* "${target_dir}"
        cd -

        cleanup_list+=("${temp_dir}")
    } || return 0
}

install_bat_themes() {
    log_info "Installing bat themes."

    install_theme "https://github.com/catppuccin/bat.git" "$(bat --config-dir)/themes"

    {
        bat cache --build
        bat --list-themes
        bat "$(bat --config-file)"
    } 2>/dev/null
}

install_bottom_themes() {
    log_info "Installing bottom themes."

    install_theme "https://github.com/catppuccin/bottom.git" "${XDG_CONFIG_HOME}/bottom/themes"
}

install_btop_themes() {
    log_info "Installing btop themes."

    install_theme "https://github.com/catppuccin/btop.git" "${XDG_CONFIG_HOME}/btop/themes"
    install_theme "https://github.com/rose-pine/btop.git" "${XDG_CONFIG_HOME}/btop/themes" "."
}

install_k9s_themes() {
    log_info "Installing k9s themes."

    install_theme "https://github.com/catppuccin/k9s.git" "${XDG_CONFIG_HOME}/k9s/skins" "dist"
}

install_lazygit_themes() {
    log_info "Installing lazygit themes."

    install_theme "https://github.com/catppuccin/lazygit.git" "${XDG_CONFIG_HOME}/lazygit/themes"
}

install_warp_themes() {
    log_info "Installing warp themes."

    install_theme "https://github.com/catppuccin/warp.git" "${HOME}/.warp/themes"
    install_theme "https://github.com/thanhsonng/rose-pine-warp.git" "${HOME}/.warp/themes" "."
}

install_yazi_themes() {
    log_info "Installing yazi themes."

    install_theme "https://github.com/catppuccin/yazi.git" "${XDG_CONFIG_HOME}/yazi/themes"
}

install_zsh_fast_syntax_highlighting_themes() {
    log_info "Installing zsh_fast_syntax_highlighting themes."

    install_theme "https://github.com/catppuccin/zsh-fsh.git" "${XDG_CONFIG_HOME}/fsh"

    zsh -c 'source ${HOME}/.zshenv && fast-theme XDG:catppuccin-mocha 2>/dev/null' || return 0
}

install_apps_themes() {
    install_bat_themes
    install_bottom_themes
    install_btop_themes
    install_k9s_themes
    install_lazygit_themes
    install_warp_themes
    install_yazi_themes
    install_zsh_fast_syntax_highlighting_themes
}

set_wallpapers() {
    local wallpapers_dir="${1}"

    if [ ! -d "${wallpapers_dir}" ]; then
        log_warning "Directory ${wallpapers_dir} does not exist."

        return 0
    fi

    local wallpaper
    wallpaper="$(fd -e bmp -e gif -e jpg -e jpeg -e png . "${wallpapers_dir}" | shuf -n 1)"
    if [ -f "${wallpaper}" ]; then
#         osascript -e "tell application \"Finder\" to set desktop picture to POSIX file \"${wallpaper}\""
         osascript -e "tell application \"System Events\" to set picture of every desktop to POSIX file \"${wallpaper}\""
         log_info "Wallpaper is set to ${wallpaper}."
    fi

    open "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension"
#    osascript <<EOF
#        tell application "System Preferences"
#            activate
#            reveal pane id "com.apple.Wallpaper-Settings.extension"
#        end tell
#EOF
}

start_services() {
    skhd --start-service
    yabai --start-service
}

stow_config() {
    local dir="${1}"

    case "${dir}" in
      ./*)
        # Removing the ./ from the beginning, as it would be rejected by the stow command.
        dir="${dir:2}"
        ;;
    esac

    log_info "Stowing files under ${dir} directory."

    stow --adopt "${dir}"
}

update_submodules() {
    git submodule update --init --rebase
}

usage() {
    local this="${1}"

    cat <<HELP
${this}: install Mac software for the first time
Usage: ${this} [-e] environment file path [-h] help [-l] log level [-x] verbose mode
    -e sets the environment file path.
    -h to get help about the usage.
    -l sets the log priority: 2 => critical, 3 => error, 6 => info, 7 => debug.
    -x to see the executed statements.
HELP

    exit 0
}

parse_args() {
    ENV_FILE="${ENV_FILE:-.env}"

    local arg
    while getopts "e:l:p:h?x" arg; do
        case "${arg}" in
            e) ENV_FILE="${OPTARG}" ;;
            l) LOG_LEVEL="${OPTARG}" ;;
            p) PROFILE="${OPTARG}" ;;
            h | \?) usage "${0}" ;;
            x) set -x ;;
        esac
    done
    shift $((OPTIND - 1))

    LOG_LEVEL="${LOG_LEVEL:-${_log_level}}"

    _log_level=$((LOG_LEVEL))
}

script_cleanup() {
    eval "$(/opt/homebrew/bin/brew shellenv)"
    brew cleanup

    [ ${#cleanup_list[@]} -gt 0 ] && {
        local item
        for item in "${cleanup_list[@]}"; do
            log_notice "Deleting directory ${item}"
            rm -rf "${item}"
        done
    } || return 0
}

at_exit() {
    local signal="${1}" \
          ret="$?"

    script_cleanup

    case "${signal}" in
      INT | TERM | QUIT)
        log_critical "\n🦇 Bat luck out there!\n😥 Try hard next time."
        exit_status=1
        ;;
      EXIT)
        [ "${ret}" == 0 ] && {
            log_info "\n✨ Congratulations, you can now chillax!\n😎 May the odds be in your favour."
        }
        ;;
    esac

    ring_bell

    exit "${exit_status}"
}

trap_with_arg() {
    local callback="${1}"

    shift

    for signal in "$@"; do
        # shellcheck disable=SC2064
        trap "${callback} ${signal}" "${signal}"
    done
}

validate_args() {
    [ -z "${ENV_FILE+x}" ] && abort 'Missing -e {{ENV_FILE}}' || return 0
}

prepare() {
    # @see: scripts/common.sh
    validate_bash
    trap_with_arg at_exit EXIT INT QUIT TERM

    parse_args "$@"
    validate_args

    # @see: scripts/common.sh
    include_env_vars "${ENV_FILE}"
    declare_global_vars

    create_dirs
}

install() {
    install_brew
    install_brew_deps

    # Stowing is necessary here, for bat theme config file.
    stow_config "./stow"

    install_apps_themes
    install_nix_darwin

    update_submodules
}

create() {
    # shellcheck disable=SC2153
    create_ssh_keys "${GIT_EMAIL}" "${PASS_PHRASE}"
    create_gpg_key "${GIT_EMAIL}" "${GIT_USER}" "${PASS_PHRASE}"
}

configure() {
    local signing_key_id="${1}"

    # shellcheck disable=SC2153
    configure_ssh_keys "${signing_key_id}"
    # shellcheck disable=SC2153
    configure_git "${GIT_EMAIL}" "${GIT_USER}" "${signing_key_id}" "${GITHUB_USERNAME}"

    configure_keychain "${signing_key_id}"
}

main() {
    prepare "$@"
    install

    {
        read -r signing_key_id
    } <<< "$(create)"

    configure "${signing_key_id}"

    start_services

    set_wallpapers "$(realpath "./wallpapers")"
}

main "$@"
