# hosts/whitey/modules/services/gitea-tunnel.nix
#
# The way back in from elsewhere. whitey is behind Mullvad, whose exit takes
# nothing inbound, so User reaches it over a reverse tunnel through the gitea
# server: gitea's loopback port 2222 leads to whitey's sshd, and from another
# machine `ssh -o ProxyCommand="ssh -W %h:%p djshepard@<gitea>" -p 2222
# djshepard@localhost`. The same connection carries `LocalForward 3000` from
# ~/.ssh/config's `Host gitea`, the only way to Gitea's web port from here.
#
# A user service, started at boot without a login (User lingers), so it comes
# back after a reboot with nobody at the console. It uses ~/.ssh/config's
# `Host gitea` and its key file, which has no passphrase, so it needs no agent.
# It never gives up: a dropped network, Mullvad still connecting, or gitea
# holding 2222 for a dead session each end in a retry ten seconds later.
{ pkgs, ... }:
{
  systemd.user.services.gitea-reverse-tunnel = {
    description = "Reverse SSH tunnel through gitea back to whitey (2222 to sshd)";
    wantedBy = [ "default.target" ];
    unitConfig = {
      ConditionUser = "djshepard";
      StartLimitIntervalSec = 0;
    };
    serviceConfig = {
      ExecStart = "${pkgs.openssh}/bin/ssh -N -o ExitOnForwardFailure=yes -o BatchMode=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -R 2222:localhost:22 gitea";
      Restart = "always";
      RestartSec = "10s";
    };
  };
}
