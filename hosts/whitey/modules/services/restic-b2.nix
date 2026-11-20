# hosts/whitey/modules/services/restic-b2.nix
#
# Off-site backup of the home directory to Backblaze B2 (bucket whitey,
# us-west-002), through B2's S3-compatible API, every day. The USB backup
# (restic.nix) runs only while its drive is mounted; this one needs nothing
# plugged in.
#
# The repository was made by hand (`restic init`). Its secrets are kept in
# this repository encrypted with age (ragenix; ../../secrets/rules.nix says
# who can read them) and decrypted at activation into /run/agenix, root-only
# and never on disk; Bitwarden ("Backblaze B2 – restic whitey") keeps the
# master copy.
#
# Left out: caches, container storage, Cargo's downloads, and every directory
# tagged as a cache (CACHEDIR.TAG: each Cargo target/, about 260 GB here).
# By hand, with these settings: `sudo restic-b2 snapshots`, `sudo restic-b2
# restore latest --target /tmp/r --include <path>`.
{ config, ... }:
let
  home = "/home/djshepard";
in
{
  # Decrypted by whitey's SSH host key, whether or not sshd runs.
  age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  age.secrets.restic-b2-env.file = ../../secrets/restic-b2-env.age;
  age.secrets.restic-b2-password.file = ../../secrets/restic-b2-password.age;

  services.restic.backups.b2 = {
    repository = "s3:https://s3.us-west-002.backblazeb2.com/whitey";
    passwordFile = config.age.secrets.restic-b2-password.path;
    environmentFile = config.age.secrets.restic-b2-env.path;
    initialize = false;
    createWrapper = true;

    paths = [ home ];
    exclude = [
      "${home}/.cache"
      "${home}/.local/share/containers"
      "${home}/.cargo/registry"
      "${home}/.cargo/git"
    ];
    extraBackupArgs = [ "--exclude-caches" "--one-file-system" ];

    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 5"
      "--keep-monthly 12"
    ];

    timerConfig = {
      OnCalendar = "daily";
      Persistent = true; # a day missed while off runs at the next boot
      RandomizedDelaySec = "1h";
    };
  };
}
