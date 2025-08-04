{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs = {
        nixpkgs.follows = "nixpkgs";
      };
    };
    myNeovimOverlay = {
      url = "github:daveman1010221/nix-neovim";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-utils.url = "github:numtide/flake-utils";
      };
    };
    dotacatFast = {
        url = "github:daveman1010221/dotacat-fast";
    };
    secrets-empty = {
      url   = "path:./secrets-empty.json";   # ← lives in repo
      flake = false;
    };
  };

  # The audit package needs an overlay to get the permissions right for
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

  outputs = { self, nixpkgs, rust-overlay, myNeovimOverlay, dotacatFast, secrets-empty }:
  let
    lib = nixpkgs.lib;
    system = "x86_64-linux";

    pkgs = import nixpkgs { system = "x86_64-linux"; };

    # Step 1: Dynamically import MOK certs into the Nix store
    certsDerivation = pkgs.runCommand "certs" {} ''
      mkdir -p $out
      cp ${./kernel/MOK.pem} $out/MOK.pem
      cp ${./kernel/MOK.priv} $out/MOK.priv
    '';

    # Step 2: Read the certs from the store after the derivation runs
    mokPem = builtins.readFile "${certsDerivation}/MOK.pem";
    mokPriv = builtins.readFile "${certsDerivation}/MOK.priv";

    # Step 3: Ensure they are properly defined
    myPubCert = builtins.toFile "MOK.pem" mokPem;
    myPrivKey = builtins.toFile "MOK.priv" mokPriv;

    myConfig = builtins.toFile ".config" (builtins.readFile (builtins.toString ./kernel/.config));

    # list of host folders
    hostNames = builtins.attrNames (
      lib.filterAttrs 
        (_: t: t == "directory")
        (builtins.readDir ./hosts)
    );

    # ── discover built-in modules ───────────────────────────────────────
    moduleDir = ./flakes/modules;

    discoveredModules =
      lib.sort (a: b: (toString a) < (toString b))  # keep a reproducible order
        (lib.filter (p: lib.hasSuffix ".nix" (toString p))
          (lib.filesystem.listFilesRecursive moduleDir));

    # common modules for every machine
    commonModules = discoveredModules ++
      [
        # ./flakes/modules/base-desktop.nix ← when you split the giant block
      ];

    # overlays shared by all hosts
    commonOverlays = [
      rust-overlay.overlays.default
      myNeovimOverlay.overlays.default
      (import ./flakes/overlays/git-hooks.nix)
    ];

    # helper function: overlayed nixpkgs for any host
    pkgsFor = extraOverlays: sys:
      import nixpkgs {
        system = sys;
        overlays = commonOverlays ++ extraOverlays;
        config = {
          allowUnfree = true;
          doCheck = false;  # This doesn't seem to help, at least in all circumstances. This disables running test during package builds, globally.
          nvidia = {
            acceptLicense = true;
          };
        };
      };

    # Helper to build a host
    mkHost = hostName:
      let
        hostDir   = ./hosts/${hostName};

        # ── gather host-specific modules ─────────────────────────────────
        hostModuleDir = hostDir + "/modules";
        
        hostModules =
          if builtins.pathExists hostModuleDir
          then
            lib.filter
              (p: lib.hasSuffix ".nix" p)
              (lib.filesystem.listFilesRecursive hostModuleDir)
          else
            [ ];

        # ── gather host-specific overlays ────────────────────────────────
        hostOverlays =
          let
            overlayDir = hostDir + "/overlays";

            # pick every *.nix that returns an overlay function
            # keep only the first-level directory .nix files
            overlayFiles =
            if builtins.pathExists overlayDir then
              lib.filter
                (p: lib.hasSuffix ".nix" p && 
                     dirOf p == overlayDir &&
                     baseNameOf p != "custom-kernel.nix")
                (lib.filesystem.listFilesRecursive overlayDir)
            else
              [ ];   # no overlays for this host
          in
            # import every *.nix in overlays/
            map import overlayFiles
            # plus custom kernel overlay if it exists
            ++ lib.optional (builtins.pathExists (hostDir + "/overlays/custom-kernel.nix"))
                 (import (hostDir + "/overlays/custom-kernel.nix") {
                   inherit myConfig myPubCert myPrivKey;
                 });

        pkgsForHost = pkgsFor hostOverlays system;

        myPackages = import (hostDir + /packages.nix) {
          pkgs = pkgsForHost;
          inherit rust-overlay dotacatFast system;
        };

        # read whatever the caller provided under the name `secrets-empty`
        secrets = builtins.fromJSON (builtins.readFile secrets-empty);

      in nixpkgs.lib.nixosSystem
      {
        inherit system;
        # <<< make the system use the overlayed set >>>
        pkgs = pkgsForHost;
        specialArgs = {
            inherit secrets pkgsFor myPackages self lib;
            pkgsForHost = pkgsForHost;   # the set we built above
            hostPkgs    = pkgsForHost;   # if something still expects plain ‘pkgs’
        };
        modules = commonModules ++ [
          (hostDir + /hardware.nix)        # or hardware-configuration.nix

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
            hostname = hostName;
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
            };

            nix = {
              settings = {
                substituters = [
                ];
                trusted-public-keys = [
                ];
                trusted-users = [ "root" "djshepard" ];
              };
              extraOptions = ''
                experimental-features = nix-command flakes
              '';
              settings.experimental-features = [ "nix-command" "flakes" ];
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
                {
                  ## Provide a complete templates directory that already
                  ## contains the hook – copy it so GC can’t break the path.
                  "git-templates" = {
                    source = pkgs.runCommand "git-templates" {} ''
                      mkdir -p "$out/hooks"
                      install -m0755 "${pkgs.commitMsgHook}/bin/commit-msg-hook" \
                                     "$out/hooks/commit-msg"
                    '';
                  };
                }
              ];

              systemPackages = myPackages.myPkgs;

              sessionVariables.COSMIC_DATA_CONTROL_ENABLED = 1;

            };

            networking = {
              hostName = hostName;
              firewall.enable = false;
              networkmanager.enable = true;

              nftables = {
                checkRuleset = true;
                enable = true;
                flushRuleset = true;
                ruleset = builtins.readFile ./firewall/nftables.nft;
              };
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
                package = pkgs.gitFull;

                # Point git at the templates we drop in /etc below.
                config.init.templatedir = "/etc/git-templates";
              };

              gnupg.agent = {
                enable = true;
                enableSSHSupport = true;
              };

              # Some programs need SUID wrappers, can be configured further or
              # are started in user sessions.
              mtr.enable = true;

              tmux = {
                enable = true;
                shortcut = "a";
                aggressiveResize = true;  # Disable for iTerm
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
              tpm2.applyUdevRules = true;
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
            };

            services = {
              # Avahi is necessary for CUPS local network printer discovery,
              # probably some other stuff, too.
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
              desktopManager.cosmic.xwayland.enable = true;

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

              # Always strikes me as an odd place for this attribute.
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

              locate.enable = true;
              locate.package = pkgs.plocate;

              lvm.enable = true;

              # Enable the OpenSSH daemon.
              openssh.enable = true;
            };

            systemd.user.services.xdg-desktop-portal-cosmic = {
              enable = true;
              description = "xdg-desktop-portal for COSMIC";
              wantedBy = [ "graphical-session.target" ];
              after = [ "xdg-desktop-portal.service" ];
              partOf = [ "graphical-session.target" ];

              serviceConfig = {
                ExecStart = "${myPackages.wrapped-portal}/bin/xdg-desktop-portal-cosmic-wrapper";
                Restart = "on-failure";
                RestartSec = 3;
              };
            };

            systemd = {
              tpm2.enable = false;
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

            xdg.portal.enable = true;
            xdg.portal.extraPortals = [
              pkgs.xdg-desktop-portal-cosmic
            ];
            xdg.portal.config.common.default = "*";

            # System copy configuration
            system.copySystemConfiguration = false;

            # NixOS state version
            system.stateVersion = "24.05";
          })
        ]
        ++ hostModules;                 # every per–host extra module
      };
  in {
    nixosConfigurations =
      builtins.listToAttrs
        (map (hn: { name = hn; value = mkHost hn; }) hostNames);
  };
}
