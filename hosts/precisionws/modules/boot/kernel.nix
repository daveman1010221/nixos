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
      "vmd"
      "cbc"
      "i8042"
      "atkbd"
      "serio_raw"
      "aesni_intel"
      "gf128mul"
      "dm_crypt"
      "essiv"
      "authenc"
      "xts"
      "ext4"
      "crc16"
      "mbcache"
      "jbd2"
      "f2fs"
      "lz4_compress"
      "lz4hc_compress"
      "vfat"
      "fat"
      "nvme"
      "nvme_core"
      "nvme_auth"
      "raid0"
      "usb_storage"
      "scsi_mod"
      "scsi_common"
      "libata"
      "dm_mod"
      "dm_snapshot"
      "dm_bufio"
      "dax"
      "md_mod"
      "ahci"
      "libahci"
      "sd_mod"
      "uas"
      "usbcore"
      "usbhid"
      "i2c_hid"
      "i2c_hid_acpi"
      "hid_multitouch"
      "hid_sensor_hub"
      "intel_ishtp_hid"
      "hid_generic"
      "xhci_hcd"
      "xhci_pci"
      "thunderbolt"
    ];

    initrd.luks.cryptoModules = [
      "aesni_intel"
      "cbc"
      "cryptd"
      "crypto_null"
      "essiv"
      "gf128mul"
      "xts"
    ];

    kernelModules = [
      "kvm-intel"
      # NVIDIA open modules — loaded after boot, not in initrd
      "nvidia"
      "nvidia_uvm"
    ];

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
      "loglevel=6"
      "lsm=landlock,yama,bpf"
      "mitigations=auto"
      "module.sig_enforce=1"
      "nosmt"
      "nvme_core.default_ps_max_latency_us=0"
      "pci=realloc"
      "pcie_aspm=on"
      "printk.time=1"
      "rootfstype=f2fs"
      "seccomp=1"
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

    kernelPatches = [];

    kernel.sysctl = {
      "net.ipv4.ip_unprivileged_port_start" = 0;
      "net.ipv4.ping_group_range" = "0 2147483647";
      "kernel.unprivileged_userns_clone" = 1;
    };
  };

  hardware.cpu.intel.updateMicrocode = true;
  hardware.enableAllFirmware = true;
  hardware.enableAllHardware = true;
  hardware.graphics.enable = true;
  hardware.keyboard.qmk.enable = true;
}
