# whitey's kernel sandbox: the shared one (flakes/kernel/sandbox), for this host's kernel-version.nix.
# nix develop --impure --file /etc/nixos/hosts/whitey/kernel-sandbox/shell.nix
import ../../../flakes/kernel/sandbox/shell.nix { hostDir = ../.; }
