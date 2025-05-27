{ ... }:
{
  imports = [
    ./boot/kernel.nix
    ./boot/initrd.nix
    ./boot/loader.nix
    ./boot/block.nix
    ./boot/filesystems.nix
    ./hardware.nix
    ./services/xserver.nix
    ./systemd-services/lockBoot.nix
    ./systemd-services/lvm-readahead.nix
  ];
}
