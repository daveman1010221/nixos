# hosts/whitey/initrd-nvme-key.nix
{ lib, config, pkgs, ... }:

let
  secretsMapper = "/dev/mapper/secrets_crypt";
  mountPoint    = "/mnt/secrets-stage1";
  keyFile       = "${mountPoint}/keys/nvme.key";
in
{
  boot.initrd.systemd.enable = true;

  boot.initrd.systemd.extraUnits."nvme-hw-key.service" = {
    description = "Mount /secrets, load NVMe hardware-encryption key, then close";
    after       = [ "cryptsetup@secrets_crypt.service" ];
    before      = [ "sysroot.mount" ];

    serviceConfig = {
      Type      = "oneshot";
      RemainAfterExit = false;
      ExecStart = pkgs.writeShellScript "nvme-hw-key" ''
        set -euo pipefail
        # 1. mount read-only
        mkdir -p ${mountPoint}
        mount -o ro ${secretsMapper} ${mountPoint}

        # 2. feed key to both drives
        ${pkgs.nvme}/bin/nvme key-set  --namespace-id=1 \
              --key=${keyFile}  /dev/nvme0n1
        ${pkgs.nvme}/bin/nvme key-set  --namespace-id=1 \
              --key=${keyFile}  /dev/nvme1n1

        # 3. wipe the key copy in RAM
        ${pkgs.coreutils}/bin/shred -u ${keyFile}

        # 4. unmount & close container
        umount ${mountPoint}
        /run/current-system/sw/bin/systemctl stop cryptsetup@secrets_crypt.service
      '';
    };
  };
}
