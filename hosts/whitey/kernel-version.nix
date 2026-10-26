# The nixpkgs kernel the custom kernel tracks: source, version and upstream
# kernelPatches come from this attribute. Read by the shared overlay
# (flakes/kernel/custom-kernel.nix) and sandbox (flakes/kernel/sandbox), so the
# two cannot drift apart; its presence is what gives this host its own kernel.
{
  attr = "linux_7_3";
}
