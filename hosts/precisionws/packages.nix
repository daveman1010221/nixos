{
  system,
  pkgs,
  rust-overlay,
  dotacatFast
}:
let
in
{
    # System-wide package list
    myPkgs = with pkgs; [
        (rust-bin.nightly.latest.default.override {
          targets = [ "wasm32-unknown-unknown" ];
          extensions = [ "rust-src" "rust-analyzer" ];
        })

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
        #epsonscan2
        eza
        fd
        file
        findutils
        firefox
        firmware-updater
        fish
        fishPlugins.bass.src
        fishPlugins.bobthefish.src
        fishPlugins.foreign-env.src
        fishPlugins.grc.src
        fortune
        fwupd-efi
        fzf
        gitFull
        # git-up    <-- Broken
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
        llvmPackages_20.clangUseLLVM
        clang_20
        lld_20
        dotacatFast.packages.${system}.default
        lshw
        lsof
        lvm2 # Provides LVM tools: pvcreate, vgcreate, lvcreate
        mdadm # RAID management
        mdcat
        #microsoft-edge
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
        #iptables
        nix-index
        nix-prefetch-git
        nixd
        nvidia-container-toolkit
        nvme-cli
        nvtopPackages.intel
        openssl
        openssl.dev
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
        python312Full
        qmk
        rootlesskit
        rustdesk
        ripgrep
        ripgrep-all
        seahorse
        #servo
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
        wasm-pack
        wasmtime
        wordbook
        wasmer
        wasmer-pack
        wasm-bindgen-cli_0_2_100
        wayland-utils
        wget
        wine64                                      # support 64-bit only
        wineWowPackages.staging                     # wine-staging (version with experimental features)
        winetricks                                  # winetricks (all versions)
        wineWowPackages.waylandFull                 # native wayland support (unstable)
        bottles                                     # a wine prefix UI
        wl-clipboard-rs
        (hiPrio xwayland)
        xbindkeys
        xbindkeys-config
        yaru-theme
        zed-editor
        zellij
        zoom-us

        # However, AppArmor is a bit more fully baked:
        # apparmor-parser
        # libapparmor
        # apparmor-utils
        # apparmor-profiles
        # apparmor-kernel-patches
        # #roddhjav-apparmor-rules
        # apparmor-pam
        # apparmor-bin-utils
    ];
}
