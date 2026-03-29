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

    kernelPackages = pkgs.linuxKernel.packages.linux_6_18;

    binfmt = {
      emulatedSystems = [ "aarch64-linux" ];
      preferStaticEmulators = true;
      addEmulatedSystemsToNixSandbox = true;
    };

    initrd = {
      includeDefaultModules = false;  # Required for FIPS compliance — prevents
                                      # unexpected driver loading in initrd.

      availableKernelModules = lib.mkForce [
        "nls_cp437"
        "nls_iso8859_1"
        "crypto_null"
        "cryptd"
        "sha256"
        "vmd"
        "cbc"

        # Keyboard stack (early boot / initrd)
        "i8042"
        "atkbd"
        "serio_raw"

        # Crypto (initrd): AES isn't "Intel-only" despite the name; AMD uses AES-NI too.
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
        "f2fs"           # Flash-friendly filesystem support -- the top-layer of our storage stack
        "lz4_compress"
        "lz4hc_compress"
        "vfat"           # Windows FAT volumes, such as the FAT12 EFI partition
        "fat"

        # Storage
        "nvme"           # NVME drive support
        "nvme_core"
        "nvme_auth"
        "raid0"          # Software RAID0 via mdadm
        "usb_storage"    # Generic USB storage support
        "scsi_mod"
        "scsi_common"
        "libata"
        "dm_mod"         # Device mapper infrastructure
        "dm_snapshot"
        "dm_bufio"
        "dax"
        "md_mod"

        # Hardware support
        "ahci"           # SATA disk support
        "libahci"
        "sd_mod"         # SCSI disk support (/dev/sdX)
        "uas"            # USB attached SCSI (booting from USB)
        "usbcore"        # USB support
        "usbhid"
        "i2c_hid"
        "hid_multitouch"
        "hid_sensor_hub"
        "intel_ishtp_hid"
        "hid_generic"
        "xhci_hcd"       # USB 3.x support
        "xhci_pci"       # USB 3.x support
        "thunderbolt"
      ];

      luks = {
        cryptoModules = [
          "aesni_intel"    # AES-NI acceleration (AMD-compatible despite name)
          "cbc"
          "cryptd"
          "crypto_null"
          "essiv"
          "gf128mul"
          "sha256"
          "xts"
        ];
        mitigateDMAAttacks = true;
      };

      services.lvm.enable = true;

      supportedFilesystems = {
        ext4 = true;
        vfat = true;
        f2fs = true;
      };

      systemd.enable = true;
      systemd.emergencyAccess = true;
    };

    kernelModules = [
      "kvm-amd"
      "vxlan"          # Required for usernetes/rootless Kubernetes overlay networking
    ];

    extraModulePackages = [ ];

    kernelParams = [
      "i8042.unlock"
      "lockdown=confidentiality"
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
      "video=efifb:off"
    ];

    kernelPatches = [ ];

    kernel.sysctl = {
      # Enable certain network operations inside rootless containers.
      "net.ipv4.ip_unprivileged_port_start" = 0;
      "net.ipv4.ping_group_range" = "0 2147483647";
      "kernel.unprivileged_userns_clone" = 1;
    };
  };

  hardware.cpu.amd.updateMicrocode = true;
  hardware.enableAllFirmware = true;
  hardware.enableAllHardware = true;
  hardware.graphics.enable = true;
  hardware.keyboard.qmk.enable = true;
}
