{ pkgsForHost, ... }:
{
  boot = {
    # Configure the kernel
  
    # This bug-checks when GDM tries to initialize the external Nvidia display,
    # so clearly some sort of issue with the Nvidia driver and the hardened
    # kernel. It works fine for 'on the go' config, though. Considering making two kernel configs.
    # kernelPackages = pkgsForHost.hardened_linux_kernel;
  
    # kernelModules = [ "kvm-intel" ];
  
    kernelParams = [
      "i8042.unlock"
      # "intel_idle.max_cstate=4"
      # "intel_iommu=on"
      #"lockdown=confidentiality"
      "mitigations=auto"
      "pci=realloc"
      "seccomp=1"
      "unprivileged_userns_clone=1"
      "zswap.compressor=lzo"
      "zswap.enabled=1"
      "zswap.max_pool_percent=10"
      # "modprobe.blacklist=nouveau"
      "rootfstype=f2fs"
      "nvme_core.default_ps_max_latency_us=0"
      "fips=1"
      # "dm_crypt.max_read_size=1048576"
      # "dm_crypt.max_write_size=65536"
      # "NVreg_EnableGpuFirmware=1"
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
}
