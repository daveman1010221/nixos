#{ pkgsForHost, lib, ... }:
{ pkgs, lib, ... }:
let
  _ = assert pkgs ? hardened_linux_kernel;
      true;
in
{
  boot = {
    kernelPackages = pkgs.hardened_linux_kernel;

  initrd.availableKernelModules = lib.mkForce [
    "nls_cp437"
    "nls_iso8859_1"
    "cryptd"
    #"sha256"
    #"sha256_generic"
    "vmd"
    "cbc"

    # keyboard stack for internal laptop keyboard
    "i8042"
    "atkbd"
    "serio_raw"

    # crypto
    "aesni_intel"     # The gold standard for FIPS 140-2/3 compliance
                      # Hardware-accelerate AES within the Intel CPU
    "gf128mul"
    #"crypto_simd"
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
    #"kvm-amd"
    "libahci"
    "sd_mod"          # SCSI disk support (/dev/sdX)
    "uas"             # USB attached SCSI (booting from USB)
    "usbcore"         # USB support
    "usbhid"
    "i2c_hid"
    "i2c_hid_acpi"    # often needed on Dell
    "hid_multitouch"
    "hid_sensor_hub"
    "intel_ishtp_hid"
    "hid_generic"
    "xhci_hcd"        # USB 3.x support
    "xhci_pci"        # USB 3.x support
    "thunderbolt"
  ];

  # Define LUKS devices, including the encrypted /boot and NVMe devices
  initrd.luks.cryptoModules = [
    "aesni_intel"
    "cbc"
    "cryptd"
    "crypto_null"
    #"crypto_simd"
    "essiv"
    "gf128mul"
    #"sha256"
    #"sha256_generic"
    "xts"
  ];

    kernelModules = [ "kvm-intel" ];
  
    kernelParams = [
      "debugfs=off"
      "dm_crypt.max_read_size=1048576"
      "dm_crypt.max_write_size=65536"
      "fips=0"
      "i8042.unlock"
      "i915.force_probe=!a788"
      "intel_idle.max_cstate=4"
      "intel_iommu=on"
      "iommu.strict=1"
      "lockdown=confidentiality"
      "log_buf_len=8M"
      "loglevel=6"
      "lsm=landlock,yama,bpf"
      "mitigations=auto"
      "module_blacklist=nouveau,nvidia,nvidia_drm,nvidia_modeset"
      "module.sig_enforce=1"
      "nosmt"
      "nvme_core.default_ps_max_latency_us=0"
      "pci=realloc"
      "pcie_aspm=on"
      "printk.time=1"
      "rootfstype=f2fs"
      "seccomp=1"
      #"udev.log_level=debug"
      "unprivileged_userns_clone=1"
      "usbcore.autosuspend=-1"
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
      "zswap.compressor=zstd"
      "zswap.enabled=1"
      "zswap.max_pool_percent=10"
    ];
  
    kernelPatches = [
    ];
  
    kernel = {
      # unprivileged_userns_clone is for applications to be able to implement
      # sandboxing, since unprivileged user namespaces are disabled by default
      # when using a hardened kernel.
  
      # The net.ipv4 options are there to enable certain network operations
      # inside of rootless containers.
      sysctl = {
        "net.ipv4.ip_unprivileged_port_start" = 0;
        "net.ipv4.ping_group_range" = "0 2147483647";
        "kernel.unprivileged_userns_clone" = 1;
      };
    };
  };

  hardware.cpu.intel.updateMicrocode = true;
  hardware.enableAllFirmware = true;
  hardware.enableAllHardware = true;
  hardware.graphics.enable = true;
  hardware.keyboard.qmk.enable = true;
}
