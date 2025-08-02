{ config, lib, secrets, ... }:

{
  boot.initrd.luks.devices.secrets_crypt = {
    allowDiscards = true;
    bypassWorkqueues = true;
    keyFile       = "";      # ask for passphrase on boot
    preLVM        = true;    # open before LVM scan
    # we’ll close it ourselves in a post-hook
  };
}
