{ config, ... }:
{
  # Keep the custom kernel's dev output (headers and build tree) in the system closure, so garbage collection
  # doesn't delete it and force a full kernel rebuild the next time something is compiled against the kernel. Only
  # this output is pinned; other build outputs are still collected.
  system.extraDependencies = [ config.boot.kernelPackages.kernel.dev ];
}
