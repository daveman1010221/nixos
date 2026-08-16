{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.resticUsbBackup;

  mountUnitName = path:
    let
      trimmed = lib.removePrefix "/" path;
      parts = lib.splitString "/" trimmed;
      escapePart = p: lib.replaceStrings [ "-" ] [ "\\x2d" ] p;
    in
      (lib.concatStringsSep "-" (map escapePart parts)) + ".mount";
in
{
  options.services.resticUsbBackup = {
    enable = mkEnableOption "restic backup to a USB drive on mount activation";

    mountPoint = mkOption {
      type = types.str;
      description = "Path where the USB drive is mounted (e.g. /run/media/user/LABEL).";
      example = "/run/media/djshepard/Backups-New";
    };

    repoSubdir = mkOption {
      type = types.str;
      default = config.networking.hostName;
      description = "Subdirectory under mountPoint used as the restic repo path.";
    };

    user = mkOption {
      type = types.str;
      description = "User to run the backup as, and whose home directory is backed up.";
    };

    extraExcludes = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Additional --exclude paths, beyond the standard cache/container excludes.";
    };

    insecureNoPassword = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Pass --insecure-no-password to restic. Appropriate when the target
        drive is itself hardware/filesystem-encrypted, making restic's own
        repo encryption redundant. Set to false and supply passwordFile
        instead if the drive is NOT independently encrypted.
      '';
    };

    passwordFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to a restic repo password file. Required if insecureNoPassword is false.";
    };

    keepWeekly = mkOption {
      type = types.int;
      default = 4;
    };

    keepMonthly = mkOption {
      type = types.int;
      default = 6;
    };

    onCalendar = mkOption {
      type = types.str;
      default = "weekly";
    };
  };

  config = mkIf cfg.enable (
    let
      mountUnit = mountUnitName cfg.mountPoint;
      repoPath = "${cfg.mountPoint}/${cfg.repoSubdir}";
      authFlags =
        if cfg.insecureNoPassword
        then [ "--insecure-no-password" ]
        else (
          assert lib.assertMsg (cfg.passwordFile != null)
            "services.resticUsbBackup: passwordFile must be set when insecureNoPassword = false";
          [ "--password-file" cfg.passwordFile ]
        );
      authFlagsStr = lib.concatStringsSep " " authFlags;
      excludeFlagsStr = lib.concatMapStringsSep " " (e: "--exclude ${e}") (
        [
          "/home/${cfg.user}/.local/share/containers"
          "/home/${cfg.user}/.cache"
          cfg.mountPoint
        ] ++ cfg.extraExcludes
      );
    in
    {
      systemd.services.restic-backup-usb = {
        description = "Restic backup to USB drive (${cfg.mountPoint})";
        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
        };
        path = [ pkgs.restic pkgs.util-linux ];
        script = ''
          set -e
          if ! mountpoint -q ${cfg.mountPoint}; then
            echo "USB drive not mounted, aborting backup"
            exit 1
          fi
          restic -r ${repoPath} ${authFlagsStr} backup /home/${cfg.user} \
            ${excludeFlagsStr}
          restic -r ${repoPath} ${authFlagsStr} forget \
            --keep-weekly ${toString cfg.keepWeekly} --keep-monthly ${toString cfg.keepMonthly} --prune
        '';
        bindsTo = [ mountUnit ];
        after = [ mountUnit ];
        wantedBy = [ mountUnit ];
      };

      systemd.timers.restic-backup-usb = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.onCalendar;
          Persistent = true;
        };
      };
    }
  );
}
