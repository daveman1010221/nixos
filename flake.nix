{
  inputs = {
    nixpkgs.follows = "nixos-cosmic/nixpkgs";

    nixos-cosmic.url = "github:lilyinstarlight/nixos-cosmic";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixos-cosmic/nixpkgs";
      };
    };

    myNeovimOverlay = {
      url = "github:daveman1010221/nix-neovim";
      inputs = {
        nixpkgs.follows = "nixos-cosmic/nixpkgs";
        flake-utils.url = "github:numtide/flake-utils";
      };
    };

    dotacatFast = {
        url = "github:daveman1010221/dotacat-fast";
    };
  };

  outputs = { self, nixpkgs, nixos-cosmic, rust-overlay, myNeovimOverlay, dotacatFast }:
  let
    system = "x86_64-linux";

    pkgs = import nixpkgs { system = "x86_64-linux"; };

    # Step 1: Dynamically import MOK certs into the Nix store
    certsDerivation = pkgs.runCommand "certs" {} ''
      mkdir -p $out
      cp ${./MOK.pem} $out/MOK.pem
      cp ${./MOK.priv} $out/MOK.priv
    '';

    # Step 2: Read the certs from the store after the derivation runs
    mokPem = builtins.readFile "${certsDerivation}/MOK.pem";
    mokPriv = builtins.readFile "${certsDerivation}/MOK.priv";

    # Step 3: Ensure they are properly defined
    myPubCert = builtins.toFile "MOK.pem" mokPem;
    myPrivKey = builtins.toFile "MOK.priv" mokPriv;

    myConfig = builtins.toFile ".config" (builtins.readFile (builtins.toString ./.config));


    # Load the secrets if the file exists, else use empty strings.
    secrets = {
      PLACEHOLDER_NVME0 = "/dev/disk/by-id/nvme-eui.ace42e00310a1b382ee4ac0000000001";
      PLACEHOLDER_NVME1 = "/dev/disk/by-id/nvme-eui.ace42e00310a1b372ee4ac0000000001";
      PLACEHOLDER_BOOT_UUID = "/dev/disk/by-uuid/fd2eb4f6-6320-4e8c-b95d-59b38a37ebb7";
      PLACEHOLDER_BOOT_FS_UUID = "/dev/disk/by-uuid/51cdc1cc-bcc7-4be8-95e3-b1ede8bef66c";
      PLACEHOLDER_EFI_FS_UUID = "/dev/disk/by-uuid/93FA-31E7";
      PLACEHOLDER_ROOT = "/dev/disk/by-uuid/bd552f84-1dfe-4a99-9167-1d17c83ce77a";
      PLACEHOLDER_VAR = "/dev/disk/by-uuid/de0a6b69-acbb-4bba-b2ff-ab46c08310a4";
      PLACEHOLDER_TMP = "/dev/disk/by-uuid/e852da06-c243-47a4-b915-06d5e464964a";
      PLACEHOLDER_HOME = "/dev/disk/by-uuid/43a2c8d1-fa49-474d-85dc-4dee2986b8e5";
      GIT_SMTP_PASS = "mlucmulyvpqlfprb";   # <-- hash
      PLACEHOLDER_HOSTNAME = "precisionws";
    };
  in {
    nixosConfigurations = {
      "${secrets.PLACEHOLDER_HOSTNAME}" = nixpkgs.lib.nixosSystem {
        inherit system;

        modules = [
          ({ config, lib, pkgs, ... }: let
            staticFunctions = lib.mapAttrs'
              (fileName: _: {
                name = "fish/vendor_functions.d/${fileName}";
                value = {
                  source = ./shell/fish/functions/static/${fileName};
                };
              })
              (builtins.readDir ./shell/fish/functions/static);

            templatedFunctions =
              lib.mapAttrs'
                (fileName: _:
                  let
                    name = lib.removeSuffix ".nix" fileName;
                    functionDef = import ./shell/fish/functions/templated/${fileName} {
                      inherit pkgs
                      manpackage
                      hostname
                      cowsayPath;
                    };
                  in {
                    name = "fish/vendor_functions.d/${name}.fish";
                    value = { text = functionDef; };
                  })
                (lib.filterAttrs (n: _: lib.hasSuffix ".nix" n)
                  (builtins.readDir ./shell/fish/functions/templated));

            cowsayPath = pkgs.cowsay;
            hostname = secrets.PLACEHOLDER_HOSTNAME;
            manpackage = pkgs.man;
            fisheyGrc = pkgs.fishPlugins.grc;
            bass = pkgs.fishPlugins.bass;
            bobthefish = pkgs.fishPlugins.bobthefish;
            starshipBin = "${pkgs.starship}/bin/starship";
            atuinBin = "${pkgs.atuin}/bin/atuin";
            editor = myNeovimOverlay;
            fishShell = pkgs.fish;
            browser = "${pkgs.firefox}/bin/firefox";
          in {
            nixpkgs = {
              hostPlatform = lib.mkDefault "x86_64-linux";
              overlays = [
                rust-overlay.overlays.default
                myNeovimOverlay.overlays.default

                # The audit package needs and overlay to get the permissions right for
                # the service to load the plug-ins.
                # (self: super: {
                #   audit = super.audit.overrideAttrs (oldAttrs: {
                #     postInstall = (oldAttrs.postInstall or "") + ''
                #       # Change permissions of all binaries in $bin/bin and $bin/sbin to 0750
                #       for dir in "$bin/bin"; do
                #         if [ -d "$dir" ]; then
                #           chmod 0750 "$dir"/*
                #         fi
                #       done
                #     '';
                #   });
                # })
                # (self: super: {
                #   srtp = super.srtp.overrideAttrs (oldAttrs: rec {
                #     doCheck = false;
                #     mesonFlags = [
                #       "-Dcrypto-library=openssl"
                #       "-Dcrypto-library-kdf=disabled"
                #       "-Ddoc=disabled"
                #       "-Dtests=${if doCheck then "enabled" else "disabled"}"
                #     ];
                #   });
                # })

                # This override was created to fix a problem with bottles, which now works without this.
                # (self: super: {
                #   python3Packages = super.python3Packages.override {
                #     overrides = (pySelf: pyPrev: {
                #       patool = pyPrev.patool.overrideAttrs (oldAttrs: {
                #         # Keep doCheck = oldAttrs.doCheck or true
                #         doCheck = true;  # Let the rest of the tests run normally
                #
                #         postPatch = (oldAttrs.postPatch or "") + ''
                #           echo "Patching out the failing test_nested_gzip..."
                #           # Rename 'test_nested_gzip' so it never runs
                #           sed -i 's:def test_nested_gzip:def skip_nested_gzip:' tests/test_mime.py
                #         '';
                #       });
                #     });
                #   };
                # })

                # (self: super: {
                  # makeModulesClosure = { kernel, firmware, rootModules, allowMissing ? false }:
                    # super.makeModulesClosure {
                      # inherit kernel firmware rootModules;
                      # allowMissing = true; # Force true
                    # };
                # }) 

                (self: super: {
                  hardened_linux_kernel = super.linuxPackagesFor (super.linuxKernel.kernels.linux_6_13_hardened.overrideAttrs (old: {
                    dontConfigure = true;

                    nativeBuildInputs = (old.nativeBuildInputs or []) ++ [ super.kmod super.openssl super.hostname super.qboot ];
                    buildInputs = (old.buildInputs or []) ++ [ super.kmod super.openssl super.hostname ];

                    buildPhase = ''
                      mkdir -p tmp_certs
                      cp ${myConfig} tmp_certs/.config
                      cp ${myPubCert} tmp_certs/MOK.pem
                      cp ${myPrivKey} tmp_certs/MOK.priv

                      # Ensure they are actually there before proceeding
                      ls -lah tmp_certs

                      # Move them into place before compilation
                      cp tmp_certs/.config .config
                      cp tmp_certs/MOK.pem MOK.pem
                      cp tmp_certs/MOK.priv MOK.priv

                      ls -alh

                      make \
                        ARCH=${super.stdenv.hostPlatform.linuxArch} \
                        CROSS_COMPILE= \
                        KBUILD_BUILD_VERSION=1-NixOS \
                        KCFLAGS=-Wno-error \
                        O=. \
                        SHELL=${super.bash}/bin/bash \
                        -j$NIX_BUILD_CORES \
                        bzImage modules
                    '';

                    installPhase = ''
                      export PATH=${super.openssl}/bin:$PATH
                      echo "Using OpenSSL from: $(which openssl)"
                      openssl version

                      mkdir -p $out
                      mkdir -p $dev

                      make \
                        INSTALL_PATH=$out \
                        INSTALL_MOD_PATH=$out \
                        INSTALL_HDR_PATH=$dev \
                        O=. \
                        -j$NIX_BUILD_CORES \
                        headers_install modules_install

                      cp arch/x86/boot/bzImage System.map $out/

                      version=$(make O=. kernelrelease)

                      # Prepare the source tree for external module builds
                      mkdir -p $dev/lib/modules/$version/source

                      # Preserve essential files before cleanup
                      cp .config $dev/lib/modules/$version/source/.config
                      if [ -f Module.symvers ]; then cp Module.symvers $dev/lib/modules/$version/source/Module.symvers; fi
                      if [ -f System.map ]; then cp System.map $dev/lib/modules/$version/source/System.map; fi
                      if [ -d include ]; then
                        mkdir -p $dev/lib/modules/$version/source
                        cp -r include $dev/lib/modules/$version/source/
                      fi

                      # Clean the build tree
                      make O=. clean mrproper

                      # Copy the cleaned-up source tree before it gets removed.
                      cp -a . $dev/lib/modules/$version/source

                      # **Change to the new source directory**
                      cd $dev/lib/modules/$version/source

                      # Regenerate configuration and prepare for external module compilation
                      make O=$dev/lib/modules/$version/source \
                        -j$NIX_BUILD_CORES \
                        prepare modules_prepare

                      ln -s $dev/lib/modules/$version/source $dev/lib/modules/$version/build
                    '';

                    outputs = [ "out" "dev" ];
                  }));

                  nvidiaPackages = self.hardened_linux_kernel.nvidiaPackages.beta.overrideAttrs (old: {
                    preInstall = (if old.preInstall == null then "" else old.preInstall) + ''
                      echo "🚨 NVIDIA OVERLAY IS RUNNING 🚨"
                      echo "🚨 NVIDIA PRE-FIXUP: Signing NVIDIA kernel modules before compression 🚨"

                      SIGN_FILE="${self.hardened_linux_kernel.dev}/lib/modules/${old.kernelVersion}/source/scripts/sign-file"
                      MOK_CERT="${self.hardened_linux_kernel.dev}/lib/modules/${old.kernelVersion}/source/MOK.pem"
                      MOK_KEY="${self.hardened_linux_kernel.dev}/lib/modules/${old.kernelVersion}/source/MOK.priv"

                      if [ ! -x "$SIGN_FILE" ]; then
                        echo "❌ sign-file tool not found at $SIGN_FILE"
                        exit 1
                      fi

                      echo "✅ Using sign-file: $SIGN_FILE"
                      echo "✅ Signing NVIDIA kernel modules with MOK key: $MOK_KEY"

                      # Find all uncompressed .ko modules and sign them
                      for mod in $(find $out/lib/modules -type f -name "*.ko"); do
                        echo "🔹 Signing module: $mod"
                        $SIGN_FILE sha256 $MOK_KEY $MOK_CERT "$mod" || exit 1
                      done

                      echo "✅ All modules signed successfully!"
                    '';
                  });

                  # Assign to kernel package set so the system uses it
                  self.hardened_linux_kernel.nvidiaPackages.beta = self.nvidiaPackages;

                })
              ];

              config = {
                allowUnfree = true;
                doCheck = false;  # This doesn't seem to help, at least in all circumstances. This disables running test during package builds, globally.
                nvidia = {
                  acceptLicense = true;
                };
              };
            };

            nix = {
              settings = {
                # max-jobs = 1;
                # build-cores = 1;
                # cores = 1;
                substituters = [
                  "https://cosmic.cachix.org/"
                  "https://airtool-dev.cachix.org"
                ];
                trusted-public-keys = [
                  "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE="
                  "airtool-dev.cachix.org-1:dfX1T1ibTyc1dIOSWtxQxbpPJUya00RVFu9gLtiWvn8="
                ];
                trusted-users = [ "root" "djshepard" ];
              };
              extraOptions = ''
                experimental-features = nix-command flakes
              '';
              # package = nixpkgs.nixVersions.stable;
              settings.experimental-features = [ "nix-command" "flakes" ];
            };

            # Boot configuration
            boot = {
              # Configure the kernel

              # This bug-checks when GDM tries to initialize the external Nvidia display,
              # so clearly some sort of issue with the Nvidia driver and the hardened
              # kernel. It works fine for 'on the go' config, though. Considering making two kernel configs.
              kernelPackages = pkgs.hardened_linux_kernel;

              kernelModules = [ "kvm-intel" ];

              kernelParams = [
                "i8042.unlock"
                "intel_idle.max_cstate=4"
                "intel_iommu=on"
                #"lockdown=confidentiality"
                "mitigations=auto"
                "pci=realloc"
                "seccomp=1"
                "unprivileged_userns_clone=1"
                "zswap.compressor=lzo"
                "zswap.enabled=1"
                "zswap.max_pool_percent=10"
                "modprobe.blacklist=nouveau"
                "rootfstype=f2fs"
                "nvme_core.default_ps_max_latency_us=0"
                "fips=1"
                "dm_crypt.max_read_size=1048576"
                "dm_crypt.max_write_size=65536"
                "NVreg_EnableGpuFirmware=1"
              ];

              kernelPatches = [
              ];

              kernel = {
                # unprivileged_userns_clone is for applications to be able to implement
                # sandboxing, since unprivileged user namespaces are disabled by default
                # when using a hardened kernel.

                # The net.ipv4 options are there to enable certain network operations
                # inside of rootless containers.
                sysctl = {
                  "net.ipv4.ip_unprivileged_port_start" = 0;
                  "net.ipv4.ping_group_range" = "0 2147483647";
                  "kernel.unprivileged_userns_clone" = 1;
                };
              };

              # A compile error prevents me from having drivers for my Alfa
              # Networks AWUS 1900 USB Wifi adapter. Supposedly, this driver
              # will in the upstream kernel in 6.15.
              # extraModulePackages = [
              #   pkgs.hardened_linux_kernel.rtl8814au
              # ];

              initrd = {
                includeDefaultModules = false;  # <-- This, along with
                                                # 'luks.cryptoModules' below,
                                                # causes unexpected driver
                                                # loading that isn't kosher for
                                                # a FIPS kernel...

                # Ensure the initrd includes necessary modules for encryption, RAID, and filesystems
                availableKernelModules = lib.mkForce [
                  "nls_cp437"
                  "nls_iso8859_1"
                  "crypto_null"
                  "cryptd"
                  "sha256"
                  "vmd"

                  # crypto
                  "aesni_intel"     # The gold standard for FIPS 140-2/3 compliance
                                    # Hardware-accelerate AES within the Intel CPU
                  "gf128mul"
                  "crypto_simd"

                  "dm_crypt"        # LUKS encryption support for device mapper storage infrastructure

                  "essiv"           # Encrypted Salt-Sector Initialization Vector is a transform for various encryption modes, mostly supporting block device encryption
                  "authenc"
                  "xts"             # XEX-based tweaked-codebook mode with ciphertext stealing -- like essiv, is designed specifically for block device encryption

                  # filesystems
                  "ext4"            # Old time linux filesystem, used on the encrypted USB boot volume. Required because grub doesn't support F2FS yet.
                  "crc16"
                  "mbcache"
                  "jbd2"
                  "f2fs"            # Flash-friendly filesystem support -- the top-layer of our storage stack
                  "lz4_compress"
                  "lz4hc_compress"
                  "vfat"            # Windows FAT volumes, such as the FAT12 EFI partition
                  "fat"

                  # storage
                  "nvme"            # NVME drive support
                  "nvme_core"
                  "nvme_auth"
                  "raid0"           # Software RAID0 via mdadm
                  "usb_storage"     # Generic USB storage support
                  "scsi_mod"
                  "scsi_common"
                  "libata"
                  "dm_mod"          # Device mapper infrastructure
                  "dm_snapshot"
                  "dm_bufio"
                  "dax"
                  "md_mod"

                  # hardware support modules
                  "ahci"            # SATA disk support
                  "libahci"
                  "sd_mod"          # SCSI disk support (/dev/sdX)
                  "uas"             # USB attached SCSI (booting from USB)
                  "usbcore"         # USB support
                  "usbhid"
                  "i2c_hid"
                  "hid_multitouch"
                  "hid_sensor_hub"
                  "intel_ishtp_hid"
                  "hid_generic"
                  "xhci_hcd"        # USB 3.x support
                  "xhci_pci"        # USB 3.x support
                  "thunderbolt"
                ];

                # Define LUKS devices, including the encrypted /boot and NVMe devices
                # EDIT
                luks = {
                  cryptoModules = [
                    "aesni_intel"
                    "essiv"
                    "xts"
                    "sha256"
                  ];

                  devices = {
                    boot_crypt = {
                      # sdb2 UUID (pre-luksOpen)
                      device = secrets.PLACEHOLDER_BOOT_UUID;
                      preLVM = true;
                      allowDiscards = true;
                      # Custom mount commands for the unencrypted /boot, included in the initrd
                      # EDIT
                      postOpenCommands = lib.mkBefore ''
                        #!${pkgs.stdenv.shell}
                        echo "Mounting unencrypted /boot..."

                        if [ -e /dev/mapper/boot_crypt ]; then
                            echo "Preparing secure key storage..."

                            # Define and create a secure mount point for keys
                            SENSITIVE_MOUNT="/sensitive"
                            mkdir -p $SENSITIVE_MOUNT

                            # Mount a dedicated tmpfs for storing keys securely
                            mount -t tmpfs -o size=50M,mode=0700,noswap tmpfs $SENSITIVE_MOUNT

                            echo "Ensuring /tmp/boot exists..."
                            mkdir -p /tmp/boot

                            echo "Mounting boot_crypt to /tmp/boot..."
                            mount -t ext4 /dev/mapper/boot_crypt /tmp/boot

                            echo "Copying keys to secure storage..."
                            mkdir --mode=0600 -p $SENSITIVE_MOUNT/keys

                            cp /tmp/boot/keys/nvme0n1.header $SENSITIVE_MOUNT/keys
                            cp /tmp/boot/keys/nvme1n1.header $SENSITIVE_MOUNT/keys
                            cp /tmp/boot/keys/nvme0n1.key $SENSITIVE_MOUNT/keys
                            cp /tmp/boot/keys/nvme1n1.key $SENSITIVE_MOUNT/keys

                            chmod 400 $SENSITIVE_MOUNT/keys/nvme0n1.header 
                            chmod 400 $SENSITIVE_MOUNT/keys/nvme1n1.header 
                            chmod 400 $SENSITIVE_MOUNT/keys/nvme0n1.key 
                            chmod 400 $SENSITIVE_MOUNT/keys/nvme1n1.key 

                            sync

                            # Unmounting /tmp/boot
                            umount /tmp/boot
                        fi
                      '';
                    };

                    # Configuration for NVMe devices with detached headers and keys on encrypted /boot
                    # EDIT
                    nvme0n1_crypt = {
                      device = secrets.PLACEHOLDER_NVME0;
                      header = "/sensitive/keys/nvme0n1.header";
                      keyFile = "/sensitive/keys/nvme0n1.key";
                      allowDiscards = true;
                      bypassWorkqueues = true;
                      postOpenCommands = ''
                        # Securely erase the key and header files
                        ${pkgs.coreutils}/bin/shred -u /sensitive/keys/nvme0n1.key || true
                        ${pkgs.coreutils}/bin/shred -u /sensitive/keys/nvme0n1.header || true
                      '';
                    };

                    # EDIT
                    nvme1n1_crypt = {
                      device = secrets.PLACEHOLDER_NVME1;
                      header = "/sensitive/keys/nvme1n1.header";
                      keyFile = "/sensitive/keys/nvme1n1.key";
                      allowDiscards = true;
                      bypassWorkqueues = true;
                      postOpenCommands = ''
                        # Securely erase the key and header files
                        ${pkgs.coreutils}/bin/shred -u /sensitive/keys/nvme1n1.key || true
                        ${pkgs.coreutils}/bin/shred -u /sensitive/keys/nvme1n1.header || true
                      '';
                    };
                  };

                  mitigateDMAAttacks = true;
                };

                services.lvm.enable = true;

                supportedFilesystems = ["ext4" "vfat" "f2fs" ];
              };

              # The variables 'canTouchEfiVariables' and 'efiInstallAsRemovable' are
              # mutually exclusive. Touching EFI variables that tell UEFI where to find the
              # boot loader means you can't install your grub as removable.

              loader = {
                efi.canTouchEfiVariables = false;
                efi.efiSysMountPoint = "/boot/EFI";

                # Enable the GRUB bootloader with UEFI support
                grub = {
                  enable = true;
                  enableCryptodisk = true;
                  efiSupport = true;
                  device = "nodev";
                  efiInstallAsRemovable = true;
                  copyKernels = true; # Ensures kernel/initrd are copied to the ESP, necessary for encrypted /boot

                  # Setting 'extraGrubInstallArgs' with an encrypted boot completely breaks
                  # 'enableCryptodisk'. This took a lot of time to figure out.
                };

                # Use the systemd-boot EFI boot loader.
                systemd-boot.enable = false;
              };

              swraid = {
                enable = true;
                mdadmConf = ''
                  MAILADDR daveman1010220@gmail.com
                '';
              };
            };

            environment = {
              etc = lib.mkMerge [
                (lib.mapAttrs (_: v: v) staticFunctions)
                (lib.mapAttrs (_: v: v) templatedFunctions)
                {
                  "fish/shellInit.fish".text = lib.mkForce (
                    import ./shell/fish/shellInit.nix {
                      inherit pkgs;
                    }
                  );
                }
                {
                  "fish/interactiveShellInit.fish".text =  lib.mkForce (
                    import ./shell/fish/interactiveShellInit.nix {
                      inherit
                        fisheyGrc
                        bass
                        bobthefish
                        starshipBin
                        atuinBin
                        editor
                        fishShell
                        browser;
                    }
                  );
                }
                {
                  "containers/containers.conf".text = lib.mkForce ''
                    [engine]
                    runtime = "runc"
                  '';
                }
              ];

              # System-wide package list
              systemPackages = with pkgs; [

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
                llvmPackages_19.clangUseLLVM
                clang_19
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

              sessionVariables.COSMIC_DATA_CONTROL_ENABLED = 1;
            };

            fileSystems = {
              "/" =
                {
                  device = secrets.PLACEHOLDER_ROOT;
                  fsType = "f2fs";
                  options = [ "defaults" "atgc" "background_gc=on" "discard" "noatime" "nodiratime" "nobarrier" ];
                  neededForBoot = true;
                };

              # Define filesystems for /boot and /boot/EFI
              # dm0 UUID (post-luksOpen)
              # EDIT
              "/boot" =
                { device = secrets.PLACEHOLDER_BOOT_FS_UUID;
                  fsType = "ext4";
                  neededForBoot = true;
                };

              # UUID
              # EDIT
              "/boot/EFI" =
                { device = secrets.PLACEHOLDER_EFI_FS_UUID;
                  fsType = "vfat";
                  options = [ "umask=0077" "fmask=0022" "dmask=0022" ]; # Ensure proper permissions for the EFI partition
                  neededForBoot = true;
                  depends = [ "/boot" ];
                };

              "/var" =
                {
                  device = secrets.PLACEHOLDER_VAR;
                  fsType = "f2fs";
                  options = [ "defaults" "atgc" "background_gc=on" "discard" "noatime" "nodiratime" "nobarrier" ];
                  depends = [ "/" ];
                };

              "/tmp" =
                {
                  device = secrets.PLACEHOLDER_TMP;
                  fsType = "f2fs";
                  options = [ "defaults" "atgc" "background_gc=on" "discard" "noatime" "nodiratime" "nobarrier" ];
                  depends = [ "/" ];
                };

              "/home" =
                {
                  device = secrets.PLACEHOLDER_HOME;
                  fsType = "f2fs";
                  options = [ "defaults" "atgc" "background_gc=on" "discard" "noatime" "nodiratime" "nobarrier" ];
                  depends = [ "/" ];
                };
            };

            hardware = {
              enableAllFirmware = true;
              enableAllHardware = true;
              cpu.intel.updateMicrocode = true;
              cpu.x86.msr.enable = true;
              graphics.enable = true;

              # Effectively, this option adds udev rules that allow a
              # non-privileged user to modify keyboard firmware.
              keyboard.qmk.enable = true;

              bluetooth = {
                enable = true;
                powerOnBoot = true;
              };

              bumblebee.enable = false;

              nvidiaOptimus.disable = false;
              nvidia = {
                gsp.enable = true;
                prime = {
                  allowExternalGpu = false;
                  offload.enable = false; # Mutually exclusive with prime sync.
                  offload.enableOffloadCmd = false;
                  sync.enable = false;
                  nvidiaBusId = "PCI:1:0:0";
                  intelBusId = "PCI:0:2:0";
                  reverseSync.enable = false;
                };

                #dynamicBoost.enable = true;

                open = true;

                # Modesetting is required.
                modesetting.enable = true;

                # Nvidia power management. Experimental, and can cause sleep/suspend to
                # fail. Enable this if you have graphical corruption issues or
                # application crashes after waking up from sleep. This fixes it by saving
                # the entire VRAM memory to /tmp/ instead of just the bare essentials.
                powerManagement.enable = true;

                # Fine-grained power management. Turns off GPU when not in use.
                # Experimental and only works on modern Nvidia GPUs (Turing or newer).
                powerManagement.finegrained = false;

                # Enable the Nvidia settings menu,
                # accessible via `nvidia-settings`.
                nvidiaSettings = true;

                # Optionally, you may need to select the appropriate driver version for
                # your specific GPU.
                package = pkgs.hardened_linux_kernel.nvidiaPackages.beta;
              };

              nvidia-container-toolkit = {
                enable = true;
              };
            };

            networking = {
              hostName = secrets.PLACEHOLDER_HOSTNAME;

              firewall.enable = false;

              networkmanager.enable = true;

              nftables.checkRuleset = true;
              nftables.enable = true;
              nftables.flushRuleset = true;
              nftables.ruleset = builtins.readFile ./firewall/nftables.nft;
              useDHCP = lib.mkDefault true;
            };

            programs = {

              command-not-found.enable = false;
              nix-index.enable = true;
              nix-index.enableFishIntegration = true;

              fish = {
                enable = true;
                useBabelfish = true;
                vendor = {
                  completions.enable = true;
                  config.enable = true;
                  functions.enable = true;
                };

                interactiveShellInit = ''
                  source /etc/fish/shellInit.fish
                  source /etc/fish/interactiveShellInit.fish
                  if not contains /etc/fish/vendor_functions.d $fish_function_path
                      set -a fish_function_path /etc/fish/vendor_functions.d
                  end
                '';
              };

              git = {
                  enable = true;
                  lfs.enable = true;
                  package = "${pkgs.gitFull}";
                  #prompt.enable = true;
              };

              gnupg.agent = {
                enable = true;
                enableSSHSupport = true;
              };

              # Some programs need SUID wrappers, can be configured further or are
              # started in user sessions.
              mtr.enable = true;

              tmux = {
                enable = true;
                shortcut = "a";
                aggressiveResize = true;  #Disable for iTerm
                baseIndex = 1;
                newSession = true;

                # Stop tmux+escape craziness.
                escapeTime = 0;

                # Force tmux to use /tmp for sockets (WSL2 compat)
                secureSocket = true;

                plugins = with pkgs; [
                  tmuxPlugins.better-mouse-mode
                ];

                extraConfig = ''
                  set -g mouse on
                  set -g default-terminal "screen-256color"
                  set -g focus-events on

                  set -ga terminal-overrides ",*256col*:Tc"

                  set-environment -g COLORTERM "truecolor"

                  # easy-to-remember split pane commands
                  bind | split-window -h -c "#{pane_current_path}"
                  bind - split-window -v -c "#{pane_current_path}"
                  bind c new-window -c "#{pane_current_path}"
                '';
              };

              xwayland.enable = true;
            };

            powerManagement = {
              enable = true;
            };

            security = {
              # The "audit sub-system" must be enabled as a separate option from the
              # "audit sub-system's daemon", which is necessary to have a fucking audit
              # sub-system.
              # auditd.enable = true;

              # audit = {
              #   enable = true;

              #   backlogLimit = 8192;

              #   failureMode = "printk";

              #   rateLimit = 1000;

              #   # Define audit rules
              #   rules = [
              #     "-D"
              #     "-b 8192"
              #     "-f 2"
              #     "-a always,exit -F arch=b64 -F path=/etc/passwd -F perm=wa -F key=auth_changes"
              #     "-a always,exit -F arch=b64 -F path=/etc/group -F perm=wa -F key=auth_changes"
              #     "-a always,exit -F arch=b64 -F path=/etc/shadow -F perm=wa -F key=auth_changes"
              #     "-a always,exit -F arch=b64 -F path=/etc/sudoers -F perm=wa -F key=auth_changes"
              #     "-a always,exit -F arch=b64 -S execve -k exec_commands"
              #     "-a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat,rmdir -F auid>=1000 -F auid!=unset -k file_deletions"
              #     "-a always,exit -F arch=b64 -S open,openat,openat2 -F exit=-EACCES -k access"
              #     "-a always,exit -F arch=b64 -S open,openat,openat2 -F exit=-EPERM -k access"
              #     "-e 1"
              #     "-e 2"
              #   ];
              # };

              doas = {
                enable = true;
                wheelNeedsPassword = true;
              };

              # Configure PAM audit settings for specific services if necessary
              pam.services.login = {
                # ttyAudit.enable = true;
                setLoginUid = true;
              };

              # pam.services.djshepard.enableAppArmor = true;
            };

            services = {
              # Necessary for CUPS local network printer discovery, probably
              # some other stuff, too.
              avahi = {
                wideArea = true;  # Not sure about this one yet, but true is the default.
                publish.enable = false;  # Don't publish unnecessarily.
                publish.domain = false;  # Don't announce yourself on the LAN unless needed.

                # Publish all local IP addresses. I assume this means only
                # those of allowed interfaces.
                publish.addresses = false;

                allowInterfaces = [ "wlp0s20f3" ];
                allowPointToPoint = false;
                domainName = "local";
                enable = true;
                ipv4 = true;
                ipv6 = false;
                openFirewall = true;  # 5353
                nssmdns4 = true;
              };

              blueman.enable = true;

              clamav = {
                scanner.enable = true;
                updater.enable = true;
                daemon.enable = true;
                daemon.settings = { };
                fangfrisch.enable = true;
                updater.settings = { };
                updater.interval = "hourly";
                updater.frequency = 12;
                scanner.scanDirectories = [
                  "/home"
                  "/var/lib"
                  "/tmp"
                  "/etc"
                  "/var/tmp"
                ];
                scanner.interval = "*-*-* 04:00:00";
                fangfrisch.settings = {
                  sanesecurity = {
                    enabled = "yes";
                    prefix = "https://mirror.rollernet.us/sanesecurity/";
                  };
                };
              };

              dbus.enable = true;

              desktopManager.cosmic.enable = true;
              displayManager.cosmic-greeter.enable = true;

              dnsmasq.enable = false;

              expressvpn.enable = true;

              flatpak.enable = true;

              fail2ban = {
                banaction = "nftables-multiport";
                bantime-increment.enable = true;
                bantime-increment.rndtime = "8m";
                enable = true;
                packageFirewall = "${pkgs.nftables}";

                jails = {
                  sshd = {
                    settings = {
                      action = ''nftables-allports[name=sshd]'';
                      bantime = "10m";
                      enabled = true;
                      filter = "sshd";
                      findtime = "10m";
                      logpath = "journalctl -u sshd -o cat";
                      maxretry = 5;
                    };
                  };
                };
              };

              fstrim.enable = true;

              # firmware update daemon
              fwupd.enable = true;

              printing = {
                allowFrom = [ "localhost" ];
                browsing = false;
                defaultShared = false;
                #drivers = with pkgs; [ gutenprint epson-escpr epson-escpr2 ];
                drivers = with pkgs; [ gutenprint ];
                enable = true;
                listenAddresses = [ "localhost:631" ];
                logLevel = "debug";
                openFirewall = true;  # 631, not sure about the web interface yet
                startWhenNeeded = true;
                webInterface = true;
                cups-pdf.enable = true;
              };

              power-profiles-daemon.enable = true;
              upower.enable = true;

              xserver = {
                # Required for DE to launch.
                enable = true;

                # Exclude default X11 packages I don't want.
                excludePackages = with pkgs; [ xterm ];
              };

              # Load nvidia driver for Xorg and Wayland
              xserver.videoDrivers = ["nvidia"];

              locate.enable = true;
              locate.package = pkgs.plocate;

              lvm.enable = true;

              # Enable the OpenSSH daemon.
              openssh.enable = true;
            };

            systemd = {

              # Override the auditd systemd service, so that we can actually configured
              # the daemon.
              # services.auditd = {
              #   description = "Linux Audit daemon";

              #   wantedBy = [ "sysinit.target" ];
              #   after = [ "local-fs.target" "systemd-tmpfiles-setup.service" ];
              #   before = [ "sysinit.target" "shutdown.target" ];
              #   conflicts = [ "shutdown.target" ];

              #   environment = {
              #     LOCALE_ARCHIVE = "${pkgs.glibcLocales}/lib/locale/locale-archive";
              #     TZDIR = "${pkgs.tzdata}/share/zoneinfo";
              #   };

              #   preStart = "${pkgs.coreutils}/bin/mkdir -p /var/log/audit";
              # };

              services.lockBoot = {
                description = "Manage the encrypted /boot partition";
                wantedBy = [ "multi-user.target" ];
                after = [ "multi-user.target" ];
                path = with pkgs; [
                  util-linux      # For mountpoint and umount
                  coreutils       # For basic utilities like rm
                  cryptsetup      # For cryptsetup commands
                  systemd         # For systemd-cat
                  psmisc          # For fuser
                ];
                serviceConfig = {
                  Type = "oneshot";
                  RemainAfterExit = true;
                };
                script = ''
                  #!${pkgs.bash}/bin/bash

                  # Graceful attempts to unmount:
                  umount /boot/EFI >& /dev/null || true
                  umount /boot >& /dev/null || true

                  # Function to check and log open file handles
                  checkAndLog() {
                    mountpoint=$1
                    if mountpoint -q $mountpoint; then
                      procs=$(fuser -m $mountpoint 2>/dev/null) || true
                      if [ -n "$procs" ]; then
                        echo "Processes using $mountpoint: $procs" | systemd-cat -p info -t lockBoot
                      fi
                    fi
                  }

                  checkAndLog /boot/EFI
                  checkAndLog /boot

                  # Forceful unmount if still needed
                  mountpoint -q /boot/EFI && umount -l /boot/EFI || true
                  mountpoint -q /boot && umount -l /boot || true

                  # Close encrypted volume
                  if [ -e /dev/mapper/boot_crypt ]; then
                    cryptsetup luksClose boot_crypt || {
                      echo "Error: Failed to lock boot_crypt. Ensure all file handles are closed." | systemd-cat -p err -t lockBoot
                    }
                  fi
                '';
                restartIfChanged = false;  # Deny the insanity.
              };

              services."set-lvm-readahead" = {
                description = "Set read-ahead for LVM LV to optimize performance";
                wants = [ "local-fs.target" ];
                path = [ pkgs.lvm2 ];
                script = ''
                lvchange --readahead 2048 /dev/nix/tmp
                lvchange --readahead 2048 /dev/nix/var
                lvchange --readahead 2048 /dev/nix/root
                lvchange --readahead 2048 /dev/nix/home
                '';
                serviceConfig.Type = "oneshot";
                serviceConfig.RemainAfterExit = true;
              };
            };

            # Prevent all containers from restarting on boot
            systemd.services.docker = {
              # Inherit the default behavior first
              overrideStrategy = "asDropin"; # Makes it a drop-in override
              serviceConfig = {
                ExecStartPost = lib.mkAfter ''${pkgs.bash}/bin/bash -c "for n in $(docker ps -aq); do docker update --restart=no $n || true; done;"'';
              };
            };

            swapDevices = [
              {
                device = "/dev/nix/swap";
                discardPolicy = "both";
              }
            ];

            # system.activationScripts.userGitConfig = let
            #   userGitConfigs = [
            #     {
            #         user = "djshepard";
            #         name = "David Shepard";
            #         email = "daveman1010220@gmail.com";
            #         smtpPass = secrets.GIT_SMTP_PASS;
            #     }
            #   ];
            #   createGitConfigScript = userCfg:
            #     import ./activation_scripts/git_config.nix {
            #       inherit (userCfg) user name email smtpPass;
            #     };
            # in {
            #   text = lib.concatMapStringsSep "\n" createGitConfigScript userGitConfigs;
            #   deps = [ ];
            # };

            # Set timezone to US Eastern Standard Time
            time.timeZone = "America/New_York";

            # Define a user account. Don't forget to set a password with ‘passwd’.
            users.users.djshepard = {
              isNormalUser = true;

              # 'mkpasswd'
              hashedPassword = ''$y$j9T$TsZjcgKr0u3TvD1.0de.W/$c/utzJh2Mkg.B38JKR7f3rQprgZ.RwNvUaoGfE/OD8D'';
              extraGroups = [ "wheel" "mlocate" "docker" "systemd-journal" "libvirtd" "kvm" ]; # Enable ‘sudo’ for the user.
              shell = pkgs.fish;
              subUidRanges = [
                {
                  startUid = 100000;
                  count = 65536;
                }
              ];
              subGidRanges = [
                {
                  startGid = 100000;
                  count = 65536;
                }
              ];
            };

            users.groups.mlocate = {};

            virtualisation = {
              containerd.enable = true;
              libvirtd.enable = true;
              podman = {
                enable = true;
              };
              docker = {
                enable = true;
                daemon.settings = {
                    iptables = false;
                    ip-forward = true;
                    live-restore = false;
                };
              };
            };

            # System copy configuration
            system.copySystemConfiguration = false;

            # NixOS state version
            system.stateVersion = "24.05";
          })

          # Additional modules
          nixos-cosmic.nixosModules.default
        ];
      };
    };
  };
}
