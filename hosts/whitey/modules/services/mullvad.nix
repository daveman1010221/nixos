{ hostPkgs, ... }:

{
  services.mullvad-vpn.enable = true;
  services.mullvad-vpn.package = hostPkgs.mullvad-vpn;
}
