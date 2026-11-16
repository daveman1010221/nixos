# hosts/whitey/modules/services/polar-mutants.nix
#
# Mutation testing runs as its own user. A mutant is our code changed on
# purpose, and it runs with all of its user's rights: on 2026-11-15 one mutant
# of polar-eden's reaper SIGKILLed every process User owned. As
# polar-mutants it can reach only its own processes, files and sockets: not
# User's session, ~/.config, SSH agent, podman socket or kubeconfigs. Its
# network is limited in nftables.nft (meta skuid 1500).
#
# Hand-off: User stages a git bundle in /var/lib/polar-mutants/exchange/in
# (`polar-mutants-stage`), then starts the run with `sudo -u polar-mutants
# polar-mutants-run <name> -- <polar-eden collect args>`; results land in
# /var/lib/polar-mutants/exchange/out/<name>. sudo resets the environment, so
# nothing of User's (KUBECONFIG, SSH_AUTH_SOCK, DOCKER_HOST) reaches the
# run.
{ pkgs, ... }:
let
  # fixed: nftables matches it by number (names do not resolve in the ruleset
  # check's sandbox)
  uid = 1500;
  home = "/var/lib/polar-mutants";
  exchange = "${home}/exchange";

  # As polar-mutants: clone the staged bundle fresh, build polar-eden there,
  # and run it under this user's own manager.
  run = pkgs.writeShellApplication {
    name = "polar-mutants-run";
    runtimeInputs = [ pkgs.git pkgs.coreutils pkgs.systemd pkgs.nix ];
    text = ''
      name="''${1:?usage: polar-mutants-run <name> -- <polar-eden collect args...>}"; shift
      [ "''${1:-}" = "--" ] && shift
      case "$name" in (*[!A-Za-z0-9._-]*|""|.*) echo "polar-mutants-run: bad name: $name" >&2; exit 2;; esac
      [ "$(id -u)" = "${toString uid}" ] || { echo "polar-mutants-run: run me as polar-mutants" >&2; exit 2; }

      export HOME=${home}
      # sudo keeps the caller's directory, which polar-mutants may not be able to read (git clone fails there).
      cd "$HOME"
      export XDG_RUNTIME_DIR=/run/user/${toString uid}
      export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
      export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock
      systemctl --user enable --now podman.socket >/dev/null

      bundle=${exchange}/in/$name.bundle
      work=${home}/work/$name
      out=${exchange}/out/$name
      rm -rf "$work"; mkdir -p "$work" "$out"
      git clone --quiet "$bundle" "$work"
      # Relative paths in the arguments (--out, --outcomes, --resume) land in $out, where User reads them.
      cd "$out"
      nix develop "$work" --command ${collect}/bin/polar-mutants-collect "$work" "$@" 2>&1 | tee "$out/run.log"
    '';
  };

  # Inside the clone's dev shell: build polar-eden there and run `collect` on
  # that workspace. No runtimeInputs, so cargo and the toolchain are the dev shell's.
  collect = pkgs.writeShellApplication {
    name = "polar-mutants-collect";
    runtimeInputs = [ ];
    text = ''
      work="''${1:?usage: polar-mutants-collect <workspace> <polar-eden collect args...>}"; shift
      manifest="$work/src/agents/Cargo.toml"
      env -u RUST_LOG CARGO_PROFILE_DEV_DEBUG=line-tables-only cargo build -q --manifest-path "$manifest" -p polar-eden
      "$work/src/agents/target/debug/polar-eden" collect --manifest-path "$manifest" "$@"
    '';
  };

  # As User: stage a revision of the repository at the working directory for
  # polar-mutants to clone.
  stage = pkgs.writeShellApplication {
    name = "polar-mutants-stage";
    runtimeInputs = [ pkgs.git pkgs.coreutils ];
    text = ''
      rev="''${1:-HEAD}"
      name="''${2:-$(git rev-parse --short=8 "$rev")}"
      git bundle create "${exchange}/in/$name.bundle" "$rev" HEAD
      chmod 0640 "${exchange}/in/$name.bundle"
      echo "$name"
    '';
  };
in
{
  users.groups.polar-mutants = { };
  # User joins the group to stage bundles and read results; that gives
  # polar-mutants nothing of User's.
  users.users.djshepard.extraGroups = [ "polar-mutants" ];

  users.users.polar-mutants = {
    # a user manager of its own (systemctl --user, slices and scopes) and
    # rootless podman
    isNormalUser = true;
    inherit uid home;
    group = "polar-mutants";
    createHome = true;
    homeMode = "0750";

    # its manager runs with nobody logged in
    linger = true;

    # no login; reached only through sudo below
    hashedPassword = "!";
    subUidRanges = [ { startUid = 200000; count = 65536; } ];
    subGidRanges = [ { startGid = 200000; count = 65536; } ];
  };

  systemd.tmpfiles.rules = [
    "d ${exchange}     2770 polar-mutants polar-mutants -"
    "d ${exchange}/in  2770 polar-mutants polar-mutants -"
    "d ${exchange}/out 2770 polar-mutants polar-mutants -"
  ];

  # User (and the Claude sessions running as User) may start a run as
  # polar-mutants without a password:
  # only this command, and only as that user, which has less than User has.
  security.sudo.extraRules = [
    {
      users = [ "djshepard" ];
      runAs = "polar-mutants";
      # sudo matches the path it resolves through PATH, the system profile's, as well as the store path itself.
      commands = [
        { command = "${run}/bin/polar-mutants-run"; options = [ "NOPASSWD" ]; }
        { command = "/run/current-system/sw/bin/polar-mutants-run"; options = [ "NOPASSWD" ]; }
      ];
    }
  ];

  environment.systemPackages = [ run stage ];

  # podman's log driver for the polar-mutants user, as User's (k8s-file;
  # journald made container tests time out).
  environment.etc."polar-mutants/containers.conf".text = ''
    [containers]
    log_driver = "k8s-file"
  '';
  systemd.user.services.polar-mutants-containers-conf = {
    description = "polar-mutants: podman settings";
    unitConfig.ConditionUser = "polar-mutants";
    wantedBy = [ "default.target" ];
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p ${home}/.config/containers
      ln -sf /etc/polar-mutants/containers.conf ${home}/.config/containers/containers.conf
    '';
  };
}
