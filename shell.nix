{ pkgs ? import <nixpkgs> {} }:
let
  overrides = (builtins.fromTOML (builtins.readFile ./rust-toolchain.toml));
  libPath = with pkgs; lib.makeLibraryPath [
    # libraries required for your project
  ];

  projectDir = "/home/djshepard/Documents/projects/codes/rust/nixos/";
in
pkgs.mkShell rec {
  buildInputs = with pkgs; [
    bubblewrap
    clang_16
    coreutils
    fish
    fishPlugins.bass.src
    fishPlugins.bobthefish.src
    fishPlugins.foreign-env.src
    fishPlugins.grc.src
    getent
    git
    grc
    iputils
    iproute
    llvmPackages_16.bintools
    llvmPackages_16.stdenv
    glib
    neovim
    nix
    openssl
    rustup
    util-linux
  ];

  RUSTC_VERSION = overrides.toolchain.channel;
  LIBCLANG_PATH = pkgs.lib.makeLibraryPath [ pkgs.llvmPackages_16.libclang.lib ];

  RUSTFLAGS = (builtins.map (a: ''-L ${a}/lib'') [
    # Add libraries here
  ]);
  LD_LIBRARY_PATH = libPath;

  BINDGEN_EXTRA_CLANG_ARGS =
    (builtins.map (a: ''-I"${a}/include"'') [
      pkgs.glibc.dev
    ])
    ++ [
      ''-I"${pkgs.llvmPackages_16.libclang.lib}/lib/clang/${pkgs.llvmPackages_16.libclang.version}/include"''
      ''-I"${pkgs.glib.dev}/include/glib-2.0"''
      ''-I${pkgs.glib.out}/lib/glib-2.0/include/''
    ];

  shellHook = ''
    export NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

    # Initialize a global variable to accumulate all ro_bind_options
    all_ro_bind_options=""

    # Function to generate --ro-bind options for a given package
    generate_ro_bind_options() {
        local package_path="$1"
        local ro_bind_options=""

        # Query the requisites of the package and generate ro_bind options
        for path in $(nix-store --query --requisites "$package_path"); do
            ro_bind_options+="--ro-bind $path $path "
        done

        echo "$ro_bind_options"
    }

    # Example usage of the function for multiple packages
    package_paths=(
        "${pkgs.bubblewrap}"
        "${pkgs.cacert}"
        "${pkgs.coreutils}"
        "${pkgs.fish}"
        "${pkgs.getent}"
        "${pkgs.iputils}"
        "${pkgs.iproute}"
        "${pkgs.neovim}"
        "${pkgs.nix}"
        "${pkgs.openssl}"
        "${pkgs.rustup}"
        "${pkgs.tree}"
        "${pkgs.llvmPackages_16.bintools}"
        "${pkgs.llvmPackages_16.stdenv}"
        "${pkgs.clang_16}"
        "${pkgs.git}"
    )

    for package_path in "''${package_paths[@]}"; do
        ro_bind_options_for_package=$(generate_ro_bind_options "$package_path")
        all_ro_bind_options+="$ro_bind_options_for_package"
    done

    function run {
      # Define UID and GID for creating temporary passwd and group files
      mUID=$(id -u)
      mGID=$(id -g)

      # Create temporary files for passwd and group
      TMP_PASSWD=$(mktemp)
      TMP_GROUP=$(mktemp)

      # Populate files with necessary content
      getent passwd $mUID 65534 > $TMP_PASSWD
      getent group $mGID 65534 > $TMP_GROUP
      local newPath="${pkgs.getent}/bin:${pkgs.neovim}/bin:${pkgs.fish}/bin:${pkgs.bubblewrap}/bin:${pkgs.coreutils}/bin:/bin:/usr/bin:${pkgs.nix}/bin:${pkgs.rustup}/bin:${pkgs.openssl}/bin:${pkgs.iputils}/bin:${pkgs.iproute}/bin:${pkgs.tree}/bin:${pkgs.llvmPackages_16.bintools}/bin:${pkgs.llvmPackages_16.stdenv}/bin:${pkgs.clang_16}/bin:${pkgs.git}/bin"
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
        --setenv PS1 "bwrap-demo\$ " \
        --setenv TERM "screen-256color" \
        --setenv PATH "$newPath" \
        --ro-bind $TMP_PASSWD /etc/passwd \
        --ro-bind $TMP_GROUP /etc/group \
        --ro-bind $HOME/.gitconfig $HOME/.gitconfig \
        --ro-bind $HOME/.git-credentials $HOME/.git-credentials \
        ${pkgs.fish}/bin/fish
    }

    echo "Sandboxed environment initialized. Use 'run' to launch a sandboxed fish shell."
  '';
}
