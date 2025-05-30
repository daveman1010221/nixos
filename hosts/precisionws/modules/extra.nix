{ ... }:
{
  imports = [
    ./boot/kernel.nix
    ./boot/initrd-devices.nix
    ./boot/loader.nix
    ./boot/block.nix
    ./boot/filesystems.nix
    ./boot/encrypted_boot.nix
    ./hardware.nix
    ./services/xserver.nix
    ./systemd-services/lockBoot.nix
    ./systemd-services/lvm-readahead.nix
  ];
}
