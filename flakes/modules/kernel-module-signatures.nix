# Every module the system will load is signed by the host's key, checked when the system is built: a kernel built
# with MODULE_SIG_FORCE refuses an unsigned module at boot, and kbuild's signing of an out-of-tree module (NVIDIA's)
# fails without stopping the build. Only for a kernel that signs with the host's key (flakes/kernel/custom-kernel.nix
# sets passthru.signsWithHostKey); nixpkgs' stock kernel signs its own way.
{ config, lib, pkgs, ... }:
let
  kernel = config.boot.kernelPackages.kernel;
  certificate = "${kernel.dev}/lib/modules/${kernel.modDirVersion}/build/certs/signing_key.x509";
in
{
  config = lib.mkIf (kernel.passthru.signsWithHostKey or false) {
    system.checks = [
      (pkgs.runCommand "kernel-module-signatures" { nativeBuildInputs = [ pkgs.openssl pkgs.python3 pkgs.zstd ]; } ''
        python3 ${../kernel/verify-module-signatures.py} ${certificate} ${config.system.modulesTree}/lib/modules
        touch $out
      '')
    ];
  };
}
