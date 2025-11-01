{
  system,
  pkgs,
  rust-overlay,
  dotacatFast
}:
let
  wrapped-portal = pkgs.writeShellScriptBin "xdg-desktop-portal-cosmic-wrapper" ''
    export WAYLAND_DISPLAY=$(ls /run/user/$UID | grep -E '^wayland-[0-9]+$' | head -n1)
    export XDG_SESSION_TYPE=wayland
    export XDG_CURRENT_DESKTOP=cosmic
    exec ${pkgs.xdg-desktop-portal-cosmic}/libexec/xdg-desktop-portal-cosmic
  '';
in {
    myPkgs = with pkgs; [
        wrapped-portal

        (rust-bin.nightly.latest.default.override {
          targets = [ "wasm32-unknown-unknown" ];
          extensions = [ "rust-src" "rust-analyzer" "miri" ];
        })

        ananicy-cpp
        ananicy-rules-cachyos

        android-tools
        #android-udev-rules

        # Tauri dev
        cargo-generate
        cargo-tauri
        cargo-leptos
        cachix
        nodejs
        gobject-introspection
        at-spi2-atk
        atkmm
        cairo
        gdk-pixbuf
        glib
        gtk3
        harfbuzz
        librsvg
        libsoup_3
        pango
        webkitgtk_4_1
        tailwindcss
        esbuild

        nvim-pkg
        #audit
        atuin
        babelfish
        bandwhich
        bat
        bottom
        bonnie
        btop
        buildkit
        cheese
        clamav
        clangStdenv
        cl-wordle
        cni-plugins
        containerd
        cosmic-bg
        cosmic-osd
        cosmic-term
        cosmic-idle
        cosmic-edit
        cosmic-comp
        cosmic-store
        cosmic-randr
        cosmic-panel
        cosmic-icons
        cosmic-files
        cosmic-player
        cosmic-session
        cosmic-greeter
        cosmic-ext-ctl
        cosmic-applets
        cosmic-settings
        cosmic-launcher
        cosmic-protocols
        cosmic-wallpapers
        cosmic-screenshot
        cosmic-ext-tweaks
        cosmic-applibrary
        cosmic-design-demo
        cosmic-notifications
        cosmic-ext-calculator
        cosmic-settings-daemon
        cosmic-workspaces-epoch
        xdg-desktop-portal-cosmic
        cryptsetup
        cups
        deja-dup
        delta
        dhall
        dhall-nix
        dhall-yaml
        dhall-json
        dhall-docs
        dhall-bash
        dhall-nixpkgs
        dhall-lsp-server
        dhallPackages.Prelude
        dhallPackages.dhall-kubernetes
        haskellPackages.dhall-yaml
        haskellPackages.dhall-toml
        # haskellPackages.dhall-check <-- broken
        # haskellPackages.dhall-secret <-- broken
        haskellPackages.dhall-openapi
        direnv
        distrobox
        doas
        docker
        dosfstools # Provides mkfs.vfat for EFI partition
        dust
        e2fsprogs # Provides mkfs.ext4
        efibootmgr
        efitools
        efivar
        ente-desktop
        #epsonscan2
        eza
        fd
        ffmpeg_8-full
        file
        findutils
        #firefox
        librewolf
        firmware-updater
        fish
        fishPlugins.bass.src
        fishPlugins.foreign-env.src
        fishPlugins.grc.src
        fortune
        fwupd-efi
        fzf
        gitFull
        # git-up    <-- Broken
        git-cliff
        git-filter-repo
        glmark2
        furmark
        glxinfo
        graphviz
        grc
        grex
        grub2_efi
        gst_all_1.gstreamer
        gtkimageview
        gucharmap
        hunspell
        hunspellDicts.en-us
        hyperfine
        intel-gpu-tools
        jdk
        jq
        jqp
        kernel-hardening-checker
        kitty
        kitty-img
        kitty-themes
        kompose
        kubectl
        kind
        kubernetes-helm
        cri-o
        libcanberra-gtk3
        libreoffice-fresh
        lld_20
        llvmPackages_20.clangUseLLVM
        clang_20
        dotacatFast.packages.${system}.default
        lshw
        lsof
        lvm2 # Provides LVM tools: pvcreate, vgcreate, lvcreate
        mdadm # RAID management
        mdcat
        microsoft-edge
        mullvad-vpn
        mullvad-closest
        plocate
        cowsay
        neofetch
        nerdctl
        nerd-fonts.fira-mono
        nerd-fonts.fira-code
        networkmanager-iodine
        networkmanager-openvpn
        networkmanager-vpnc
        nftables
        nix-index
        nix-prefetch-git
        nixd
        nvidia-container-toolkit
        nvme-cli
        nvtopPackages.intel
        openssl
        openssl.dev
        ollama-cuda
        pandoc
        patool
        parted
        pciutils
        pkg-config
        podman
        podman-compose
        podman-desktop
        expressvpn
        psmisc
        pwgen
        pyenv
        #qmk
        rootlesskit
        ripgrep
        ripgrep-all
        seahorse
        signal-desktop
        simple-scan
        slirp4netns
        sqlite
        starship
        sysstat
        #systeroid
        trunk
        #teams  <-- not currently supported on linux targets
        tinyxxd
        tldr
        tealdeer
        tmux
        tree
        tree-sitter
        usbutils
        unzip
        uv
        (vscode-with-extensions.override {
          vscodeExtensions = with vscode-extensions; [
            bbenoist.nix
            ms-azuretools.vscode-docker
            dhall.vscode-dhall-lsp-server
            dhall.dhall-lang
          ];
        })
        viu
        vkmark
        vulkan-tools
        vulnix
        #wasm-pack
        #wasmtime
        #wasm-bindgen-cli_0_2_100
        wordbook
        #wasmer
        #wasmer-pack
        wayland-utils
        wget
        wine64                                      # support 64-bit only
        wineWowPackages.staging                     # wine-staging (version with experimental features)
        winetricks                                  # winetricks (all versions)
        wineWowPackages.waylandFull                 # native wayland support (unstable)
        wireguard-tools
        bottles                                     # a wine prefix UI
        wl-clipboard-rs
        (hiPrio xwayland)
        xbindkeys
        xbindkeys-config
        yaru-theme
        zed-editor
        zellij
        zoom-us
    ];

    wrapped-portal = wrapped-portal;
}
