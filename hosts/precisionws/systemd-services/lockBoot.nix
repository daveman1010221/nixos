{ hostPkgs, ... }:

{
  systemd.services.lockBoot = {
    description = "Manage the encrypted /boot partition";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    path = with hostPkgs; [
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
      #!${hostPkgs.bash}/bin/bash

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
}
