# hosts/whitey/initrd-nvme-key.nix
{ lib, config, pkgs, ... }:

let
  mountPoint    = "/mnt/secrets-stage1";
  keyFile       = "${mountPoint}/keys/nvme.key";

  nvmeKeyScript = pkgs.writeShellScript "nvme-hw-key" ''
    set -euo pipefail

    echo "[nvme-hw-key] Mounting secrets_crypt"
    mkdir -p /tmp/boot
    mount -o ro /dev/mapper/secrets_crypt /tmp/boot

    echo "[nvme-hw-key] Setting up tmpfs"
    mkdir -p ${mountPoint}/keys
    mount -t tmpfs -o size=10M,mode=0700 tmpfs ${mountPoint}

    echo "[nvme-hw-key] Copying nvme.key"
    cp /tmp/boot/keys/nvme.key ${keyFile}
    chmod 400 ${keyFile}
    sync

    echo "[nvme-hw-key] Cleaning up"
    umount /tmp/boot
    cryptsetup luksClose secrets_crypt

    echo "[nvme-hw-key] Injecting NVMe key"
    ${pkgs.nvme-cli}/bin/nvme key-set --namespace-id=1 --key=${keyFile} /dev/nvme0n1
    ${pkgs.nvme-cli}/bin/nvme key-set --namespace-id=1 --key=${keyFile} /dev/nvme1n1

    echo "[nvme-hw-key] Validating tmpfs before shred..."
    FSTYPE=$(stat -f -c %T ${mountPoint})
    if [ "$FSTYPE" != "tmpfs" ]; then
      echo "ERROR: ${mountPoint} is not tmpfs (it's $FSTYPE). Aborting shred for safety."
      exit 1
    fi

    echo "[nvme-hw-key] Shredding key from tmpfs..."
    ${pkgs.coreutils}/bin/shred -u ${keyFile}
  '';
in {
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
