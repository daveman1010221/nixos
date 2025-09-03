{ hostPkgs, ... }:

{
  systemd.services."systemd-cryptsetup@secrets_crypt".enable = false;
}

