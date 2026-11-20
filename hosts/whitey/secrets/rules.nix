# hosts/whitey/secrets/rules.nix
#
# Who can read each of whitey's secrets (ragenix's rules; not named
# secrets.nix, which .gitignore keeps out): whitey itself, by its SSH host key,
# to decrypt them at activation; and djshepard's own key, so they can be edited
# or re-keyed from anywhere, and are not lost with the machine. Bitwarden keeps
# the master copy of every value.
#
# From this directory, to edit:
#   ragenix --rules rules.nix -e <name>.age -i ~/.ssh/id_ed25519
# after changing a recipient:
#   ragenix --rules rules.nix -r -i ~/.ssh/id_ed25519
let
  whitey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOepuxyf6QF7Mwa34Aqdv6WRADTlMNf1/Vyh7oNWTgO8";
  djshepard = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL47LQDAPJHvdVOKkP9ZcW/1T6dV6n5z7gx7ZEiv/XTD";
  all = [ whitey djshepard ];
in
{
  # AWS_ACCESS_KEY_ID=<keyID> and AWS_SECRET_ACCESS_KEY=<applicationKey>, one a
  # line: the B2 application key, limited to bucket whitey (restic-b2.nix).
  "restic-b2-env.age".publicKeys = all;
  # The restic repository's password.
  "restic-b2-password.age".publicKeys = all;
}
