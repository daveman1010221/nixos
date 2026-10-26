{ pkgs, lib, config, ... }:
# let
  # _ = assert pkgs ? hardened_linux_kernel;
      # true;
# in
{
  boot = {
    # blacklistedKernelModules = [
    #   "encrypted_keys"
    #   "trusted"
    # ];

    # Custom clang-built kernel: the shared flakes/kernel/custom-kernel.nix,
    # config in overlays/.config (from whitey's defconfig and
    # overlays/kernel.fragment), tracked version in ../../kernel-version.nix.
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

      availableKernelModules = lib.mkForce [
        # 7.1 bullshit changes:
        "aes"
        "aesni-intel"
        "dm-crypt"
        "dm-mod"

        "nls_cp437"
        "nls_iso8859_1"
        "cbc"

        # Keyboard stack (early boot / initrd)
        "i8042"
        "atkbd"
        "serio_raw"

        # Crypto (initrd): AES isn't "Intel-only" despite the name; AMD uses AES-NI too.
        "gf128mul"
        "essiv"          # ESSIV IV generator for block encryption modes
        "authenc"        # Authenticated encryption transforms used by dm-crypt
        "xts"            # XTS mode (common for disk encryption)

        # Filesystems
        "ext4"           # Encrypted boot volume
        "crc16"
        "mbcache"
        "jbd2"
        "f2fs"           # Flash-friendly filesystem -- root FS
        "lz4_compress"
        "lz4hc_compress"
        "vfat"           # EFI system partition
        "fat"

        # Storage
        "nvme"           # NVME drive support
        "nvme_core"
        "raid0"          # Software RAID0 via mdadm
        "usb_storage"    # Generic USB storage support
        "scsi_mod"
        "scsi_common"
        "libata"
        "md_mod"

        # Hardware support
        "ahci"           # SATA disk support
        "libahci"
        "sd_mod"         # SCSI disk support (/dev/sdX)
        "uas"            # USB attached SCSI (booting from USB)
        "usbcore"        # USB support
        "usbhid"
        "i2c_hid"
        "i2c_hid_acpi"
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
          "aesni-intel"
          "cbc"
          "essiv"
          "gf128mul"
          "xts"
        ];
        mitigateDMAAttacks = true;
      };

      supportedFilesystems = {
        ext4 = true;
        vfat = true;
        f2fs = true;
      };

      systemd.enable = true;
      systemd.emergencyAccess = true;
    };

    kernelModules = [
      "kvm-intel"
      # NVIDIA open modules — loaded after boot, not in initrd
      "nvidia"
      "nvidia_uvm"
      "pkcs8_key_parser" # Lets the kernel keyring take PKCS#8 private keys (keyctl padd asymmetric); never loaded on demand
    ];

    extraModulePackages = [ ];

    kernelParams = [
      "debugfs=off"
      "dm_crypt.max_read_size=1048576"
      "dm_crypt.max_write_size=65536"
      "fips=1"
      "i8042.unlock"
      "i915.force_probe=!a788"
      "intel_idle.max_cstate=4"
      "intel_iommu=on"
      "iommu.strict=1"
      "lockdown=confidentiality"
      "log_buf_len=8M"
      # loglevel, lsm, pcie_aspm and usbcore.autosuspend come from the shared block in flake.nix.
      "mitigations=auto,nosmt"            # the form kernel-hardening-checker reads
      "nosmt"                             # SMT off whatever the CPU; auto,nosmt only where it is vulnerable
      "module.sig_enforce=1"
      "nvme_core.default_ps_max_latency_us=0"
      "pci=realloc"
      "printk.time=1"
      "rootfstype=f2fs"
      "seccomp=1"
      "vsyscall=none"
      "xe.disable_power_well=0"
      "xe.enable_dc=0"
      "xe.enable_fbc=0"
      "xe.enable_ips=0"
      "xe.enable_panel_replay=0"
      "xe.enable_psr2_sel_fetch=0"
      "xe.enable_psr=0"
      "xe.enable_sagv=0"
      "xe.force_probe=a788"
      "zswap.compressor=zstd"             # the config builds CRYPTO_ZSTD for it
      "zswap.enabled=1"
      "zswap.max_pool_percent=10"

      # Hardening (kernel-hardening-checker), as on whitey
      "page_alloc.shuffle=1"
      "hash_pointers=always"
      "iommu=force"
      "tsx=off"
    ];

    kernelPatches = [];

    kernel.sysctl = {
      # Enable certain network operations inside rootless containers.
      "net.ipv4.ip_unprivileged_port_start" = 0;
      "net.ipv4.ping_group_range" = "0 2147483647";

      # Hardening (kernel-hardening-checker), as on whitey
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
      "kernel.io_uring_disabled" = 2;        # off entirely (whitey: 1, root and the io_uring group)
      "kernel.unprivileged_bpf_disabled" = 1; # off for good, not only until root turns it back on
      "kernel.sysrq" = 0;                    # no magic SysRq (NixOS default 16, sync only)

      # The kernel is built without IPv6, so these keys don't exist.
      "net.ipv6.conf.all.disable_ipv6" = lib.mkForce null;
      "net.ipv6.conf.default.disable_ipv6" = lib.mkForce null;
      "net.ipv6.conf.default.use_tempaddr" = lib.mkForce null;
    };
  };

  networking.enableIPv6 = false;

  hardware = {
    cpu.intel.updateMicrocode = true;
    cpu.x86.msr.enable = true;
    enableAllFirmware = true;
    enableAllHardware = true;
    keyboard.qmk.enable = true;

    bluetooth = {
      enable = true;
      powerOnBoot = true;
    };

    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        libva
        libvdpau
        libglvnd
        mesa
      ];
    };

    nvidia = {
      # Use the open kernel modules — correct for RTX 4000 Ada (AD104).
      open = true;

      # Keep drivers in sync with the kernel package set.
      package = config.boot.kernelPackages.nvidiaPackages.stable;

      # iGPU drives the display; dGPU is only woken for offloaded workloads.
      prime = {
        offload = {
          enable = true;
          enableOffloadCmd = true;  # gives you `nvidia-offload <cmd>`
        };

        # lspci shows:
        #   00:02.0  Intel Raptor Lake-S UHD Graphics  → Bus 0, Device 2, Function 0
        #   01:00.0  NVIDIA AD104GLM RTX 4000 Ada      → Bus 1, Device 0, Function 0
        intelBusId  = "PCI:0:2:0";
        nvidiaBusId = "PCI:1:0:0";
      };

      powerManagement = {
        enable = false;
        finegrained = false;
      };

      modesetting.enable = true;
      nvidiaSettings = false;  # GUI settings app — not useful in this setup
    };
  };
}
