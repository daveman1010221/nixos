# hosts/whitey/initrd-devices.nix  (or separate file)

{ lib, ... }:

{
  boot.initrd.luks.devices.secrets_crypt = {
    device        = "/dev/disk/by-partuuid/…";   # your SECRETS_PARTITION
    allowDiscards = true;
    bypassWorkqueues = true;
    keyFile       = "";      # ask for passphrase on boot
    preLVM        = true;    # open before LVM scan
    # we’ll close it ourselves in a post-hook
  };
}
