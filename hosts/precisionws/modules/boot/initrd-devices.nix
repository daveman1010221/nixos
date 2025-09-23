{ config, lib, hostPkgs, secrets, ... }:

{
  # Boot configuration
  boot = {
  
    # A compile error prevents me from having drivers for my Alfa
    # Networks AWUS 1900 USB Wifi adapter. Supposedly, this driver
    # will in the upstream kernel in 6.15.
    # extraModulePackages = [
    #   pkgs.hardened_linux_kernel.rtl8814au
    # ];
  
    initrd = {
      luks.devices = {
        boot_crypt = {
          # sdb2 UUID (pre-luksOpen)
          device = "/dev/disk/by-uuid/bd7cb388-7b08-4264-bee0-7477fd48fa59";
          preLVM = true;
          allowDiscards = true;
          # Custom mount commands for the unencrypted /boot, included in the initrd
          # EDIT
          postOpenCommands = lib.mkBefore ''
            #!${hostPkgs.stdenv.shell}
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
          device = secrets.PLACEHOLDER_NVME0;
          header = "/sensitive/keys/nvme0n1.header";
          keyFile = "/sensitive/keys/nvme0n1.key";
          allowDiscards = true;
          bypassWorkqueues = true;
          postOpenCommands = ''
            # Securely erase the key and header files
            ${hostPkgs.coreutils}/bin/shred -u /sensitive/keys/nvme0n1.key || true
            ${hostPkgs.coreutils}/bin/shred -u /sensitive/keys/nvme0n1.header || true
          '';
        };
  
        # EDIT
        nvme1n1_crypt = {
          device = secrets.PLACEHOLDER_NVME1;
          header = "/sensitive/keys/nvme1n1.header";
          keyFile = "/sensitive/keys/nvme1n1.key";
          allowDiscards = true;
          bypassWorkqueues = true;
          postOpenCommands = ''
            # Securely erase the key and header files
            ${hostPkgs.coreutils}/bin/shred -u /sensitive/keys/nvme1n1.key || true
            ${hostPkgs.coreutils}/bin/shred -u /sensitive/keys/nvme1n1.header || true
          '';
        };
      };
    };
  };
}
