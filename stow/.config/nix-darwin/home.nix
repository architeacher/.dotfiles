# home.nix
# home-manager switch

{ config, pkgs, ... }:

{
    home = {
        username = "ahmed";
        homeDirectory = "/Users/ahmed";
    };

    # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
    home.stateVersion = "24.05"; # Please read the comment before changing.

    # Makes sense for user specific applications that shouldn't be available system-wide
    home.packages = [
    ];

    # Home Manager is pretty good at managing dotfiles. The primary way to manage
    # plain files is through 'home.file'.
    home.file = {
        # ".config/nix-darwin".source = /Users/ahmed/.dotfiles/stow/.config/nix-darwin;
    };

    home.sessionVariables = {
    };

    home.sessionPath = [
    "/run/current-system/sw/bin"
        "$HOME/.nix-profile/bin"
    ];

    nixpkgs = {
        # Configure your nixpkgs instance
        config = {
            # Disable if you don't want unfree packages
            allowUnfree = true;
        };
    };

    programs.home-manager.enable = true;
    programs.zsh = {
        initExtra = ''
            # Add any additional configurations here
            export PATH=/run/current-system/sw/bin:$HOME/.nix-profile/bin:$PATH
            if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
                . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
            fi
        '';
    };
}
