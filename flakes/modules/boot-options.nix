{ lib, ... }:

with lib;

{
  options.my.boot.device = mkOption {
    type        = types.str;
    description = "Block device (or by-id/by-uuid symlink) for the encrypted /boot file-system.";
  };

  options.my.boot.efiDevice = mkOption {
    type        = types.str;
    description = "Block device (or by-id/by-uuid symlink) for the EFI System Partition.";
  };
}
