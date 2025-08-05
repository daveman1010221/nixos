{ lib, ... }:
{
  boot = {
    initrd = {
      includeDefaultModules = false;  # <-- This, along with
                                        # 'luks.cryptoModules' below,
                                        # causes unexpected driver
                                        # loading that isn't kosher for
                                        # a FIPS kernel...
  
      # Ensure the initrd includes necessary modules for encryption, RAID, and filesystems
      availableKernelModules = lib.mkForce [
        "encrypted_keys"
        "trusted"

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
        mitigateDMAAttacks = true;
      };

      services.lvm.enable      = true;
      supportedFilesystems     = {
        ext4 = true;
        vfat = true;
        f2fs  = true;
      };
    };
  };
}
