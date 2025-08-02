# hosts/whitey/initrd-nvme-key.nix
{ lib, config, pkgs, ... }:

let
  secretsMapper = "/dev/mapper/secrets_crypt";
  mountPoint    = "/mnt/secrets-stage1";
  keyFile       = "${mountPoint}/keys/nvme.key";
  nvmeKeyScript = pkgs.writeShellScript "nvme-hw-key" ''
    set -euo pipefail
    mkdir -p ${mountPoint}
    mount -o ro ${secretsMapper} ${mountPoint}
    ${pkgs.nvme-cli}/bin/nvme key-set --namespace-id=1 --key=${keyFile} /dev/nvme0n1
    ${pkgs.nvme-cli}/bin/nvme key-set --namespace-id=1 --key=${keyFile} /dev/nvme1n1
    ${pkgs.coreutils}/bin/shred -u ${keyFile}
    umount ${mountPoint}
    /run/current-system/sw/bin/systemctl stop cryptsetup@secrets_crypt.service
  '';
in
{
  boot.initrd.systemd.enable = true;

  boot.initrd.systemd.units."nvme-hw-key" = {
    enable = true;
    wantedBy = [ "initrd.target" ];
    text = ''
      [Unit]
      Description=Inject NVMe key from stage1
      DefaultDependencies=no
      After=systemd-cryptsetup@secrets_crypt.service
      Before=sysroot.mount

      [Service]
      Type=oneshot
      ExecStart=${nvmeKeyScript}
    '';
  };
}
