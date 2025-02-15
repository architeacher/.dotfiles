# :bookmark_tabs:

```text
     __          __       ___      ___
    /\ \        /\ \__  /'___\ __ /\_ \
    \_\ \    ___\ \ ,_\/\ \__//\_\\//\ \      __    ____
    /'_` \  / __`\ \ \/\ \ ,__\/\ \ \ \ \   /'__`\ /',__\
 __/\ \L\ \/\ \L\ \ \ \_\ \ \_/\ \ \ \_\ \_/\  __//\__, `\
/\_\ \___,_\ \____/\ \__\\ \_\  \ \_\/\____\ \____\/\____/
\/_/\/__,_ /\/___/  \/__/ \/_/   \/_/\/____/\/____/\/___/
```

### Spice up your Mac

Please follow these instructions to set up your Mac.

1. Run the following command to download the .dotfiles repo
   ```bash
   curl https://raw.githubusercontent.com/architeacher/.dotfiles/HEAD/scripts/download.sh | bash
   ```

2. Prerequisites
    We will use `make` for the installation to get help

   ```bash
   cd .dotfiles
   make
   ```
   This will provide help about the available targets.

3. Environment variables
   To create the `.env` file with variables that will be used in the installation, please run
   ```bash
   make .env
   ```

    This command will generate a `.env` file, that you can edit for your git username and email, it should look like this.
    ```dotenv
    # Installer
    FORCE_REINSTALL=false

    # Git
    GIT_EMAIL="john.doe@foo.bar"
    GIT_USER="John Doe"

    # Github
    GITHUB_USERNAME="johndoe"

    # Sginging Keys - make sure to escape $, in case of any.
    PASS_PHRASE="bottom.secret"

    # Installation profiles
    # The values can be one the following:
    # - private
    # - work
    PROFILE=""
    ```

4. Installation
    Please check
    * [Brew](https://github.com/architeacher/.dotfiles/blob/main/stow/.config/homebrew/Brewfile "Brew file") file to select the software to install.
    * [.config](https://github.com/architeacher/.dotfiles/blob/main/stow/.config "Software config files") directory for the installed software that would be sym linked under `XDG_CONFIG_HOME:=~/.config` using GNU [Stow](https://www.gnu.org/software/stow/ "GNU Stow").

    To install, please run
    ```bash
    make install
    ```
## Feedback

Suggestions/improvements are
[welcome](https://github.com/architeacher/.dotfiles/issues)!


## Thanks to…

* [AhmedSoliman](https://github.com/AhmedSoliman "Ahmed Farghal") and his [dotfiles repository](https://github.com/AhmedSoliman/dotfiles)
* [omerxx](https://github.com/omerxx "Omer Hamerman") and his [dotfiles repository](https://github.com/omerxx/dotfiles)
* [ThePrimeagen](https://github.com/ThePrimeagen "ThePrimeagen") and his [dotfiles repository](https://github.com/ThePrimeagen/.dotfiles)
* [renemarc](https://github.com/renemarc "René-Marc Simard") and his [dotfiles repository](https://github.com/renemarc/dotfiles)
* [voku](https://github.com/voku "Lars Moelleken") and his [dotfiles repository](https://github.com/voku/dotfiles)
* Anyone who [contributed a patch](https://github.com/architeacher/.dotfiles/contributors).

Thanks geeks 🚀
