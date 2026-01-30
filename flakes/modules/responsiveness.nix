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
  ### ananicy-cpp foreground bias
  ### ────────────────────────────────
  services.ananicy = {
    enable = true;
    package = pkgs.ananicy-cpp;
    rulesProvider = pkgs.ananicy-rules-cachyos;

    serviceConfig = {
      # If ananicy-cpp leaves behind a stale semaphore, clear it once
      # before starting. Crucially: failure to remove it should NOT fail
      # the service when it doesn't exist.
      ExecStartPre = lib.mkForce [
        # "reset" any packaged ExecStartPre (if present)
        ""
        # Best-effort cleanup; ignore errors like "No such file or directory"
        "${pkgs.bash}/bin/bash -lc '${pkgs.ananicy-cpp}/bin/ananicy-cpp --force-remove-semaphore start >/dev/null 2>&1 || true'"
      ];

      Delegate = "yes";
      ProtectControlGroups = false;
      ProtectKernelTunables = false;
      ReadWritePaths = [ "/sys/fs/cgroup" ];

      # The packaged unit uses:
      #   ExecStart=.../ananicy-cpp start
      #
      # Under systemd, calling the "start" subcommand is a footgun:
      # it can daemonize / create a background instance / pidfile logic,
      # and then subsequent starts see "already running" and exit 1,
      # causing an infinite restart loop.
      #
      # ananicy-cpp requires an action positional (e.g. "start").
      # We also defensively clear stale semaphore state that can cause
      # "Ananicy Cpp is already running!" even when no process exists.
      #
      # NOTE: The empty string entry is systemd's "reset ExecStart" trick.
      # Actual start: no cleanup flags, just start.
      ExecStart = lib.mkForce [
        ""
        "${pkgs.ananicy-cpp}/bin/ananicy-cpp start"
      ];

      # Keep it simple; upstream unit already uses Type=simple.
      Type = lib.mkForce "simple";

      # While validating, don't restart forever on clean exit(1) loops.
      Restart = lib.mkForce "on-failure";
      RestartSec = lib.mkForce 2;
    };

    settings = {
      verbose = true;
      check_freq = 10;

      apply_cgroup = true;
      cgroup_load = true;
      cgroup_root = lib.mkForce "system.slice/ananicy-cpp.service";
      cgroup_realtime_workaround = false;

      type_load = true;
      rule_load = true;
      apply_nice = true;
      apply_ioclass = true;
      apply_ionice = true;
      apply_sched = true;
      apply_oom_score_adj = true;
      check_disks_schedulers = true;
    };

    extraRules = [
      #─────────────────────────────
      # High-priority, interactive
      #─────────────────────────────
      # Keep CPU responsive, but don't let these bully disk with ionice=0.
      { name = "code";              nice = -8; ioclass = "best-effort"; ionice = 3; type = "editor"; }
      { name = "zed";               nice = -8; ioclass = "best-effort"; ionice = 3; type = "editor"; }
      { name = "nvim";              nice = -8; ioclass = "best-effort"; ionice = 3; type = "editor"; }
      { name = "kitty";             nice = -8; ioclass = "best-effort"; ionice = 3; type = "terminal"; }
      { name = "librewolf";         nice = -6; ioclass = "best-effort"; ionice = 3; type = "browser"; }
      { name = "microsoft-edge";    nice = -6; ioclass = "best-effort"; ionice = 3; type = "browser"; }
      { name = "signal-desktop";    nice = -6; ioclass = "best-effort"; ionice = 3; type = "comms"; }
      { name = "zoom";              nice = -6; ioclass = "best-effort"; ionice = 3; type = "comms"; }
      { name = "zoom-us";           nice = -6; ioclass = "best-effort"; ionice = 3; type = "comms"; }

      #─────────────────────────────
      # Cosmic processes — keep smooth
      #─────────────────────────────
      # Compositor smoothness is mostly CPU scheduling; don't over-tune IO here.
      { name = "cosmic-comp";       nice = -5; ioclass = "best-effort"; ionice = 4; type = "compositor"; }
      { name = "cosmic-session";    nice = -3; ioclass = "best-effort"; ionice = 4; type = "desktop"; }
      { name = "cosmic-panel";      nice = -3; ioclass = "best-effort"; ionice = 4; type = "desktop"; }
      { name = "cosmic-bg";         nice = 0;  ioclass = "best-effort"; ionice = 5; type = "service"; }
      { name = "cosmic-settings";   nice = 0;  ioclass = "best-effort"; ionice = 5; type = "service"; }
      { name = "xdg-desktop-portal-cosmic"; nice = 0; ioclass = "best-effort"; ionice = 5; type = "service"; }

      #─────────────────────────────
      # Cosmic desktop — additional processes
      #─────────────────────────────

      # Login / greeter path (keep stable, not "fast")
      { name = "cosmic-greeter-daemon"; nice = 0;  ioclass = "best-effort"; ionice = 5; type = "desktop"; }
      { name = "cosmic-greeter";        nice = 0;  ioclass = "best-effort"; ionice = 5; type = "desktop"; }

      # Core UX: these are the “if they stutter you notice” set
      { name = "cosmic-launcher";       nice = -4; ioclass = "best-effort"; ionice = 4; type = "desktop"; }
      { name = "cosmic-workspaces";     nice = -4; ioclass = "best-effort"; ionice = 4; type = "desktop"; }
      { name = "cosmic-osd";            nice = -4; ioclass = "best-effort"; ionice = 4; type = "desktop"; }
      { name = "cosmic-app-library";    nice = -3; ioclass = "best-effort"; ionice = 4; type = "desktop"; }
      { name = "cosmic-app-list";       nice = -3; ioclass = "best-effort"; ionice = 4; type = "desktop"; }

      # Settings/notifications are interactive but not latency-critical like the compositor
      { name = "cosmic-settings-daemon"; nice = -2; ioclass = "best-effort"; ionice = 5; type = "service"; }
      { name = "cosmic-notifications";   nice = -2; ioclass = "best-effort"; ionice = 5; type = "service"; }

      # Applets: lots of tiny processes; give them mild priority so panel interactions stay crisp
      { name = "cosmic-applet-audio";         nice = -1; ioclass = "best-effort"; ionice = 5; type = "desktop"; }
      { name = "cosmic-applet-network";       nice = -1; ioclass = "best-effort"; ionice = 5; type = "desktop"; }
      { name = "cosmic-applet-notifications"; nice = -1; ioclass = "best-effort"; ionice = 5; type = "desktop"; }
      { name = "cosmic-applet-power";         nice = -1; ioclass = "best-effort"; ionice = 5; type = "desktop"; }
      { name = "cosmic-applet-time";          nice = -1; ioclass = "best-effort"; ionice = 5; type = "desktop"; }

      # Other applets: keep neutral; they shouldn’t matter much
      { name = "cosmic-applet-bluetooth";      nice = 0; ioclass = "best-effort"; ionice = 6; type = "desktop"; }
      { name = "cosmic-applet-input-sources";  nice = 0; ioclass = "best-effort"; ionice = 6; type = "desktop"; }
      { name = "cosmic-applet-status-area";    nice = 0; ioclass = "best-effort"; ionice = 6; type = "desktop"; }
      { name = "cosmic-applet-tiling";         nice = 0; ioclass = "best-effort"; ionice = 6; type = "desktop"; }
      { name = "cosmic-applet-minimize";       nice = 0; ioclass = "best-effort"; ionice = 6; type = "desktop"; }

      # Panel helper procs (these are lightweight; don’t overfit)
      { name = "cosmic-panel-button";     nice = 0; ioclass = "best-effort"; ionice = 6; type = "desktop"; }

      # Files applet: can touch disk; keep it decent but not a bully
      { name = "cosmic-files-applet";     nice = -1; ioclass = "best-effort"; ionice = 5; type = "desktop"; }

      # Idle manager: this is not something you want competing with your actual work
      { name = "cosmic-idle";             nice = 8;  ioclass = "idle"; type = "service"; }

      # Pop launcher plugin used by Cosmic (toplevel integration)
      { name = "cosmic-toplevel";         nice = -2; ioclass = "best-effort"; ionice = 5; type = "desktop"; }

      #─────────────────────────────
      # Build / heavy work — deprioritize the actual hogs
      #─────────────────────────────
      # This is what makes your desktop jank: compilers, linkers, builders, compressors.
      { name = "nix";               nice = 10; ioclass = "best-effort"; ionice = 6; type = "build"; }
      { name = "nix-daemon";        nice = 10; ioclass = "best-effort"; ionice = 6; type = "build"; }
      { name = "nix-store";         nice = 10; ioclass = "best-effort"; ionice = 6; type = "build"; }
      { name = "rustc";             nice = 12; ioclass = "best-effort"; ionice = 6; type = "build"; }
      { name = "cc1";               nice = 12; ioclass = "best-effort"; ionice = 6; type = "build"; }
      { name = "cc1plus";           nice = 12; ioclass = "best-effort"; ionice = 6; type = "build"; }
      { name = "clang";             nice = 12; ioclass = "best-effort"; ionice = 6; type = "build"; }
      { name = "gcc";               nice = 12; ioclass = "best-effort"; ionice = 6; type = "build"; }
      { name = "ld";                nice = 12; ioclass = "best-effort"; ionice = 6; type = "build"; }
      { name = "ld.lld";            nice = 12; ioclass = "best-effort"; ionice = 6; type = "build"; }
      { name = "collect2";          nice = 12; ioclass = "best-effort"; ionice = 6; type = "build"; }
      { name = "ninja";             nice = 12; ioclass = "best-effort"; ionice = 6; type = "build"; }
      { name = "make";              nice = 12; ioclass = "best-effort"; ionice = 6; type = "build"; }
      { name = "cmake";             nice = 10; ioclass = "best-effort"; ionice = 6; type = "build"; }
      { name = "meson";             nice = 10; ioclass = "best-effort"; ionice = 6; type = "build"; }
      { name = "zstd";              nice = 12; ioclass = "best-effort"; ionice = 7; type = "build"; }
      { name = "xz";                nice = 12; ioclass = "best-effort"; ionice = 7; type = "build"; }
      { name = "gzip";              nice = 12; ioclass = "best-effort"; ionice = 7; type = "build"; }
      { name = "bzip2";             nice = 12; ioclass = "best-effort"; ionice = 7; type = "build"; }

      # Container infrastructure — deprioritize CPU a bit, but do NOT "ioclass=idle" it.
      # (Idle IO here can make *interactive* container-backed workflows feel randomly terrible.)
      { name = "dockerd";            nice = 8;  ioclass = "best-effort"; ionice = 6; type = "build"; }
      { name = "containerd";         nice = 8;  ioclass = "best-effort"; ionice = 6; type = "build"; }
      { name = "buildkitd";          nice = 8;  ioclass = "best-effort"; ionice = 6; type = "build"; }
      { name = "podman";             nice = 8;  ioclass = "best-effort"; ionice = 6; type = "build"; }

      # Keep kubectl interactive (remove the penalty)
      { name = "kubectl";            nice = 0;  ioclass = "best-effort"; ionice = 4; type = "tool"; }
      { name = "kind";               nice = 0;  ioclass = "best-effort"; ionice = 5; type = "tool"; }

      #─────────────────────────────
      # Background services
      #─────────────────────────────

      # nix indexers / search daemons
      { name = "nix-index";         nice = 15; ioclass = "idle"; type = "indexer"; }
      { name = "nix-index-daemon";  nice = 15; ioclass = "idle"; type = "indexer"; }
      { name = "nix-locate";        nice = 10; ioclass = "idle"; type = "indexer"; }

      # LSP can affect editor responsiveness; keep IO normal, just de-prio CPU a bit.
      { name = "nixd";              nice = 8;  ioclass = "best-effort"; ionice = 6; type = "indexer"; }

      { name = "updatedb";          nice = 15; ioclass = "idle"; type = "maintenance"; }
      { name = "fwupd";             nice = 10; ioclass = "idle"; type = "maintenance"; }
      { name = "fwupd-efi";         nice = 10; ioclass = "idle"; type = "maintenance"; }
      { name = "cupsd";             nice = 5;  ioclass = "best-effort"; ionice = 6; type = "service"; }

      # Don't IO-starve VPN/Network management.
      { name = "mullvad-daemon";    nice = 5;  ioclass = "best-effort"; ionice = 5; type = "network"; }
      { name = "networkmanager";    nice = 0;  ioclass = "best-effort"; ionice = 4; type = "network"; }

      #─────────────────────────────
      # Audio and video keep stable
      #─────────────────────────────
      { name = "pipewire";          nice = 0;  ioclass = "best-effort"; ionice = 4; type = "audio"; }
      { name = "pipewire-pulse";    nice = 0;  ioclass = "best-effort"; ionice = 4; type = "audio"; }
      { name = "wireplumber";       nice = 0;  ioclass = "best-effort"; ionice = 4; type = "audio"; }
      { name = "cosmic-player";     nice = 0;  ioclass = "best-effort"; ionice = 5; type = "audio"; }
      { name = "cheese";            nice = 0;  ioclass = "best-effort"; ionice = 5; type = "video"; }
      { name = "simple-scan";       nice = 0;  ioclass = "best-effort"; ionice = 5; type = "video"; }
    ];
  };
}
