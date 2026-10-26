{ pkgs, lib, ... }:
# let
  # _ = assert pkgs ? hardened_linux_kernel;
      # true;
# in
{
  boot = {
    blacklistedKernelModules = [
      "tpm"
      "tpm_crb"
      "tpm_tis"
      "tpm_tis_core"
    ];

    # Custom clang-built kernel: the shared flakes/kernel/custom-kernel.nix,
    # config in overlays/.config, tracked version in ../../kernel-version.nix.
    # Stock fallback: pkgs.linuxPackages_latest
    kernelPackages = pkgs.hardened_linux_kernel;

    binfmt = {
      emulatedSystems = [ "aarch64-linux" ];
      preferStaticEmulators = true;
      addEmulatedSystemsToNixSandbox = true;
    };

    initrd = {
      includeDefaultModules = false;  # Required for FIPS compliance — prevents
                                      # unexpected driver loading in initrd.

      # Every name here must exist in the custom kernel, as a module or
      # built in; the initrd build fails otherwise.
      availableKernelModules = lib.mkForce [
        # 7.1 module-name updates: newer kernel generations report these
        # with hyphens rather than underscores, and stock 7.1.1 initrds
        # were found to omit a plain "aes" skcipher that essiv needs.
        "aes"
        "aesni-intel"
        "dm-crypt"
        "dm-mod"

        "nls_cp437"
        "nls_iso8859_1"
        "sha256"
        "cbc"

        # Keyboard stack (early boot / initrd)
        "i8042"
        "atkbd"

        # Crypto (initrd): AES isn't "Intel-only" despite the name; AMD uses AES-NI too.
        "gf128mul"
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
        "raid0"          # Software RAID0 via mdadm
        "usb_storage"    # Generic USB storage support
        "scsi_mod"
        "scsi_common"
        "libata"
        "dm_snapshot"
        "dm_bufio"
        "md_mod"

        # Hardware support
        "ahci"           # SATA disk support
        "libahci"
        "sd_mod"         # SCSI disk support (/dev/sdX)
        "uas"            # USB attached SCSI (booting from USB)
        "usbcore"        # USB support
        "usbhid"
        "hid_generic"
        "xhci_hcd"       # USB 3.x support
        "xhci_pci"       # USB 3.x support
        "thunderbolt"    # ASM4242 USB4 router; the USB boot drive sits behind it
      ];

      luks = {
        cryptoModules = [
          "aesni-intel"    # AES-NI acceleration (AMD-compatible despite name)
          "cbc"
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
      "pkcs8_key_parser" # Lets the kernel keyring take PKCS#8 private keys (keyctl padd asymmetric); never loaded on demand
    ];

    extraModulePackages = [ ];

    kernelParams = [
      "i8042.unlock"
      "lockdown=confidentiality"
      "mitigations=auto"
      "pci=realloc"
      "seccomp=1"
      "zswap.compressor=lzo"
      "zswap.enabled=1"
      "zswap.max_pool_percent=10"
      "rootfstype=f2fs"
      "nvme_core.default_ps_max_latency_us=0"
      "fips=1"
      "cgroup_no_v1=net_cls"
      "video=efifb:off"

      # Hardening (kernel-hardening-checker)
      "page_alloc.shuffle=1"
      "hash_pointers=always"
      "iommu=force"
    ];

    kernelPatches = [ ];

    kernel.sysctl = {
      # Enable certain network operations inside rootless containers.
      "net.ipv4.ip_unprivileged_port_start" = 0;
      "net.ipv4.ping_group_range" = "0 2147483647";

      # Hardening (kernel-hardening-checker)
      "kernel.kptr_restrict" = 2;            # hides kernel addresses from root too; perf/bpftrace
                                             # symbolization needs 1 (sysctl -w) while tracing
      "dev.tty.ldisc_autoload" = 0;
      "fs.protected_fifos" = 2;
      "fs.protected_regular" = 2;
      "fs.suid_dumpable" = 0;
      "net.ipv4.conf.all.accept_redirects" = 0;
      "net.ipv4.conf.default.accept_redirects" = 0;
      "net.core.bpf_jit_harden" = 2;
      "kernel.oops_limit" = 100;
      "kernel.warn_limit" = 100;
      "kernel.io_uring_disabled" = 1;        # root and kernel.io_uring_group members only

      # The kernel is built without IPv6, so these keys don't exist.
      "net.ipv6.conf.all.disable_ipv6" = lib.mkForce null;
      "net.ipv6.conf.default.disable_ipv6" = lib.mkForce null;
      "net.ipv6.conf.default.use_tempaddr" = lib.mkForce null;
    };
  };

  networking.enableIPv6 = false;

  hardware.cpu.amd.updateMicrocode = true;
  hardware.enableAllFirmware = true;
  hardware.enableAllHardware = true;
  hardware.graphics.enable = true;
  hardware.keyboard.qmk.enable = true;
}
