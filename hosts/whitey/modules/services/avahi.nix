{ ... }:

{
  # avahi matches interface names exactly, and whitey's Wi-Fi is whichever
  # adapter is plugged in (onboard wlp16s0, or the USB RTL8814AU under a
  # port-dependent name). So deny the container bridges instead of allowing
  # a fixed list. Point-to-point links (wg0-mullvad, tun0) are already
  # excluded, and nftables.nft passes mDNS only on wl* interfaces.
  services.avahi.settings.server.deny-interfaces = [ "docker0" "br0" "virbr0" ];
}
