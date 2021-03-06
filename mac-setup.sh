#!/bin/bash

# Bail on any errors
set -e

tty_bold=`tput bold`
tty_normal=`tput sgr0`

# The directory to which all repositories will be cloned.
ROOT=${1-$HOME}
REPOS_DIR="$ROOT/khan"

# Derived path location constants
DEVTOOLS_DIR="$REPOS_DIR/devtools"

# Load shared setup functions.
. "$DEVTOOLS_DIR"/khan-dotfiles/shared-functions.sh

# for printing standard echoish messages
notice () {
    printf "         $1\n"
}

# for printing logging messages that *may* be replaced by
# a success/warn/error message
info () {
    printf "  [ \033[00;34m..\033[0m ] $1"
}

# for printing prompts that expect user input and will be
# replaced by a success/warn/error message
user () {
    printf "\r  [ \033[0;33m??\033[0m ] $1 "
}

# for replacing previous input prompts with success messages
success () {
    printf "\r\033[2K  [ \033[00;32mOK\033[0m ] $1\n"
}

# for replacing previous input prompts with warnings
warn () {
    printf "\r\033[2K  [\033[0;33mWARN\033[0m] $1\n"
}

# for replacing previous prompts with errors
error () {
    printf "\r\033[2K  [\033[0;31mFAIL\033[0m] $1\n"
}

trap exit_warning EXIT   # from shared-functions.sh


update_path() {
    # We need /usr/local/bin to come before /usr/bin on the path, to
    # pick up brew files we install.  To do this, we just source
    # .profile.khan, which does this for us (and the new user).
    # (This assumes you're running mac-setup.sh from the khan-dotfiles
    # directory.)
    . .profile.khan
}

maybe_generate_ssh_keys () {
  # Create a public key if need be.
  info "Checking for ssh keys"
  mkdir -p ~/.ssh
  if [ -s ~/.ssh/id_rsa ] || [ -s ~/.ssh/id_dsa ]
  then
    success "Found existing ssh keys"
  else
    ssh-keygen -q -N "" -t rsa -f ~/.ssh/id_rsa
    success "Generated an rsa ssh key at ~/.ssh/id_rsa"
  fi
  return 0
}

copy_ssh_key () {
  if [ -e ~/.ssh/id_rsa ]
  then
    pbcopy < ~/.ssh/id_rsa.pub
  elif [ -e ~/.ssh/id_dsa ]
  then
    pbcopy < ~/.ssh/id_dsa.pub
  else
    error "no ssh public keys found"
    exit
  fi
}

register_ssh_keys() {
    success "Registering your ssh keys with github\n"
    verify_ssh_auth
}

# checks to see that ssh keys are registered with github
# $1: "true"|"false" to end the auth cycle
verify_ssh_auth () {
    ssh_host="git@github.com"
    webpage_url="https://github.com/settings/ssh"
    instruction="Click 'Add SSH Key', paste into the box, and hit 'Add key'"

    info "Checking for GitHub ssh auth"
    if ! ssh -T -v $ssh_host 2>&1 >/dev/null | grep \
        -q -e "Authentication succeeded (publickey)"
    then
        if [ "$2" == "false" ]  # error if auth fails twice in a row
        then
            error "Still no luck with GitHub ssh auth. Ask a dev!"
            ssh_auth_loop $webpage_url "false"
        else
            # otherwise prompt to upload keys
            success "GitHub's ssh auth didn't seem to work\n"
            notice "Let's add your public key to GitHub"
            info "${tty_bold}${instruction}${tty_normal}\n"
            ssh_auth_loop $webpage_url "true"
        fi
    else
        success "GitHub ssh auth succeeded!"
    fi
}

ssh_auth_loop() {
    # a convenience function which lets you copy your public key to your clipboard
    # open the webpage for the site you're pasting the key into or just bailing
    # $1 = ssh key registration url
    service_url=$1
    first_run=$2
    if [ "$first_run" == "true" ]
    then
        notice "1. hit ${tty_bold}o${tty_normal} to open GitHub on the web"
        notice "2. hit ${tty_bold}c${tty_normal} to copy your public key to your clipboard"
        notice "3. hit ${tty_bold}t${tty_normal} to test ssh auth for GitHub"
        notice "☢. hit ${tty_bold}s${tty_normal} to skip ssh setup for GitHub"
        ssh_auth_loop $1 "false"
    else
        user "o|c|t|s) "
        read -n1 ssh_option
        case $ssh_option in
            o|O )
                success "opening GitHub's webpage to register your key!"
                open $service_url
                ssh_auth_loop $service_url "false"
                ;;
            c|C )
                success "copying your ssh key to your clipboard"
                copy_ssh_key
                ssh_auth_loop $service_url "false"
                ;;
            t|T )
                printf "\r"
                verify_ssh_auth "false"
                ;;
            s|S )
                warn "skipping GitHub ssh registration"
                ;;
        esac
    fi
}

install_gcc() {
    info "\nChecking for Apple command line developer tools..."
    if ! gcc --version >/dev/null 2>&1 || [ ! -s /usr/include/stdio.h ]; then
        if sw_vers -productVersion | grep -e '^10\.[0-8]$' -e '^10\.[0-8]\.'; then
            warn "Command line tools are *probably available* for your Mac's OS, but..."
            info "why not upgrade your OS right now?\n"
            info "Otherwise, you can always visit developer.apple.com and grab 'em there.\n"
            exit 1
        fi
        if ! gcc --version >/dev/null 2>&1 ; then
            success "Installing command line developer tools"
            # If enter is pressed before its done, not a big deal, but it'll just loop to the same place.
            success "You'll want to wait until the xcode install is complete to press Enter again."
            # Also, how did you get this dotfiles repo in 10.9 without
            # git auto-triggering the command line tools install process??
            xcode-select --install
            exec sh ./mac-setup.sh
            # If this doesn't work for you, you can find the most recent
            # version here: https://developer.apple.com/downloads
        fi
        if sw_vers -productVersion | grep -q -e '^10\.14\.' && [ ! -s /usr/include/stdio.h ]; then
            # mac version is Mojave 10.14.*, install SDK headers
            # The file "macOS_SDK_headers_for_macOS_10.14.pkg" is from
            # xcode command line tools install
            if [ -s /Library/Developer/CommandLineTools/Packages/macOS_SDK_headers_for_macOS_10.14.pkg ]; then
                # This command isn't guaranteed to work. If it fails, just warn
                # the user there may be problems and advise they contact 
                # @dev-support if so.
                if sudo installer -pkg /Library/Developer/CommandLineTools/Packages/macOS_SDK_headers_for_macOS_10.14.pkg -target / ; then
                    success "macOS_SDK_headers_for_macOS_10.14 installed"
                else
                    warn "We're not able to determine if stdio.h is able to be used by compilers correctly on your system."
                    warn "Please reach out to @dev-support if you encounter errors indicating this is a problem while building code or dependencies."
                    warn "You may be able to get more information about the setup by running ${tty_bold}gcc -v${tty_normal}"
                fi
            else
                success "Updating your command line tools"
                # If enter is pressed before its done, not a big deal, but it'll just loop to the same place.
                success "You'll want to wait until the xcode install is complete to press Enter again."
                sudo rm -rf /Library/Developer/CommandLineTools
                xcode-select --install
                exec sh ./mac-setup.sh
            fi
        fi
    else
        success "Great, found gcc! (assuming we also have other recent devtools)"
    fi
}

install_slack() {
    info "Checking for Slack..."
    if ! open -R -g -a Slack > /dev/null; then
        success "Didn't find Slack."
        info "Installing Slack to ~/Applications\n"
        brew cask install slack
    else
        success "Great! Slack already installed!"
    fi
}

install_homebrew() {
    info "Checking for mac homebrew"
    # If homebrew is already installed, don't do it again.
    if ! brew --help >/dev/null 2>&1; then
        success "Brew not found. Installing!"
        ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    else
        success "Great! Mac homebrew already installed!"
        info "Verifying homebrew is in a good state...\n"
        if ! brew doctor; then
            warn "Oh no! 'brew doctor' reported some warnings."
            info "These warnings may cause you trouble, but they are likely harmless.\n"
            read -r -p "Onward? [Y/n] " response
            case "$response" in
                [nN][oO]|[nN])
                    exit 1
                    ;;
            esac
        fi
    fi
    success "Updating (but not upgrading) Homebrew"
    brew update > /dev/null

    # Required to install chrome-canary
    brew tap homebrew/cask-versions

    # Make sure everything is ok.  We don't care if we're using an
    # obsolete gcc, so instead of looking at the exit code for 'brew
    # doctor', we look at its output.  The last 'grep', combined with
    # the ! at the beginning of this command, causes the overall
    # command to fail -- and thus the script to exit -- if brew doctor
    # has any errors or warnings after we grep out the stuff we don't
    # care about.
    ## Commented out for now: too many legit setups have warnings (cf chris).
    ## ! brew doctor 2>&1 \
    ##     | grep -v -e 'A newer Command Line Tools' \
    ##     | grep -v -e 'Your Homebrew is not installed to /usr/local' \
    ##     | grep -C1000 -e ^Error -e ^Warning
}

update_git() {
    if ! git --version | grep -q -e 'version 2\.[2-9][0-9]\.'; then
        echo "Installing an updated version of git using Homebrew"
        echo "Current version is `git --version`"

        if brew ls git >/dev/null 2>&1; then
            # If git is already installed via brew, update it
            brew upgrade git || true
        else
            # Otherwise, install via brew
            brew install git || true
        fi

        # Check git version again
        if ! git --version | grep -q -e 'version 2\.[2-9][0-9]\.'; then
            if ! brew ls --versions git | grep -q -e 'git 2\.[2-9][0-9]\.' ; then
                echo "Error installing git via brew; download and install manually via http://git-scm.com/download/mac. "
                read -p "Press enter to continue..."
            else 
                echo "Git has been updated correctly, but will require restarting your terminal to take effect."
            fi
        fi
    fi
}

install_node() {
    if ! which node >/dev/null 2>&1; then
        # Install node 10: webapp doesn't (yet!) work with node 12.
        # (Node 10 is LTS.)
        brew install node@10

        # We need this because brew doesn't link /usr/local/bin/node
        # by default when installing non-latest node.
        brew link --force --overwrite node@10
    fi
    # We don't want to force usage of node v10, but we want to make clear we don't support it
    if ! node --version | grep "v10" >/dev/null ; then 
        notice "Your version of node is $(node --version). We currently only support v10."
        if brew ls --versions node@10 >/dev/null ; then
            notice "You do however have node 10 installed."
            notice "Consider running:"
        else
            notice "Consider running:"
            notice "\t${tty_bold}brew install node@10${tty_normal}"
        fi
        notice "\t${tty_bold}brew link --force --overwrite node@10${tty_normal}"
        read -p "Press enter to continue..."
    fi
    if ! which yarn >/dev/null 2>&1; then
        # Using brew to install node 10 seems to prevent npm from
        # correctly installing yarn. Use brew instead
        brew install yarn
    fi
}

install_go() {
    if ! has_recent_go; then   # has_recent_go is from shared-functions.sh
        info "Installing go\n"
        if brew ls go >/dev/null 2>&1; then
            brew upgrade "go@$DESIRED_GO_VERSION"
        else
            brew install "go@$DESIRED_GO_VERSION"
        fi

        # Brew doesn't link non-latest versions of go on install. This command
        # fixes that, telling the system that this is the go executable to use
        brew link --force --overwrite "go@$DESIRED_GO_VERSION"
    else
        success "go already installed"
    fi
}

# Gets the name brew uses to refer to postgresql 11, or NONE if not isntalled
recent_postgresql_brewname() {
    if brew ls postgresql@11 >/dev/null 2>&1 ; then
        echo "postgresql@11"
    elif brew ls postgresql --versions >/dev/null 2>&1 | grep "\s11\.\d" ; then
        echo "postgresql"
    else
        echo "NONE"
    fi
}

install_postgresql() {
    pg11_brewname="$(recent_postgresql_brewname)"
    if [ "$pg11_brewname" = "NONE" ] ; then
        info "Installing postgresql\n"
        brew install postgresql@11
        # swtich icu4c to 64.2
        # if default verison is 63.x and v64.2 was installed by postgres@11
        if [ "$(brew ls icu4c --versions |grep "icu4c 63")" ] && \
           [ "$(brew ls icu4c | grep 64.2 >/dev/null 2>&1)" ]; then
           brew switch icu4c 64.2
        fi

        # Brew doesn't link non-latest versions on install. This command fixes that
        # allowing postgresql and commads like psql to be found
        brew link --force --overwrite postgresql@11
        pg11_brewname="postgresql@11"
    else
        success "postgresql already installed"
    fi

    # Make sure that postgres is started, so that we can create the user below,
    # if necessary and so later steps in setup_webapp can connect to the db.
    if ! brew services list | grep "$pg11_brewname" | grep -q started; then
        info "Starting postgreql service\n"
        brew services start "$pg11_brewname" 2>&1
        # Give postgres a chance to start up before we connect to it on the next line
        sleep 5
    else
        success "postgresql service already started"
    fi

    # We create a postgres user locally that we use in test and dev.
    if ! psql \
      -tc "SELECT rolname from pg_catalog.pg_roles"  postgres \
      | grep -c 'postgres' > /dev/null 2>&1 ; then
        info "Creating postgres user for dev\n"
        psql --quiet -c "CREATE ROLE postgres LOGIN SUPERUSER;" postgres;
    else
        success "postgres user already created"
    fi
}

install_nginx() {
    info "Checking for nginx\n"
    if ! type nginx >/dev/null 2>&1; then
        info "Installing nginx\n"
        brew install nginx
    else
        success "nginx already installed"
    fi
}

install_redis() {
    info "Checking for redis\n"
    if ! type redis-cli >/dev/null 2>&1; then
        info "Installing redis\n"
        brew install redis
    else
        success "redis already installed"
    fi

    if ! brew services list | grep redis | grep -q started; then
        info "Starting redis service\n"
        brew services start redis 2>&1
    else
        success "redis service already started"
    fi
}

install_image_utils() {
    info "Checking for imagemagick\n"
    if ! brew ls imagemagick >/dev/null 2>&1; then
        info "Installing imagemagick\n"
        brew install imagemagick
    else
        success "imagemagick already installed"
    fi
}

install_helpful_tools() {
    # This installs gtimeout, among a ton of other tools, which we use
    # some in our deploy pipeline.
    if ! brew ls coreutils >/dev/null 2>&1; then
        info "Installing coreutils\n"
        brew install coreutils
    else
        success "coreutils already installed"
    fi
}

install_wget() {
    info "Checking for wget\n"
    if ! which wget  >/dev/null 2>&1; then
        info "Installing wget\n"
        brew install wget
    else
        success "wget already installed"
    fi
}

install_openssl() {
    info "Checking for openssl\n"
    if ! which openssl  >/dev/null 2>&1; then
        info "Installing openssl\n"
        brew install openssl
    else
        success "openssl already installed"
    fi
    for source in $(brew --prefix openssl)/lib/*.dylib ; do
        dest="/usr/local/lib/$(basename $source)"
        # if dest is already a symlink pointing to the correct source, skip it
        if [ -h "$dest" -a "$(readlink "$dest")" = "$source" ]; then
            :
        # else if dest already exists, warn user and skip dotfile
        elif [ -e "$dest" ]; then
            warn "Not symlinking to $dest because it already exists."
        # otherwise, verbosely symlink the file (with --force)
        else
            info "Symlinking $(basename $source) "
            ln -sfvn "$source" "$dest"
        fi
    done
}

install_protoc() {
    # If the user has a homebrew version of protobuf installed, uninstall it so
    # we can manually install our own version in /usr/local.
    if brew list | grep -q '^protobuf$'; then
        info "Uninstalling homebrew version of protobuf\n"
        brew uninstall protobuf
    fi

    # The mac and linux installation process is the same from here on out aside
    # from the platform-dependent zip archive.
    install_protoc_common https://github.com/protocolbuffers/protobuf/releases/download/v3.4.0/protoc-3.4.0-osx-x86_64.zip
}

install_python_tools() {
    # We use various python versions (e.g. internal-service)
    # and use Pyenv, pipenv as environment manager
    if ! brew ls pyenv >/dev/null 2>&1; then
        info "Installing pyenv\n"
        brew install pyenv
        # At the moment, we depend on MacOS coming with python 2.7. If that
        # stops, or we want to align the python versions with the linux
        # dotfiles more effectively, we could do it with pyenv:
        # `pyenv install 2.7.16 ; pyenv global 2.7.16`
        # Because the linux dotfiles do not yet install pyenv, holding off on
        # using pyenv to enforce python version until either that happens, or
        # MacOs stops including python 2.7 by default.
    else
        success "pyenv already installed"
    fi
}

install_watchman() {
    if ! which watchman >/dev/null 2>&1; then
        update "Installing watchman..."
        brew install watchman
    fi
}

# To install some useful mac apps.
install_mac_apps() {
  chosen_apps=() # When the user opts to install a package it will be added to this array.

  mac_apps=(
    # Browsers
    firefox firefox-developer-edition google-chrome google-chrome-canary
    # Tools
    dropbox google-drive-file-stream iterm2 virtualbox zoomus
    # Text Editors
    macvim sublime-text textmate atom
  )

  mac_apps_str="${mac_apps[@]}"
  info "We recommend installing the following apps: ${mac_apps_str}. \n\n"

  read -r -p "Would you like to install [a]ll, [n]one, or [s]ome of the apps? [a/n/s]: " input

  case "$input" in
      [aA][lL][lL] | [aA])
          chosen_apps=("${mac_apps[@]}")
          ;;
      [sS][oO][mM][eE] | [sS])
          for app in ${mac_apps[@]}; do
            if [ "$(get_yn_input "Would you like to install ${app}?" "y")" = "y" ]; then
              chosen_apps=("${chosen_apps[@]}" "${app}")
            fi
          done
          ;;
      [nN][oO][nN][eE] | [nN])
          ;;
      *)
          echo "Please choose [a]ll, [n]one, or [s]ome."
          exit 100
          ;;
  esac

  for app in ${chosen_apps[@]}; do
    if ! brew cask ls $app >/dev/null 2>&1; then
        info "$app is not installed, installing $app"
        brew cask install $app || warn "Failed to install $app, perhaps it is already installed."
    else
        success "$app already installed"
    fi
  done
}

echo
success "Running Khan Installation Script 1.2\n"

if ! sw_vers -productVersion 2>/dev/null | grep -q '10\.1[12345]\.' ; then
    warn "Warning: This is only tested up to macOS 10.15 (Catalina).\n"
    notice "If you find that this works on a newer version of macOS, "
    notice "please update this message.\n"
fi

notice "After each statement, either something will open for you to"
notice "interact with, or a script will run for you to use\n"
notice "Press enter when a download/install is completed to go to"
notice "the next step (including this one)"

if ! echo "$SHELL" | grep -q -e '/bash$' -e '/zsh$' ; then
    echo
    warn "It looks like you're using a shell other than bash or zsh!"
    notice "Other shells are not officially supported.  Most things"
    notice "should work, but dev-support help is not guaranteed."
fi

read -p "Press enter to continue..."

# Run sudo once at the beginning to get the necessary permissions.
notice "This setup script needs your password to install things as root."
sudo sh -c 'echo Thanks'

update_path
maybe_generate_ssh_keys
register_ssh_keys
install_gcc
install_homebrew
install_wget
install_openssl
install_slack
update_git
install_node
install_go
install_postgresql
install_nginx
install_redis
install_image_utils
install_helpful_tools
# We use java for our google cloud dataflow jobs that live in webapp
# (as well as in khan-linter for linting those jobs)
install_mac_java
install_protoc
install_watchman
install_mac_apps
install_python_tools

trap - EXIT
