{
  description = "virtual environments";

  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    rust-overlay.url = "github:oxalica/rust-overlay";
    myNeovimOverlay.url = "github:daveman1010221/nix-neovim";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };
  };

  outputs = { self, flake-utils, nixpkgs, rust-overlay, myNeovimOverlay, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ rust-overlay.overlays.default myNeovimOverlay.overlays.default ];
        };
      in
      with pkgs;
      {
        devShells.default = pkgs.mkShell {
          buildInputs = [
            bat
            binutils
            bubblewrap
            cacert
            clang
            deterministic-uname
            eza
            fd
            figlet
            fish
            fishPlugins.bass
            fishPlugins.bobthefish
            fishPlugins.foreign-env
            fishPlugins.grc
            fzf
            getent
            git
            grc
            iproute
            iputils
            jq
            llvmPackages_latest.bintools
            llvmPackages_latest.stdenv
            nvim-pkg
            nix
            openssl
            pkg-config
            ripgrep
            tree
            util-linux
            uutils-coreutils-noprefix
            which

            # The Rust toolchain (includes rustc, cargo, and standard library)
            rust-bin.stable.latest.default

            # Rust formatting tool
            rustfmt

            # Rust linter
            clippy
          ];

  shellHook = ''
    # Create a file that contains package sources for plugins that get sourced
    # by fish shell:

    fishPlugins='
# grc
source ${pkgs.fishPlugins.grc}/share/fish/vendor_conf.d/grc.fish
source ${pkgs.fishPlugins.grc}/share/fish/vendor_functions.d/grc.wrap.fish 

# bass
source ${pkgs.fishPlugins.bass}/share/fish/vendor_functions.d/bass.fish

# bobthefish
source ${pkgs.fishPlugins.bobthefish}/share/fish/vendor_functions.d/__bobthefish_glyphs.fish
source ${pkgs.fishPlugins.bobthefish}/share/fish/vendor_functions.d/fish_mode_prompt.fish
source ${pkgs.fishPlugins.bobthefish}/share/fish/vendor_functions.d/fish_right_prompt.fish
source ${pkgs.fishPlugins.bobthefish}/share/fish/vendor_functions.d/__bobthefish_colors.fish
source ${pkgs.fishPlugins.bobthefish}/share/fish/vendor_functions.d/fish_title.fish
source ${pkgs.fishPlugins.bobthefish}/share/fish/vendor_functions.d/__bobthefish_display_colors.fish
source ${pkgs.fishPlugins.bobthefish}/share/fish/vendor_functions.d/fish_prompt.fish
source ${pkgs.fishPlugins.bobthefish}/share/fish/vendor_functions.d/fish_greeting.fish
source ${pkgs.fishPlugins.bobthefish}/share/fish/vendor_functions.d/bobthefish_display_colors.fish

set -xg COREUTILS "${pkgs.uutils-coreutils-noprefix}"
    '
    echo "$fishPlugins" > .plugins.fish

    # The '--pure' flag to 'nix-shell' sets this variable to an invalid path
    # and it breaks SSL. The variable doesn't exist at all in an impure shell.
    # I do not know why they do this. The safest fix I've discovered is to set
    # this to a valid path.
    export NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

    export ARG_MAX=2097152

    # Accumulate all ro_bind_options, collected from the various package derivations.
    all_ro_bind_options=""

    # The derivations for all packages listed here will be expanded and added
    # to the set of read-only bind mounts for the bubble wrap sandbox.
    # Additionally, we will try to use this to add items to the PATH.

    package_paths=(
        "${pkgs.bat}"
        "${pkgs.binutils}"
        "${pkgs.bubblewrap}"
        "${pkgs.cacert}"
        "${pkgs.clang}"
        "${pkgs.deterministic-uname}"
        "${pkgs.eza}"
        "${pkgs.fd}"
        "${pkgs.figlet}"
        "${pkgs.fish}"
        "${pkgs.fishPlugins.bass}"
        "${pkgs.fishPlugins.bobthefish}"
        "${pkgs.fishPlugins.foreign-env}"
        "${pkgs.fishPlugins.grc}"
        "${pkgs.fzf}"
        "${pkgs.getent}"
        "${pkgs.git}"
        "${pkgs.grc}"
        "${pkgs.iproute}"
        "${pkgs.iputils}"
        "${pkgs.jq}"
        "${pkgs.llvmPackages_latest.bintools}"
        "${pkgs.llvmPackages_latest.stdenv}"
        "${pkgs.lolcat}"
        "${pkgs.nix}"
        "${nvim-pkg}"
        "${pkgs.openssl}"
        "${pkgs.ripgrep}"
        "${pkgs.rust-bin.stable.latest.default}"
        "${pkgs.tree}"
        "${pkgs.util-linux}"
        "${pkgs.uutils-coreutils-noprefix}"
        "${pkgs.which}"
    )

    # This newPath will be used as PATH in the sandbox.
    fullPath=""

    # Generate --ro-bind options for a given package
    generate_ro_bind_options() {
      local package_path="$1"
      local ro_bind_options=""

      # Query the requisites of a given package and generate ro_bind options.
      # Note that this isn't 'pure', unless you pin your package versions,
      # which is probably a good idea, but maybe not initially.
      for path in $(nix-store --query --requisites "$package_path"); do
        ro_bind_options+="--ro-bind $path $path "
      done

      echo "$ro_bind_options"
    }

    # Generate path arguments for a given package
    generate_new_path() {
      local package_path="$1"

      for path in $(nix-store --query --requisites "$package_path"); do
        # Use the package paths to build the newPath.
        newPath+="$path/bin:"
      done

      echo "$newPath"
    }

    for path in "''${package_paths[@]}"; do
        # Add package derivations to the full set of ro-bind options for bwrap.
        ro_bind_options_for_package=$(generate_ro_bind_options "$path")
        all_ro_bind_options+="$ro_bind_options_for_package"

        new_path_segments=$(generate_new_path "$path")
        fullPath+="$new_path_segments"
    done

    export PATH=$fullPath
    export PATH=${lib.makeBinPath [ pkgs.rust-bin.stable.latest.default ]}:$PATH
    export fullPath=$PATH

    # Define UID and GID for creating temporary passwd and group files
    mUID=$(id -u)
    mGID=$(id -g)

    # Create temporary files for passwd and group
    TMP_PASSWD=$(mktemp)
    TMP_GROUP=$(mktemp)

    # Create /etc/passwd and /etc/group files with the current user's UID/GID, and the nobody user.
    getent passwd $mUID 65534 > $TMP_PASSWD
    getent group $mGID 65534 > $TMP_GROUP

    export projectRoot="$HOME/Documents/projects"
    export projectDir="$projectRoot/codes/rust/nixos/"

    # It's time to create the sandbox and launch the shell as a default action.
    # The SSL stuff is insane and it has to be done this way. This took hours
    # to figure out. Most everything else that is getting set is fairly
    # obvious. I don't think the order of the arguments matters, since bwrap
    # probably has to do these things in a deterministic order anyway, but the
    # order you see the operations here is roughly the order that things need
    # to happen.

    exec bwrap \
      --symlink /tmp $TMP \
      --dir $HOME/.config/fish \
      --proc /proc \
      --dev /dev \
      --chdir $projectDir \
      --bind $projectDir $projectDir \
      $all_ro_bind_options \
      --ro-bind /etc/resolv.conf /etc/resolv.conf \
      --dir /etc/static/ssl/certs \
      --symlink ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt /etc/static/ssl/certs/ca-bundle.crt \
      --symlink ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt /etc/static/ssl/certs/ca-certificates.crt \
      --ro-bind ${pkgs.cacert.p11kit} ${pkgs.cacert.p11kit} \
      --symlink ${pkgs.cacert.p11kit} /etc/static/ssl/trust-source \
      --dir /etc/ssl/certs \
      --symlink /etc/static/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-bundle.crt \
      --symlink /etc/static/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt \
      --symlink $projectDir/config.fish $HOME/.config/fish/config.fish \
      --symlink /etc/static/ssl/trust-source /etc/ssl/trust-source \
      --setenv SSL_CERT_FILE "/etc/ssl/certs/ca-certificates.crt" \
      --setenv SSL_CERT_DIR "/etc/ssl/certs" \
      --unshare-all \
      --share-net \
      --die-with-parent \
      --dir /run/user/$(id -u) \
      --setenv XDG_RUNTIME_DIR "/run/user/$(id -u)" \
      --setenv PS1 "rust-dev\$ " \
      --setenv TERM "screen-256color" \
      --setenv fullPath "$fullPath" \
      --ro-bind $TMP_PASSWD /etc/passwd \
      --ro-bind $TMP_GROUP /etc/group \
      --ro-bind $HOME/.gitconfig $HOME/.gitconfig \
      --ro-bind $HOME/.git-credentials $HOME/.git-credentials \
      ${pkgs.fish}/bin/fish --private
  '';
        };
      }
    );
}
