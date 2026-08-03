{ pkgs, ... }:
{
  systemd.services.restic-backup-usb = {
    description = "Manual restic backup to USB drive";
    serviceConfig = {
      Type = "oneshot";
      User = "djshepard";
    };
    path = [ pkgs.restic pkgs.util-linux ];
    script = ''
      set -e
      if ! mountpoint -q /run/media/djshepard/BD7D-8A76; then
        echo "USB drive not mounted, aborting backup"
        exit 1
      fi
      restic -r /run/media/djshepard/BD7D-8A76/precisionws --insecure-no-password backup /home/djshepard \
        --exclude /home/djshepard/.local/share/containers \
        --exclude /home/djshepard/.cache \
        --exclude /run/media/djshepard
      restic -r /run/media/djshepard/BD7D-8A76/precisionws --insecure-no-password forget \
        --keep-weekly 4 --keep-monthly 6 --prune
    '';
  };

  # Fires when the mount unit itself activates — mount events are visible to
  # systemd directly, unlike inotify watching for a path to appear.
  systemd.services."restic-backup-usb".bindsTo = [ "run-media-djshepard-BD7D\\x2d8A76.mount" ];
  systemd.services."restic-backup-usb".after = [ "run-media-djshepard-BD7D\\x2d8A76.mount" ];
  systemd.services."restic-backup-usb".wantedBy = [ "run-media-djshepard-BD7D\\x2d8A76.mount" ];

  systemd.timers.restic-backup-usb = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };
}
