{ lib, hostPkgs, secrets, ... }:

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
      includeDefaultModules = false;  # <-- This, along with
                                      # 'luks.cryptoModules' below,
                                      # causes unexpected driver
                                      # loading that isn't kosher for
                                      # a FIPS kernel...
  
      # Ensure the initrd includes necessary modules for encryption, RAID, and filesystems
      availableKernelModules = lib.mkForce [
        "nls_cp437"
        "nls_iso8859_1"
        "crypto_null"
        "cryptd"
        "sha256"
        "vmd"
  
        # crypto
        "aesni_intel"     # The gold standard for FIPS 140-2/3 compliance
                          # Hardware-accelerate AES within the Intel CPU
        "gf128mul"
        "crypto_simd"
  
        "dm_crypt"        # LUKS encryption support for device mapper storage infrastructure
  
        "essiv"           # Encrypted Salt-Sector Initialization Vector is a transform for various encryption modes, mostly supporting block device encryption
        "authenc"
        "xts"             # XEX-based tweaked-codebook mode with ciphertext stealing -- like essiv, is designed specifically for block device encryption
  
        # filesystems
        "ext4"            # Old time linux filesystem, used on the encrypted USB boot volume. Required because grub doesn't support F2FS yet.
        "crc16"
        "mbcache"
        "jbd2"
        "f2fs"            # Flash-friendly filesystem support -- the top-layer of our storage stack
        "lz4_compress"
        "lz4hc_compress"
        "vfat"            # Windows FAT volumes, such as the FAT12 EFI partition
        "fat"
  
        # storage
        "nvme"            # NVME drive support
        "nvme_core"
        "nvme_auth"
        "raid0"           # Software RAID0 via mdadm
        "usb_storage"     # Generic USB storage support
        "scsi_mod"
        "scsi_common"
        "libata"
        "dm_mod"          # Device mapper infrastructure
        "dm_snapshot"
        "dm_bufio"
        "dax"
        "md_mod"
  
        # hardware support modules
        "ahci"            # SATA disk support
        "libahci"
        "sd_mod"          # SCSI disk support (/dev/sdX)
        "uas"             # USB attached SCSI (booting from USB)
        "usbcore"         # USB support
        "usbhid"
        "i2c_hid"
        "hid_multitouch"
        "hid_sensor_hub"
        "intel_ishtp_hid"
        "hid_generic"
        "xhci_hcd"        # USB 3.x support
        "xhci_pci"        # USB 3.x support
        "thunderbolt"
      ];
  
      # Define LUKS devices, including the encrypted /boot and NVMe devices
      # EDIT
      luks = {
        cryptoModules = [
          "aesni_intel"
          "essiv"
          "xts"
          "sha256"
        ];
  
        devices = {
          boot_crypt = {
            # sdb2 UUID (pre-luksOpen)
            device = secrets.PLACEHOLDER_BOOT_UUID;
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
  
        mitigateDMAAttacks = true;
      };
  
      services.lvm.enable = true;
  
      supportedFilesystems = ["ext4" "vfat" "f2fs" ];
    };
  };
}
