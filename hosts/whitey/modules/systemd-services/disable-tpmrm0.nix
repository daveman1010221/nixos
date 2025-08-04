{ hostPkgs, ... }:

{
  systemd.services."dev-tpmrm0.device".enable = false;
}

