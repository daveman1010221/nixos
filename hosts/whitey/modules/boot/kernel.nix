{ pkgs, lib, ... }:
let
  _ = assert pkgs ? hardened_linux_kernel;
      true;
in
{
  boot = {
    blacklistedKernelModules = [
      "tpm"
      "tpm_crb"
      "tpm_tis"
      "tpm_tis_core"
    ];

    kernelPackages = pkgs.hardened_linux_kernel;

    initrd.availableKernelModules = lib.mkForce [
      "nls_cp437"
      "nls_iso8859_1"
      "crypto_null"
      "cryptd"
      "cbc"

      # Keyboard stack (early boot / initrd)
      "i8042"
      "atkbd"
      "serio_raw"

      # Crypto (initrd): AES isn’t “Intel-only” despite the name; AMD uses AES-NI too.
      "aesni_intel"    # AES-NI acceleration module (name is historical; works on AMD too)
      "gf128mul"
      "dm_crypt"       # Device-mapper crypto (LUKS)
      "essiv"          # ESSIV IV generator for block encryption modes
      "authenc"        # Authenticated encryption transforms used by dm-crypt
      "xts"            # XTS mode (common for disk encryption)

      # Filesystems
      "ext4"           # Encrypted USB boot volume (GRUB still hates F2FS)
      "crc16"
      "mbcache"
      "jbd2"
      "f2fs"           # Root FS
      "lz4_compress"
      "lz4hc_compress"
      "vfat"           # EFI system partition
      "fat"

      # Storage
      "nvme"
      "nvme_core"
      "nvme_auth"
      "raid0"          # md raid0
      "usb_storage"
      "scsi_mod"
      "scsi_common"
      "libata"
      "dm_mod"
      "dm_snapshot"
      "dm_bufio"
      "dax"
      "md_mod"

      # Hardware support
      "ahci"
      "libahci"
      "sd_mod"
      "uas"
      "usbcore"
      "usbhid"
      "hid_sensor_hub"
      "hid_generic"
      "xhci_hcd"
      "xhci_pci"
      "thunderbolt"
    ];

    # Crypto primitives needed in initrd for unlocking volumes (LUKS + dm-crypt)
    initrd.luks.cryptoModules = [
      "aesni_intel"     # AES-NI acceleration (AMD-compatible despite name)
      "cbc"
      "cryptd"
      "crypto_null"
      "essiv"
      "gf128mul"
      "xts"
    ];

    kernelModules = [ "kvm-amd" ];

    kernelParams = [
      "i8042.unlock"
      #"lockdown=confidentiality"
      "mitigations=auto"
      "pci=realloc"
      "seccomp=1"
      "unprivileged_userns_clone=1"
      "zswap.compressor=lzo"
      "zswap.enabled=1"
      "zswap.max_pool_percent=10"
      "rootfstype=f2fs"
      "nvme_core.default_ps_max_latency_us=0"
      "fips=1"
      "cgroup_no_v1=net_cls"
    ];

    kernelPatches = [ ];

    kernel = {
      # Enable certain network operations inside rootless containers.
      sysctl = {
        "net.ipv4.ip_unprivileged_port_start" = 0;
        "net.ipv4.ping_group_range" = "0 2147483647";
        "kernel.unprivileged_userns_clone" = 1;
      };
    };
  };

  hardware.cpu.amd.updateMicrocode = true;
  hardware.enableAllFirmware = true;
  hardware.enableAllHardware = true;
  hardware.graphics.enable = true;
  hardware.keyboard.qmk.enable = true;
}
