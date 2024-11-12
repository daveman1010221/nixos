# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:
 
{
  # Set the GTK and icon themes (Yaru theme might need to be installed manually or substituted)

  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

    nix = {
      extraOptions = ''
        experimental-features = nix-command flakes
      '';
      package = pkgs.nixVersions.stable;
      settings.experimental-features = [ "nix-command" "flakes" ];
    };

  nixpkgs = {
    config = {
      allowUnfree = true;
      nvidia.acceptLicense = true;

      overlays = [
        (self: super: {
          nvim-treesitter = super.vimPlugins.nvim-treesitter.overrideAttrs (oldAttrs: {
            buildInputs = oldAttrs.buildInputs ++ [ self.libunwind ];
          });
        })
      ];
    };
  };

  boot = {
    # Configure the kernel
    kernelPackages = pkgs.linuxPackages_latest;
    kernelParams = [
    "intel_iommu=on"
    "intel_idle.max_cstate=4"
    "i8042.unlock"
    "lockdown=confidentiality"
    "mitigations=auto"
    "modprobe.blacklist=nouveau"
    "pci=realloc"
    "zswap.compressor=lzo"
    "zswap.enabled=1"
    "zswap.max_pool_percent=10"
    "seccomp=1"
    ];

    initrd = {
      # Ensure the initrd includes necessary modules for encryption, RAID, and filesystems
      availableKernelModules = [
        "aesni_intel"
        "ahci"
	"cryptd"
	"crypto"
        "crypto_simd"
        "dm_crypt"
        "dm_mod"
        "ext4"
        "nls_cp437"
        "nls_iso8859_1"
        "nvme"
        "raid0"
        "sdhci_pci"
        "sd_mod"
        "uas"
        "usbcore"
        "usb_storage"
        "vfat"
	"xhci_hcd"
        "xhci_pci"
      ];

      # Define LUKS devices, including the encrypted /boot and NVMe devices
      # EDIT
      luks = {
        devices = {
          boot_crypt = {
            # sdb2 UUID (pre-luksOpen)
            device = "/dev/disk/by-uuid/ed470d64-56da-4624-8080-bc736a64e27f";
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
            device = "/dev/disk/by-id/nvme-eui.ace42e00310a1b372ee4ac0000000001";
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
            device = "/dev/disk/by-id/nvme-eui.ace42e00310a1b382ee4ac0000000001";
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

      supportedFilesystems = ["ext4" "vfat" ];
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

  # System-wide package list
  environment.systemPackages = with pkgs; [
    atuin
    babelfish
    bat
    bottom
    bonnie
    btop
    cryptsetup
    cups
    deja-dup
    delta
    direnv
    doas
    dosfstools # Provides mkfs.vfat for EFI partition
    e2fsprogs # Provides mkfs.ext4
    efibootmgr
    efitools
    efivar
    epsonscan2
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
    git-up
    glmark2
    glxinfo
    gnome-calculator
    gnome-calendar
    gnome-common
    gnome-disk-utility
    gnomeExtensions.dash-to-dock
    gnomeExtensions.dock-from-dash
    gnomeExtensions.gtk4-desktop-icons-ng-ding
    gnome-font-viewer
    gdm
    gnome-applets
    gnome-backgrounds
    gnome-bluetooth
    gnome-characters
    gnome-clocks
    gnome-color-manager
    gnome-control-center
    gnome-initial-setup
    gnome-nettool
    gnome-power-manager
    gnome-session
    gnome-settings-daemon
    gnome-shell
    gnome-shell-extensions
    gnome-keyring
    mutter
    networkmanager-iodine
    networkmanager-openvpn
    networkmanager-vpnc
    gnome-screenshot
    gnome-system-monitor
    gnome-terminal
    gnome-themes-extra
    gnome-tweaks
    gpaste
    grc
    grub2_efi
    gtkimageview
    gucharmap
    jq
    kitty
    kitty-img
    kitty-themes
    libcanberra-gtk3
    libgnome-keyring
    llvmPackages_18.clangUseLLVM
    llvmPackages_18.libunwind
    lolcat
    lsof
    lvm2 # Provides LVM tools: pvcreate, vgcreate, lvcreate
    mdadm # RAID management
    mlocate
    nautilus
    neo-cowsay
    neofetch
    (hiPrio neovim)
    nerdfonts
    nftables
    nix-index
    nvtopPackages.intel
    openssl
    parted
    protonvpn-gui
    pwgen
    pyenv
    python312Full
    python312Packages.jsonschema
    ripgrep
    seahorse
    signal-desktop-beta
    simple-scan
    sqlite
    starship
    sushi
    tmux
    tree
    tree-sitter
    (vscode-with-extensions.override {
      vscodeExtensions = with vscode-extensions; [
        bbenoist.nix
        ms-python.python
        ms-azuretools.vscode-docker
        ms-vscode-remote.remote-ssh
      ] ++ pkgs.vscode-utils.extensionsFromVscodeMarketplace [
        {
          name = "remote-ssh-edit";
          publisher = "ms-vscode-remote";
          version = "0.47.2";
          sha256 = "1hp6gjh4xp2m1xlm1jsdzxw9d8frkiidhph6nvl24d0h8z34w49g";
        }
      ];
    })
    wordbook
    wasmer
    wasmer-pack
    wget
    (hiPrio xwayland)
    yaru-theme
    zellij
  ];

  fileSystems = {
    # Define filesystems for /boot and /boot/EFI
    # dm0 UUID (post-luksOpen)
    # EDIT
    "/boot" =
      { device = "/dev/disk/by-uuid/5b605f2d-f67f-4744-8f36-046e2d55bfb9";
        fsType = "ext4";
        neededForBoot = true;
      };

    # UUID
    # EDIT
    "/boot/EFI" =
      { device = "/dev/disk/by-uuid/7EF5-FFA3";
        fsType = "vfat";
        options = [ "umask=0077" ]; # Ensure proper permissions for the EFI partition
      };
  };

  hardware = {
    graphics.enable = true;

    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    bumblebee.enable = false;

    nvidiaOptimus.disable = false;
    nvidia = {
      prime.allowExternalGpu = true;
      prime.offload.enable = true;
      prime.offload.enableOffloadCmd = true;
      prime.nvidiaBusId = "PCI:1:0:0";
      prime.intelBusId = "PCI:0:2:0";
      prime.reverseSync.enable = true;

      dynamicBoost.enable = false;

      open = false;

      # Modesetting is required.
      modesetting.enable = true;

      # Nvidia power management. Experimental, and can cause sleep/suspend to
      # fail. Enable this if you have graphical corruption issues or
      # application crashes after waking up from sleep. This fixes it by saving
      # the entire VRAM memory to /tmp/ instead of just the bare essentials.
      powerManagement.enable = true;

      # Fine-grained power management. Turns off GPU when not in use.
      # Experimental and only works on modern Nvidia GPUs (Turing or newer).
      powerManagement.finegrained = true;

      # Enable the Nvidia settings menu,
      # accessible via `nvidia-settings`.
      nvidiaSettings = true;

      # Optionally, you may need to select the appropriate driver version for
      # your specific GPU.
      package = config.boot.kernelPackages.nvidiaPackages.beta;
    };
  };

  networking = {
    hostName = "precisionws";

    firewall.enable = false;

    networkmanager.enable = true;

    nftables.checkRuleset = true;
    nftables.enable = true;
    nftables.flushRuleset = true;
    #nftables.ruleset = ''
    #'';
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

      interactiveShellInit = import /etc/nixos/config.fish.nix { inherit pkgs; };

    };

    git = {
        enable = true;
        lfs.enable = true;
        package = "${pkgs.gitFull}";
        #prompt.enable = true;
    };

    gnome-terminal.enable = true;

    gnupg.agent = {
      enable = true;
      enableSSHSupport = true;
    };

    # Some programs need SUID wrappers, can be configured further or are
    # started in user sessions.
    mtr.enable = true;

    neovim = {
      configure = {
        packages.myVimPackage = with pkgs.vimPlugins; {
          start = [
            ctrlp
            fugitive
            gruvbox-nvim
            intero-neovim
            lazy-nvim
            markdown-preview-nvim
            neoconf-nvim
            neodev-nvim
            nvim-tree-lua
            nvim-treesitter
            nvim-treesitter-parsers.mermaid
            nvim-web-devicons
            vim-tmux-focus-events
            vim-plug
            which-key-nvim
          ];
	};
        customRC = import /etc/nixos/init.lua.nix { inherit pkgs; };
      };

      defaultEditor = true;
      enable = true;

      viAlias = true;
      vimAlias = true;

      withPython3 = true;
      withRuby = true;
    };

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
        set -ga terminal-overrides '*:Ss=\E[%p1%d q:Se=\E[ q'

        set-environment -g COLORTERM "truecolor"

        # easy-to-remember split pane commands
        bind | split-window -h -c "#{pane_current_path}"
        bind - split-window -v -c "#{pane_current_path}"
        bind c new-window -c "#{pane_current_path}"
      '';
    };

    gpaste.enable = true;

    xwayland.enable = true;
  };

  powerManagement = {
    enable = true;
  };

  security = {
    doas = {
      enable = true;
      wheelNeedsPassword = true;
    };
  };

  services = {
    avahi = {  # Necessary for CUPS local network printer discovery, probably some other stuff, too.
      wideArea = true;  # Not sure about this one yet, but true is the default.
      publish.enable = false;  # Just don't publish unnecessarily.
      publish.domain = false;  # Don't announce yourself on the local network unless needed.
      publish.addresses = false;  # Publish all local IP addresses. I assume this means only those of allowed interfaces.
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

    # firmware update daemon
    fwupd.enable = true;
    #fwupd.package = pkgs.fwupd-efi;

    gnome = {
      core-os-services.enable = true;
      core-shell.enable = true;
      core-utilities.enable = true;
      gnome-initial-setup.enable = true;
      gnome-keyring.enable = true;
      gnome-online-accounts.enable = true;
      gnome-settings-daemon.enable = true;
      sushi.enable = true;
      tinysparql.enable = true;
      localsearch.enable = true;
    };

    #lorri.enable = true;

    printing = {
      allowFrom = [ "localhost" ];
      # browsed.enable = true;
      browsing = false;
      defaultShared = false;
      drivers = with pkgs; [ gutenprint epson-escpr epson-escpr2 ];
      enable = true;
      listenAddresses = [ "localhost:631" ];
      logLevel = "debug";
      openFirewall = true;  # 631, not sure about the web interface yet
      startWhenNeeded = true;
      # stateless = true;
      webInterface = true;
      cups-pdf.enable = true;
    };

    power-profiles-daemon.enable = true;
    upower.enable = true;

    xserver = {
      # Required for DE to launch.
      enable = true;

      # Enable Desktop Environment.
      desktopManager.gnome.enable = true;

      # Exclude default X11 packages I don't want.
      excludePackages = with pkgs; [ xterm ];

      # Configure GNOME desktop environment with GDM3 display manager
      displayManager = {
        gdm = {
          enable = true;
          wayland = true;
        };
      };
    };

    displayManager.defaultSession = "gnome";

    # Load nvidia driver for Xorg and Wayland
    xserver.videoDrivers = ["nvidia"];

    locate.enable = true;
    locate.package = pkgs.mlocate;
    locate.localuser = null;

    lvm.enable = true;

    # Enable the OpenSSH daemon.
    openssh.enable = true;
  };

  systemd = {
    # systemd service to activate LVM volumes
    services."lvm" = {
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      unitConfig = {
        Description = "Activate LVM volumes";
      };
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.lvm2.bin}/bin/lvm vgchange -ay";
      };
    };

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
      restartIfChanged = false;	# Deny the insanity.
    };

    # This service only begins to make sense if you have an array with
    # redundancy. I.e., for a raid zero setup, mdadm will simply exit.
    #services."mdadmMonitor" = {
      #description = "mdadm monitor";
      #after = [ "network.target" ];
      #wantedBy = [ "multi-user.target" ];
      #serviceConfig = {
        #ExecStart = "${pkgs.mdadm}/bin/mdadm --monitor --scan -10m --mail='daveman1010220@gmail.com'";
	#Restart = "always";
      #};
    #};


    services."set-lvm-readahead" = {
      description = "Set read-ahead for LVM LV to optimize performance";
      after = [ "lvm.service" ];
      wants = [ "local-fs.target" ];
      path = [ pkgs.lvm2 ];
      script = ''
      lvchange --readahead 1024 /dev/nix/tmp
      lvchange --readahead 1024 /dev/nix/var
      lvchange --readahead 1024 /dev/nix/root
      lvchange --readahead 1024 /dev/nix/home
      '';
      serviceConfig.Type = "oneshot";
      serviceConfig.RemainAfterExit = true;
    };
  };

  # Enable sound.
  #sound.enable = true;

  swapDevices = [
    {
      device = "/dev/nix/swap";
      discardPolicy = "both";
    }
  ];

  system.activationScripts.userGitConfig = let
    userGitConfigs = [
      { user = "djshepard"; name = "David Shepard"; email = "daveman1010220@gmail.com"; }
      # Add additional users as needed
    ];
    createGitConfigScript = userConfig: ''
      # Check if .gitconfig exists for user ${userConfig.user}
      if [ ! -f /home/${userConfig.user}/.gitconfig ]; then
        echo "Creating .gitconfig for ${userConfig.user}"
        cat > /home/${userConfig.user}/.gitconfig <<EOF
[user]
  name = ${userConfig.name}
  email = ${userConfig.email}
[init]
  defaultBranch = main
[credential]
  helper = store
EOF
        # Ensure the file ownership is correct
        chown ${userConfig.user} /home/${userConfig.user}/.gitconfig
        echo "********* Remember to create your ~/.git-credentials file with your token *********"
      else
        echo ".gitconfig already exists for ${userConfig.user}, skipping..."
      fi
    '';
  in {
    text = lib.concatMapStringsSep "\n" createGitConfigScript userGitConfigs;
    deps = [ ];
  };

  # Set timezone to US Eastern Standard Time
  time.timeZone = "America/New_York";

  users.mutableUsers = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.djshepard = {
    isNormalUser = true;

    # 'mkpasswd'
    hashedPassword = ''$y$j9T$TsZjcgKr0u3TvD1.0de.W/$c/utzJh2Mkg.B38JKR7f3rQprgZ.RwNvUaoGfE/OD8D'';
    extraGroups = [ "wheel" "mlocate" ]; # Enable ‘sudo’ for the user.
    shell = pkgs.fish;
  };
  
  users.groups.mlocate = {};


  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "24.05"; # Did you read the comment?
}
