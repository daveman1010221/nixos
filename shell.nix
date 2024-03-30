{ pkgs ? import <nixpkgs> {} }:
let
  overrides = (builtins.fromTOML (builtins.readFile ./rust-toolchain.toml));
  libPath = with pkgs; lib.makeLibraryPath [
    # libraries required for your project
  ];

  projectDir = "/home/djshepard/Documents/codes/rust/hello_world";
in
pkgs.mkShell rec {
  buildInputs = with pkgs; [
    clang
    llvmPackages_16.bintools
    rustup
    neovim
    bubblewrap
    fish
    fishPlugins.bass.src
    fishPlugins.bobthefish.src
    fishPlugins.foreign-env.src
    fishPlugins.grc.src
    getent
    grc
    coreutils
    util-linux
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

  shellHook = ''
    function run {
      # Define UID and GID for creating temporary passwd and group files
      mUID=$(id -u)
      mGID=$(id -g)

      # Create temporary files for passwd and group
      TMP_PASSWD=$(mktemp)
      TMP_GROUP=$(mktemp)

      # Populate files with necessary content
      getent passwd $mUID 65534 > $TMP_PASSWD && echo "temp passwd: $TMP_PASSWD"
      getent group $mGID 65534 > $TMP_GROUP
      local newPath="${pkgs.getent}/bin:${pkgs.neovim}/bin:${pkgs.fish}/bin:${pkgs.bubblewrap}/bin:${pkgs.coreutils}/bin:/bin:/usr/bin"
      bwrap \
        --dir /tmp \
        --proc /proc \
        --dev /dev \
        --ro-bind /etc/resolv.conf /etc/resolv.conf \
        --chdir ${projectDir} \
        --ro-bind ${projectDir} ${projectDir} \
        --ro-bind /etc /etc \
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
        ${pkgs.fish}/bin/fish
    }

    echo "Sandboxed environment initialized. Use 'run' to launch a sandboxed fish shell."
  '';
}



