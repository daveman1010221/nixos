{ hostPkgs, ... }:

{
  systemd.services."systemd-cryptsetup@secrets_crypt.service".enable = false;
}

