{ pkgs ? import <nixpkgs> {} }:
let
  userHome = builtins.getEnv "HOME";
  projectRoot = "/Documents/projects";
  projectDir = "${userHome}${projectRoot}/codes/rust/nixos/";
in
pkgs.mkShell rec {
  buildInputs = with pkgs; [
    binutils
    bubblewrap
    cargo
    clang_latest
    clippy
    deterministic-uname
    fish
    fishPlugins.bass.src
    fishPlugins.bobthefish.src
    fishPlugins.foreign-env.src
    fishPlugins.grc.src
    getent
    git
    grc
    iproute
    iputils
    llvmPackages_latest.bintools
    llvmPackages_latest.stdenv
    neovim
    nix
    openssl
    rustc
    rustfmt
    util-linux
    uutils-coreutils-noprefix
  ];

  RUSTC_VERSION = overrides.toolchain.channel;
  LIBCLANG_PATH = pkgs.lib.makeLibraryPath [ pkgs.llvmPackages_latest.libclang.lib ];

  RUSTFLAGS = (builtins.map (a: ''-L ${a}/lib'') [
    # Add libraries here
  ]);
  LD_LIBRARY_PATH = libPath;

  BINDGEN_EXTRA_CLANG_ARGS =
    (builtins.map (a: ''-I"${a}/include"'') [
      pkgs.glibc.dev
    ])
    ++ [
      ''-I"${pkgs.llvmPackages_latest.libclang.lib}/lib/clang/${pkgs.llvmPackages_latest.libclang.version}/include"''
      ''-I"${pkgs.glib.dev}/include/glib-2.0"''
      ''-I${pkgs.glib.out}/lib/glib-2.0/include/''
    ];

  # Certain Rust tools won't work without this
  # This can also be fixed by using oxalica/rust-overlay and specifying the rust-src extension
  # See https://discourse.nixos.org/t/rust-src-not-found-and-other-misadventures-of-developing-rust-on-nixos/11570/3?u=samuela. for more details.
  RUST_SRC_PATH = "${pkgs.rust.packages.stable.rustPlatform.rustLibSrc}";

  shellHook = ''
    # The '--pure' flag to 'nix-shell' sets this variable to an invalid path
    # and it breaks SSL. The variable doesn't exist at all in an impure shell.
    # I do not know why they do this. The safest fix I've discovered is to set
    # this to a valid path.
    export NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

    # Accumulate all ro_bind_options, collected from the various package derivations.
    all_ro_bind_options=""

    # The derivations for all packages listed here will be expanded and added
    # to the set of read-only bind mounts for the bubble wrap sandbox.
    # Additionally, we will try to use this to add items to the PATH.

    package_paths=(
        "${pkgs.binutils}"
        "${pkgs.bubblewrap}"
        "${pkgs.cacert}"
        "${pkgs.cargo}"
        "${pkgs.clang_latest}"
        "${pkgs.clippy}"
        "${pkgs.deterministic-uname}"
        "${pkgs.fish}"
        "${pkgs.fishPlugins.bass.src}"
        "${pkgs.fishPlugins.bobthefish.src}"
        "${pkgs.fishPlugins.foreign-env.src}"
        "${pkgs.fishPlugins.grc.src}"
        "${pkgs.getent}"
        "${pkgs.git}"
        "${pkgs.grc}"
        "${pkgs.iproute}"
        "${pkgs.iputils}"
        "${pkgs.llvmPackages_latest.bintools}"
        "${pkgs.llvmPackages_latest.stdenv}"
        "${pkgs.neovim}"
        "${pkgs.nix}"
        "${pkgs.openssl}"
        "${pkgs.rustc}"
        "${pkgs.rustfmt}"
        "${pkgs.tree}"
        "${pkgs.util-linux}"
        "${pkgs.uutils-coreutils-noprefix}"
    )

    # This newPath will be used as PATH in the sandbox.
    newPath=""

    # Generate --ro-bind options for a given package
    generate_ro_bind_options_and_update_path() {
      local package_path="$1"
      local ro_bind_options=""

      # Query the requisites of a given package and generate ro_bind options.
      # Note that this isn't 'pure', unless you pin your package versions,
      # which is probably a good idea, but maybe not initially.
      for path in $(nix-store --query --requisites "$package_path"); do
        ro_bind_options+="--ro-bind $path $path "

        # Use the package paths to build the newPath.
        newPath+="$path/bin:"
      done

      echo "$ro_bind_options"
    }

    for path in "''${package_paths[@]}"; do
        # Add package derivations to the full set of ro-bind options for bwrap.
        ro_bind_options_for_package=$(generate_ro_bind_options_and_update_path "$path")
        all_ro_bind_options+="$ro_bind_options_for_package"
    done

    # Define UID and GID for creating temporary passwd and group files
    mUID=$(id -u)
    mGID=$(id -g)

    # Create temporary files for passwd and group
    TMP_PASSWD=$(mktemp)
    TMP_GROUP=$(mktemp)

    # Create /etc/passwd and /etc/group files with the current user's UID/GID, and the nobody user.
    getent passwd $mUID 65534 > $TMP_PASSWD
    getent group $mGID 65534 > $TMP_GROUP

    # It's time to create the sandbox and launch the shell as a default action.
    # The SSL stuff is insane and it has to be done this way. This took hours
    # to figure out. Most everything else that is getting set is fairly
    # obvious. I don't think the order of the arguments matters, since bwrap
    # probably has to do these things in a deterministic order anyway, but the
    # order you see the operations here is roughly the order that things need
    # to happen.

    bwrap \
      --dir /tmp \
      --proc /proc \
      --dev /dev \
      --chdir ${projectDir} \
      --bind ${projectDir} ${projectDir} \
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
      --setenv PATH "$newPath" \
      --ro-bind $TMP_PASSWD /etc/passwd \
      --ro-bind $TMP_GROUP /etc/group \
      --ro-bind $HOME/.gitconfig $HOME/.gitconfig \
      --ro-bind $HOME/.git-credentials $HOME/.git-credentials \
      ${pkgs.fish}/bin/fish
  '';
}
