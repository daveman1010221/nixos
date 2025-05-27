{ hostPkgs, ... }:

{
  systemd.services."set-lvm-readahead" = {
    description = "Set read-ahead for LVM LV to optimize performance";
    wants = [ "local-fs.target" ];
    path = [ hostPkgs.lvm2 ];
    script = ''
    lvchange --readahead 2048 /dev/nix/tmp
    lvchange --readahead 2048 /dev/nix/var
    lvchange --readahead 2048 /dev/nix/root
    lvchange --readahead 2048 /dev/nix/home
    '';
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
  };
}
