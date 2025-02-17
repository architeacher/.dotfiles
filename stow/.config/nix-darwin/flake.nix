{
    description = "My Darwin system flake";

    inputs = {
        flake-schemas.url = "github:DeterminateSystems/flake-schemas";

        nixos.url            = "github:NixOS/nixpkgs/nixos-24.05";
        nixos-stable-lib.url = "github:NixOS/nixpkgs/nixos-24.05?dir=lib"; # "github:nix-community/nixpkgs.lib" doesn't work
        nixos-unstable.url   = "github:NixOS/nixpkgs/nixos-unstable";

        nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-24.05-darwin";

        nix-darwin = {
            url = "github:LnL7/nix-darwin";

            # You can access packages and modules from different nixpkgs revs at the same time.
            inputs.nixpkgs.follows = "nixpkgs-darwin";
        };

        home-manager = {
            url = "github:nix-community/home-manager/release-24.05";
            inputs.nixpkgs.follows = "nixos-stable-lib"; # not needed by NixOS' module thanks to `home-manager.useGlobalPkgs = true` but needed by the unprivileged module.
        };
    };

    outputs = inputs @ { self, nix-darwin, nixpkgs, home-manager, ... }:
    let
        inherit (nix-darwin.lib) darwinSystem;

        configuration = { pkgs, ... }: {
            # List packages installed in system profile. To search by name, run:
            # $ nix-env -qaP | grep wget
            environment.systemPackages = [
                    pkgs.age
                    pkgs.direnv
                    pkgs.portal
                    pkgs.sshs
                    pkgs.termshark
                    pkgs.vim
                ];
            home-manager.backupFileExtension = "backup";
            nix.configureBuildUsers = true;

            # Necessary for using flakes on this system.
            nix.settings.experimental-features = "nix-command flakes";
            nix.useDaemon = true;

             # The platform the configuration will be used on.
            nixpkgs.hostPlatform = "aarch64-darwin";

            # Create /etc/zshrc that loads the nix-darwin environment.
            programs.zsh.enable = true;  # default shell on catalina
            security.pam.enableSudoTouchIdAuth = true;

            # Auto upgrade nix package and the daemon service.
            services.nix-daemon.enable = true;

            # Set Git commit hash for darwin-version.
            system.configurationRevision = self.rev or self.dirtyRev or null;

            # Used for backwards compatibility, please read the changelog before changing.
            # $ darwin-rebuild changelog
            system.stateVersion = 4;

            system.defaults = {
                dock.autohide                   = true;
                dock.mru-spaces                 = false;
                finder.AppleShowAllExtensions   = true;
                finder.FXPreferredViewStyle     = "clmv";
                loginwindow.LoginwindowText     = "Architeacher-Portal";
                screencapture.location          = "/Users/architeacher/Pictures/screenshots";
                screensaver.askForPasswordDelay = 10;
            };

            users.users.architeacher.home = "/Users/architeacher";

            # Homebrew needs to be installed on its own!
            homebrew.enable = true;
            homebrew.brews = [
                "tree"
            ];
            homebrew.casks = [
                "whatsapp"
            ];
        };
    in
    {
        darwinConfigurations."Ahmeds-MacBook-Pro" = darwinSystem {
            system = "aarch64-darwin";

            specialArgs = { inherit inputs self; };

            modules = [
	            configuration
                home-manager.darwinModules.home-manager {
                    home-manager.useGlobalPkgs      = true;
                    home-manager.useUserPackages    = true;
                    home-manager.users.architeacher = import ./home.nix;
                }
            ];
        };

        # Expose the package set, including overlays, for convenience.
        darwinPackages = self.darwinConfigurations."Ahmeds-MacBook-Pro".pkgs;
    };
}
