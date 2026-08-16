{ secrets, lib, ... }:
{
  fileSystems = lib.mkIf (secrets.PLACEHOLDER_ROOT != "") {
    "/" =
      {
        device = secrets.PLACEHOLDER_ROOT;
        fsType = "f2fs";
        options = [ "defaults" "atgc" "background_gc=on" "discard" "noatime" "nodiratime" "nobarrier" ];
        neededForBoot = true;
      };

    "/boot" =
      { device = secrets.PLACEHOLDER_BOOT_FS_UUID;
        fsType = "ext4";
        neededForBoot = true;
      };

    "/boot/EFI" =
      { device = secrets.PLACEHOLDER_EFI_FS_UUID;
        fsType = "vfat";
        options = [ "umask=0077" "fmask=0022" "dmask=0022" ];
        neededForBoot = true;
        depends = [ "/boot" ];
      };

    "/var" =
      {
        device = secrets.PLACEHOLDER_VAR;
        fsType = "f2fs";
        options = [ "defaults" "atgc" "background_gc=on" "discard" "noatime" "nodiratime" "nobarrier" ];
        depends = [ "/" ];
      };

    "/tmp" =
      {
        device = secrets.PLACEHOLDER_TMP;
        fsType = "f2fs";
        options = [ "defaults" "atgc" "background_gc=on" "discard" "noatime" "nodiratime" "nobarrier" ];
        depends = [ "/" ];
      };

    "/home" =
      {
        device = secrets.PLACEHOLDER_HOME;
        fsType = "f2fs";
        options = [ "defaults" "atgc" "background_gc=on" "discard" "noatime" "nodiratime" "nobarrier" ];
        depends = [ "/" ];
      };
  };
}
