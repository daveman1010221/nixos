{ pkgs, secrets, lib, ... }:

let
  s = secrets;

  secretsDev = s.PLACEHOLDER_SECRETS;     # LUKS partition (by-uuid or by-id)
  nvme0      = s.PLACEHOLDER_NVME0;       # first NVMe namespace/drive
  nvme1      = s.PLACEHOLDER_NVME1;       # second NVMe namespace/drive

  mountPoint = "/mnt/secrets-stage1";
  keyFile    = "${mountPoint}/keys/nvme.key";

  # systemd device unit for the block path (so our unit waits for the node)
  # e.g. /dev/disk/by-uuid/XXXX -> dev-disk-by\x2duuid-XXXX.device
  devPath = lib.removePrefix "/dev/" secretsDev;
  devUnit = "dev-" + (lib.escapeSystemdPath devPath) + ".device";

  # absolute store paths (so the script never relies on $PATH)
  cryptsetup = "${pkgs.cryptsetup}/bin/cryptsetup";
  mount      = "${pkgs.util-linux}/bin/mount";
  umount     = "${pkgs.util-linux}/bin/umount";
  nvme       = "${pkgs.nvme-cli}/bin/nvme";
  statBin    = "${pkgs.coreutils}/bin/stat";
  shred      = "${pkgs.coreutils}/bin/shred";
  cp         = "${pkgs.coreutils}/bin/cp";
  chmodBin   = "${pkgs.coreutils}/bin/chmod";
  syncBin    = "${pkgs.coreutils}/bin/sync";
in
{
  boot.initrd.systemd.enable = true;

  # ────────────────────────────────────────────────────────────────
  # OPTION 1: copy the required packages into the initrd closure
  # ────────────────────────────────────────────────────────────────
  boot.initrd.systemd.storePaths = with pkgs; [
    cryptsetup
    nvme-cli
    util-linux        # provides mount/umount (tiny, so cheap to include)
    coreutils         # cp / chmod / stat / shred / sync
    systemd           # udevadm + systemd-ask-password in stage-1
    kmod              # modprobe in stage-1
  ];

  boot.initrd.systemd.services.nvme-hw-key = {
    description = "Inject NVMe hardware-encryption key (stage-1)";
    wantedBy    = [ "initrd.target" ];
    # Don’t start until modules are loaded AND the block device exists
    after       = [ "systemd-modules-load.service" "systemd-udev-settle.service" devUnit ];
    requires    = [ "systemd-modules-load.service" devUnit ];
    before      = [ "sysroot.mount" ];

    # keep $PATH convenience (but script uses absolute paths anyway)
    path = with pkgs; [ bash coreutils util-linux cryptsetup nvme-cli kmod systemd ];

    serviceConfig.Type = "oneshot";

    script = ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail

      # Ensure dm-crypt is live even if modules-load raced us
      ${pkgs.kmod}/bin/modprobe dm-crypt || true

      # wait up to ~7.5 s for the LUKS device symlink to appear
      for i in {1..15}; do
          if [ -e "${secretsDev}" ]; then break; fi
          echo "[nvme-hw-key] waiting for ${secretsDev} …"
          ${pkgs.systemd}/bin/udevadm settle || true
          sleep 0.5
      done
      if [ ! -e "${secretsDev}" ]; then
          echo "[nvme-hw-key] Device ${secretsDev} never appeared" >&2
          exit 1
      fi

      echo "[nvme-hw-key] luksOpen ${secretsDev}"
      pass=$(${pkgs.systemd}/bin/systemd-ask-password --no-tty \
          "Passphrase for secrets_crypt" 2>&1)
      echo -n "$pass" | ${cryptsetup} luksOpen --key-file=- \
          ${secretsDev} secrets_crypt

      echo "[nvme-hw-key] Mounting secrets_crypt read-only"
      mkdir -p /tmp/boot
      ${mount} -o ro /dev/mapper/secrets_crypt /tmp/boot

      echo "[nvme-hw-key] Staging key in tmpfs"
      mkdir -p ${mountPoint}/keys
      ${mount} -t tmpfs -o size=10M,mode=0700 tmpfs ${mountPoint}

      echo "[nvme-hw-key] Copying nvme.key"
      ${cp} /tmp/boot/keys/nvme.key ${keyFile}
      ${chmodBin} 400 ${keyFile}
      ${syncBin}

      echo "[nvme-hw-key] Unmounting and closing secrets_crypt"
      ${umount} /tmp/boot
      ${cryptsetup} luksClose secrets_crypt

      echo "[nvme-hw-key] Injecting key into drives"
      ${nvme} key-set --namespace-id=1 --key=${keyFile} ${nvme0}
      ${nvme} key-set --namespace-id=1 --key=${keyFile} ${nvme1}

      echo "[nvme-hw-key] Verifying tmpfs, then shredding key"
      fsType=$(${statBin} -f -c %T ${mountPoint})
      if [ "$fsType" != "tmpfs" ]; then
        echo "ERROR: ${mountPoint} is $fsType, expected tmpfs"
        exit 1
      fi
      ${shred} -u ${keyFile}
    '';
  };
}
