{ pkgsForHost, ... }:
{
  boot = {
    # Configure the kernel
  
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
      #"fips=1"
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
