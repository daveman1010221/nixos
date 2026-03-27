{ pkgs, lib, ... }:

{
  ### ────────────────────────────────
  ### Kernel & scheduler baseline
  ### ────────────────────────────────
  boot.kernel.sysctl = {
    "kernel.sched_autogroup_enabled" = 1;
    "kernel.sched_child_runs_first" = 0;
  };

  boot.kernelParams = [
    "amd_pstate=active"
    "usbcore.autosuspend=-1"
    "pcie_aspm=on"
  ];

  services.power-profiles-daemon.enable = true;

  ### ────────────────────────────────
  ### system76-scheduler foreground bias
  ### ────────────────────────────────
  #
  # Replaces ananicy-cpp. No BPF, no semaphores, no segfaults.
  #
  # system76-scheduler tunes CFS latency parameters globally (responsive on AC,
  # conservative on battery) and assigns per-process nice/io priorities via
  # named profiles with process matchers.
  #
  # NOTE: foregroundBoost is disabled — it requires DE-side cooperation
  # (a GNOME shell extension or explicit Cosmic integration) to signal which
  # window is in the foreground. Without that signal it does nothing useful.
  # pipewireBoost works standalone and is kept.
  #
  # IO priority scale: 0 = highest, 7 = lowest (within a class).
  #
  services.system76-scheduler = {
    enable = true;
    useStockConfig = false;

    settings = {
      cfsProfiles = {
        enable = true;

        # On battery / default: modest latency, energy-friendly
        default = {
          latency = 6;
          nr-latency = 8;
          wakeup-granularity = 1.0;
          bandwidth-size = 5;
          preempt = "voluntary";
        };

        # On AC: tighten up CFS for desktop responsiveness
        responsive = {
          latency = 4;
          nr-latency = 10;
          wakeup-granularity = 0.5;
          bandwidth-size = 3;
          preempt = "full";
        };
      };

      processScheduler = {
        enable = true;
        useExecsnoop = false; # execsnoop requires kheaders — bad under hardened kernel
        refreshInterval = 10; # poll every 10s, matching old check_freq

        foregroundBoost.enable = false;

        pipewireBoost = {
          enable = true;
          profile = {
            nice = -6;
            ioClass = "best-effort";
            ioPrio = 2;
          };
        };
      };
    };

    # ── Process priority assignments ────────────────────────────────────
    #
    # Groups map roughly 1:1 to the old ananicy extraRules.
    # system76-scheduler matches by process name (executable basename).
    #
    assignments = {

      #──────────────────────────────────────────────────────────
      # Editors & terminals — high interactive priority
      #──────────────────────────────────────────────────────────
      editors = {
        nice = -8;
        ioClass = "best-effort";
        ioPrio = 3;
        matchers = [ "code" "zed" "nvim" ];
      };

      terminals = {
        nice = -8;
        ioClass = "best-effort";
        ioPrio = 3;
        matchers = [ "kitty" ];
      };

      #──────────────────────────────────────────────────────────
      # Browsers & comms
      #──────────────────────────────────────────────────────────
      browsers = {
        nice = -6;
        ioClass = "best-effort";
        ioPrio = 3;
        matchers = [ "librewolf" "microsoft-edge" ];
      };

      comms = {
        nice = -6;
        ioClass = "best-effort";
        ioPrio = 3;
        matchers = [ "signal-desktop" "zoom" "zoom-us" ];
      };

      #──────────────────────────────────────────────────────────
      # Cosmic compositor & core session — keep smooth
      #──────────────────────────────────────────────────────────
      cosmic-compositor = {
        nice = -5;
        ioClass = "best-effort";
        ioPrio = 4;
        matchers = [ "cosmic-comp" ];
      };

      cosmic-session = {
        nice = -3;
        ioClass = "best-effort";
        ioPrio = 4;
        matchers = [
          "cosmic-session"
          "cosmic-panel"
        ];
      };

      #──────────────────────────────────────────────────────────
      # Cosmic UX — launcher, workspaces, OSD: noticeable if they stutter
      #──────────────────────────────────────────────────────────
      cosmic-ux = {
        nice = -4;
        ioClass = "best-effort";
        ioPrio = 4;
        matchers = [
          "cosmic-launcher"
          "cosmic-workspaces"
          "cosmic-osd"
        ];
      };

      cosmic-ux-secondary = {
        nice = -3;
        ioClass = "best-effort";
        ioPrio = 4;
        matchers = [
          "cosmic-app-library"
          "cosmic-app-list"
          "cosmic-toplevel"
        ];
      };

      #──────────────────────────────────────────────────────────
      # Cosmic settings & notifications
      #──────────────────────────────────────────────────────────
      cosmic-settings = {
        nice = -2;
        ioClass = "best-effort";
        ioPrio = 5;
        matchers = [
          "cosmic-settings"
          "cosmic-settings-daemon"
          "cosmic-notifications"
          "xdg-desktop-portal-cosmic"
        ];
      };

      #──────────────────────────────────────────────────────────
      # Cosmic applets — panel interactions should feel crisp
      #──────────────────────────────────────────────────────────
      cosmic-applets-primary = {
        nice = -1;
        ioClass = "best-effort";
        ioPrio = 5;
        matchers = [
          "cosmic-applet-audio"
          "cosmic-applet-network"
          "cosmic-applet-notifications"
          "cosmic-applet-power"
          "cosmic-applet-time"
          "cosmic-files-applet"
        ];
      };

      cosmic-applets-secondary = {
        nice = 0;
        ioClass = "best-effort";
        ioPrio = 6;
        matchers = [
          "cosmic-applet-bluetooth"
          "cosmic-applet-input-sources"
          "cosmic-applet-status-area"
          "cosmic-applet-tiling"
          "cosmic-applet-minimize"
          "cosmic-panel-button"
        ];
      };

      #──────────────────────────────────────────────────────────
      # Cosmic support processes
      #──────────────────────────────────────────────────────────
      cosmic-support = {
        nice = 0;
        ioClass = "best-effort";
        ioPrio = 5;
        matchers = [
          "cosmic-bg"
          "cosmic-greeter"
          "cosmic-greeter-daemon"
        ];
      };

      cosmic-idle = {
        nice = 8;
        ioClass = "idle";
        matchers = [ "cosmic-idle" ];
      };

      #──────────────────────────────────────────────────────────
      # Audio & video — stable, not bursty
      #──────────────────────────────────────────────────────────
      # pipewire itself is handled by pipewireBoost above.
      audio-clients = {
        nice = 0;
        ioClass = "best-effort";
        ioPrio = 4;
        matchers = [
          "wireplumber"
          "cosmic-player"
        ];
      };

      video = {
        nice = 0;
        ioClass = "best-effort";
        ioPrio = 5;
        matchers = [ "cheese" "simple-scan" ];
      };

      #──────────────────────────────────────────────────────────
      # Network & VPN — don't IO-starve these
      #──────────────────────────────────────────────────────────
      network = {
        nice = 0;
        ioClass = "best-effort";
        ioPrio = 4;
        matchers = [ "NetworkManager" ];
      };

      vpn = {
        nice = 5;
        ioClass = "best-effort";
        ioPrio = 5;
        matchers = [ "mullvad-daemon" ];
      };

      #──────────────────────────────────────────────────────────
      # System services
      #──────────────────────────────────────────────────────────
      printing = {
        nice = 5;
        ioClass = "best-effort";
        ioPrio = 6;
        matchers = [ "cupsd" ];
      };

      firmware = {
        nice = 10;
        ioClass = "idle";
        matchers = [ "fwupd" "fwupd-efi" ];
      };

      #──────────────────────────────────────────────────────────
      # Build tools — deprioritize the desktop-janking hogs
      #──────────────────────────────────────────────────────────
      nix-builds = {
        nice = 10;
        ioClass = "best-effort";
        ioPrio = 6;
        matchers = [
          "nix"
          "nix-daemon"
          "nix-store"
          "cmake"
          "meson"
        ];
      };

      compilers = {
        nice = 12;
        ioClass = "best-effort";
        ioPrio = 6;
        matchers = [
          "rustc"
          "cc1"
          "cc1plus"
          "clang"
          "gcc"
          "ld"
          "ld.lld"
          "collect2"
          "ninja"
          "make"
        ];
      };

      compressors = {
        nice = 12;
        ioClass = "best-effort";
        ioPrio = 7;
        matchers = [ "zstd" "xz" "gzip" "bzip2" ];
      };

      # Container infra: deprioritize CPU but keep IO reasonable —
      # ioClass=idle here tanks interactive container-backed workflows.
      containers = {
        nice = 8;
        ioClass = "best-effort";
        ioPrio = 6;
        matchers = [ "dockerd" "containerd" "buildkitd" "podman" ];
      };

      # kubectl/kind are interactive tools, keep them snappy
      kube-tools = {
        nice = 0;
        ioClass = "best-effort";
        ioPrio = 4;
        matchers = [ "kubectl" "kind" ];
      };

      #──────────────────────────────────────────────────────────
      # Background indexers
      #──────────────────────────────────────────────────────────
      indexers = {
        nice = 15;
        ioClass = "idle";
        matchers = [
          "nix-index"
          "nix-index-daemon"
          "updatedb"
        ];
      };

      # LSP touches disk but affects editor latency — keep IO normal
      lsp = {
        nice = 8;
        ioClass = "best-effort";
        ioPrio = 6;
        matchers = [ "nixd" "nix-locate" ];
      };
    };
  };
}
