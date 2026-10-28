# netavark's nftables driver builds an `inet` table, which a kernel without IPv6 cannot provide,
# so no rootless podman bridge network could be set up (published ports, compose, testcontainers);
# its iptables driver needs xt_nat, which this kernel does not build either. The patch makes the
# nftables driver use an IPv4-only `ip` table when the kernel has no IPv6. It is selected in
# containers.conf (flake.nix: firewall_driver = "nftables").
#
# To be proposed upstream (containers/netavark; ~/Documents/projects/netavark, branch
# ipv6less-nftables). Drop this overlay once a netavark release includes the change.
final: prev: {
  netavark = prev.netavark.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./netavark-nftables-without-ipv6.patch ];
  });
}
