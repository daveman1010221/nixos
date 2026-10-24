# The nixpkgs kernel the custom kernel tracks: source, version and upstream
# kernelPatches come from this attribute. Shared by overlays/custom-kernel.nix
# and kernel-sandbox/shell.nix so the two cannot drift apart.
{
  attr = "linux_7_3";
}
