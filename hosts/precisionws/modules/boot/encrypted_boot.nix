# literal values live here – NOT secrets
{ config, ... }:

{
  my.boot.device    = "/dev/disk/by-uuid/fd2eb4f6-6320-4e8c-b95d-59b38a37ebb7";
  my.boot.efiDevice = "/dev/disk/by-uuid/C2EC-CF17";

  # (optional cache for scripts – remove if you don’t want the file)
  environment.etc."cache/boot.json".text = builtins.toJSON {
    boot_device = config.my.boot.device;
    efi_device  = config.my.boot.efiDevice;
  };
}
