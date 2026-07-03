{ ... }:

{
#  services.restic.backups.usb = {
#    user = "djshepard";
#    paths = [ "/home/djshepard" ];
#    exclude = [
#      "/home/djshepard/.local/share/containers"
#      "/home/djshepard/.cache"
#      "/run/media/djshepard"
#    ];
#    repository = "/run/media/djshepard/BD7D-8A76/precisionws";
#    initialize = true;
#    inhibitsSleep = true;
#    timerConfig = {
#      OnCalendar = "weekly";
#      Persistent = true;
#    };
#    pruneOpts = [
#      "--keep-weekly 4"
#      "--keep-monthly 6"
#    ];
#    backupPrepareCommand = ''
#      if ! mountpoint -q /run/media/djshepard/BD7D-8A76; then
#        echo "USB drive not mounted, aborting backup"
#        exit 1
#      fi
#    '';
#  };
}
