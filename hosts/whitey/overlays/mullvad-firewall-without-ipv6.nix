# Mullvad's firewall builds an `inet` nftables table, which a kernel without IPv6 cannot
# provide, so the daemon could never apply its policy on whitey's kernel and never connected.
# The patch makes it fall back to an IPv4-only `ip` table when the kernel has no IPv6.
#
# To be proposed upstream (mullvad/mullvadvpn-app, branch linux-firewall-without-ipv6). Drop this
# overlay once a Mullvad release includes the change.
final: prev: {
  mullvad = prev.mullvad.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./mullvad-firewall-without-ipv6.patch ];
  });
}
