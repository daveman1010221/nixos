{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.ananicy;

  configFile = pkgs.writeText "ananicy.conf"
    (lib.generators.toKeyValue { } cfg.settings);

  extraRules = pkgs.writeText "extraRules"
    (lib.concatMapStringsSep "\n" (l: builtins.toJSON l) cfg.extraRules);

  extraTypes = pkgs.writeText "extraTypes"
    (lib.concatMapStringsSep "\n" (l: builtins.toJSON l) cfg.extraTypes);

  extraCgroups = pkgs.writeText "extraCgroups"
    (lib.concatMapStringsSep "\n" (l: builtins.toJSON l) cfg.extraCgroups);

  servicename =
    if (lib.getName cfg.package) == (lib.getName pkgs.ananicy-cpp)
    then "ananicy-cpp"
    else "ananicy";
in
{
  options.services.ananicy = {
    enable = lib.mkEnableOption "Ananicy, an auto nice daemon";

    package = lib.mkPackageOption pkgs "ananicy" { example = "ananicy-cpp"; };

    rulesProvider = lib.mkPackageOption pkgs "ananicy" { example = "ananicy-cpp"; } // {
      description = "Which package to copy default rules/types/cgroups from.";
    };

    settings = lib.mkOption {
      type = with lib.types; attrsOf (oneOf [ int bool str ]);
      default = { };
      description = "ananicy/ananicy-cpp config settings written to ananicy.conf.";
    };

    extraRules = lib.mkOption {
      type = with lib.types; listOf attrs;
      default = [ ];
      description = "Extra rules written to nixRules.rules (JSON lines).";
    };

    extraTypes = lib.mkOption {
      type = with lib.types; listOf attrs;
      default = [ ];
      description = "Extra types written to nixTypes.types (JSON lines).";
    };

    extraCgroups = lib.mkOption {
      type = with lib.types; listOf attrs;
      default = [ ];
      description = "Extra cgroups written to nixCgroups.cgroups (JSON lines).";
    };

    # 🔥 The missing knob: allow callers to modify the unit cleanly.
    serviceConfig = lib.mkOption {
      type = with lib.types; attrsOf anything;
      default = { };
      description = "Merged into systemd.services.<ananicy>.serviceConfig.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment = {
      systemPackages = [ cfg.package ];

      etc."ananicy.d".source =
        pkgs.runCommand "ananicyfiles" { preferLocalBuild = true; } ''
          mkdir -p $out

          # ananicy-cpp does not include rules or settings on purpose
          if [[ -d "${cfg.rulesProvider}/etc/ananicy.d/00-default" ]]; then
            cp -r ${cfg.rulesProvider}/etc/ananicy.d/* $out
          else
            cp -r ${cfg.rulesProvider}/* $out
          fi

          # configured through .settings
          rm -f $out/ananicy.conf
          cp ${configFile} $out/ananicy.conf

          ${lib.optionalString (cfg.extraRules != [ ]) "cp ${extraRules} $out/nixRules.rules"}
          ${lib.optionalString (cfg.extraTypes != [ ]) "cp ${extraTypes} $out/nixTypes.types"}
          ${lib.optionalString (cfg.extraCgroups != [ ]) "cp ${extraCgroups} $out/nixCgroups.cgroups"}
        '';
    };

    # Defaults (same logic you pasted)
    services.ananicy.settings =
      let mkOD = lib.mkOptionDefault;
      in {
        cgroup_load = mkOD true;
        type_load = mkOD true;
        rule_load = mkOD true;
        apply_nice = mkOD true;
        apply_ioclass = mkOD true;
        apply_ionice = mkOD true;
        apply_sched = mkOD true;
        apply_oom_score_adj = mkOD true;
        apply_cgroup = mkOD true;
      } // (
        if servicename == "ananicy-cpp" then {
          loglevel = mkOD "warn";
          cgroup_realtime_workaround = mkOD true;
          log_applied_rule = mkOD false;

          # ✅ THIS is the “make it actually work” setting.
          #
          # Force ananicy-cpp to operate inside its systemd unit cgroup subtree
          # instead of trying to push tasks into /sys/fs/cgroup/cgroup.procs.
          #
          # If your ananicy-cpp build uses a different key name, keep reading below.
          cgroup_root = mkOD "/sys/fs/cgroup/system.slice/${servicename}.service";
        } else {
          check_disks_schedulers = mkOD true;
          check_freq = mkOD 5;
        }
      );

    systemd.packages = [ cfg.package ];

    systemd.services."${servicename}" = {
      wantedBy = [ "default.target" ];

      # sane defaults for “this daemon must poke cgroups”
      serviceConfig = lib.mkMerge [
        {
          Delegate = "yes";

          # Make sure the unit can actually write where it needs to.
          ProtectControlGroups = false;
          ReadWritePaths = [ "/sys/fs/cgroup" ];

          # Don’t let the packaged unit’s hardening break its purpose.
          ProtectKernelTunables = false;
          ProtectKernelModules = lib.mkDefault true;
          ProtectKernelLogs = lib.mkDefault true;

          # Keep the stock ExecStart unless the caller overrides it.
          # (You can still mkForce it from responsiveness.nix if you want.)
        }

        cfg.serviceConfig
      ];
    };
  };

  meta.maintainers = with lib.maintainers; [ ];
}
