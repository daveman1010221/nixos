#{ pkgsForHost, lib, ... }:
{ pkgs, lib, ... }:
let
  _ = assert pkgs ? hardened_linux_kernel;
      true;
in
{
  boot = {
    # Configure the kernel
  
    # This bug-checks when GDM tries to initialize the external Nvidia display,
    # so clearly some sort of issue with the Nvidia driver and the hardened
    # kernel. It works fine for 'on the go' config, though. Considering making two kernel configs.
    #kernelPackages = pkgsForHost.linuxPackages_latest;
    #kernelPackages = pkgsForHost.linuxKernel.packages.linux_6_17;

    # Currently built on top of 6.17 generic, I think.
    #kernelPackages = pkgsForHost.hardened_linux_kernel;
    kernelPackages = pkgs.hardened_linux_kernel;

  initrd.availableKernelModules = lib.mkForce [
    "nls_cp437"
    "nls_iso8859_1"
    "crypto_null"
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
      "i8042.unlock"
      "intel_idle.max_cstate=4"
      "intel_iommu=on"
      #"lockdown=confidentiality"
      "mitigations=auto"
      "pci=realloc"
      "seccomp=1"
      "unprivileged_userns_clone=1"
      "zswap.compressor=lzo"
      "zswap.enabled=1"
      "zswap.max_pool_percent=10"
      "modprobe.blacklist=nouveau"
      "rootfstype=f2fs"
      "nvme_core.default_ps_max_latency_us=0"
      "fips=1"
      "dm_crypt.max_read_size=1048576"
      "dm_crypt.max_write_size=65536"
      "NVreg_EnableGpuFirmware=1"
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

  hardware.cpu.amd.updateMicrocode = true;
  hardware.enableAllFirmware = true;
  hardware.enableAllHardware = true;
  hardware.graphics.enable = true;
  hardware.keyboard.qmk.enable = true;
}
