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
    "usbcore.autosuspend=2"
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

    settings = {
      verbose = false;
      check_freq = 10;
      cgroup_load = true;
      type_load = true;
      rule_load = true;
      apply_nice = true;
      apply_ioclass = true;
      apply_ionice = true;
      apply_sched = true;
      apply_oom_score_adj = true;
      apply_cgroup = false;
      check_disks_schedulers = true;
    };

    extraRules = [
      #─────────────────────────────
      # High-priority, interactive
      #─────────────────────────────
      { name = "code";              nice = -8; ioclass = "best-effort"; ionice = 0; type = "editor"; }
      { name = "zed";               nice = -8; ioclass = "best-effort"; ionice = 0; type = "editor"; }
      { name = "nvim";              nice = -8; ioclass = "best-effort"; ionice = 0; type = "editor"; }
      { name = "wezterm";           nice = -8; ioclass = "best-effort"; ionice = 0; type = "terminal"; }
      { name = "kitty";             nice = -8; ioclass = "best-effort"; ionice = 0; type = "terminal"; }
      { name = "librewolf";         nice = -6; ioclass = "best-effort"; ionice = 0; type = "browser"; }
      { name = "microsoft-edge";    nice = -6; ioclass = "best-effort"; ionice = 0; type = "browser"; }
      { name = "signal-desktop";    nice = -6; ioclass = "best-effort"; ionice = 0; type = "comms"; }
      { name = "zoom";              nice = -6; ioclass = "best-effort"; ionice = 0; type = "comms"; }
      { name = "zoom-us";           nice = -6; ioclass = "best-effort"; ionice = 0; type = "comms"; }

      #─────────────────────────────
      # Cosmic processes — keep smooth
      #─────────────────────────────
      { name = "cosmic-comp";       nice = -5; ioclass = "best-effort"; ionice = 0; type = "compositor"; }
      { name = "cosmic-session";    nice = -5; ioclass = "best-effort"; ionice = 0; type = "desktop"; }
      { name = "cosmic-panel";      nice = -5; ioclass = "best-effort"; ionice = 0; type = "desktop"; }
      { name = "cosmic-bg";         nice = 0;  ioclass = "best-effort"; ionice = 0; type = "service"; }
      { name = "cosmic-settings";   nice = 0;  ioclass = "best-effort"; ionice = 0; type = "service"; }
      { name = "xdg-desktop-portal-cosmic"; nice = 0; ioclass = "best-effort"; ionice = 0; type = "service"; }

      #─────────────────────────────
      # Containers, build tools — deprioritize
      #─────────────────────────────
      { name = "docker";            nice = 10; ioclass = "idle"; type = "build"; }
      { name = "podman";            nice = 10; ioclass = "idle"; type = "build"; }
      { name = "containerd";        nice = 10; ioclass = "idle"; type = "build"; }
      { name = "buildkitd";         nice = 10; ioclass = "idle"; type = "build"; }
      { name = "kind";              nice = 10; ioclass = "idle"; type = "build"; }
      { name = "kubectl";           nice = 10; ioclass = "idle"; type = "build"; }

      #─────────────────────────────
      # Background services
      #─────────────────────────────

      # nix indexers / search daemons
      { name = "nix-index";         nice = 15; ioclass = "idle"; type = "indexer"; }
      { name = "nix-index-daemon";  nice = 15; ioclass = "idle"; type = "indexer"; }
      { name = "nix-locate";        nice = 10; ioclass = "idle"; type = "indexer"; }
      { name = "nixd";              nice = 10; ioclass = "idle"; type = "indexer"; }
      { name = "updatedb";          nice = 15; ioclass = "idle"; type = "maintenance"; }
      { name = "fwupd";             nice = 10; ioclass = "idle"; type = "maintenance"; }
      { name = "fwupd-efi";         nice = 10; ioclass = "idle"; type = "maintenance"; }
      { name = "cupsd";             nice = 5;  ioclass = "idle"; type = "service"; }
      { name = "mullvad-daemon";    nice = 5;  ioclass = "idle"; type = "network"; }
      { name = "networkmanager";    nice = 0;  ioclass = "best-effort"; ionice = 0; type = "network"; }

      #─────────────────────────────
      # Audio and video keep stable
      #─────────────────────────────
      { name = "pipewire";          nice = 0; type = "audio"; }
      { name = "pipewire-pulse";    nice = 0; type = "audio"; }
      { name = "wireplumber";       nice = 0; type = "audio"; }
      { name = "cosmic-player";     nice = 0; type = "audio"; }
      { name = "cheese";            nice = 0; type = "video"; }
      { name = "simple-scan";       nice = 0; type = "video"; }
    ];
  };
}
