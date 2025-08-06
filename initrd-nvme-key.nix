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
  devPath  = lib.removePrefix "/dev/" secretsDev;
  # First escape original hyphens, THEN turn '/' into '-' so only original '-' get escaped.
  devEscHy = lib.replaceStrings [ "-" ] [ "\\x2d" ] devPath;
  devEsc   = lib.replaceStrings [ "/" ] [ "-" ] devEscHy;
  devUnit  = "dev-" + devEsc + ".device";

  # absolute store paths (so the script never relies on $PATH)
  cryptsetup = "${pkgs.cryptsetup}/bin/cryptsetup";
  mount      = "${pkgs.util-linux}/bin/mount";
  umount     = "${pkgs.util-linux}/bin/umount";
  nvme       = "${pkgs.nvme-cli}/bin/nvme";
  statBin    = "${pkgs.coreutils}/bin/stat";
  shred      = "${pkgs.coreutils}/bin/shred";
  awk        = "${pkgs.gawk}/bin/awk";
  cp         = "${pkgs.coreutils}/bin/cp";
  chmodBin   = "${pkgs.coreutils}/bin/chmod";
  modprobe   = "${pkgs.kmod}/bin/modprobe";
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
    gawk              # for robust parsing of 'nvme sed discover'
    expect            # to feed nvme sed --ask-key non-interactively
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
    path = with pkgs; [ bash coreutils util-linux cryptsetup nvme-cli gawk expect kmod systemd ];

    serviceConfig = {
      Type = "oneshot";
      # Make sure it’s truly early-boot and not pulling in defaults
      # that might reorder us behind mounts/fsck.
      StandardOutput = "journal+console";
      StandardError  = "journal+console";
    };
    unitConfig.DefaultDependencies = false;

    script = ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail

      # Ensure the dm + crypto stack is live even if we race module load
      ${modprobe} -ab dm_mod || true
      ${modprobe} -ab encrypted_keys trusted || true
      ${modprobe} -ab xts aesni_intel gf128mul crypto_simd sha256 essiv || true
      ${modprobe} -ab dm_crypt || true

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
      mkdir -p ${mountPoint}
      ${mount} -t tmpfs -o size=10M,mode=0700 tmpfs ${mountPoint}
      mkdir -p ${mountPoint}/keys

      echo "[nvme-hw-key] Copying nvme.key"
      [ -f /tmp/boot/keys/nvme.key ] || { echo "nvme.key missing in secrets volume"; exit 1; }
      ${pkgs.coreutils}/bin/install -D -m 0400 /tmp/boot/keys/nvme.key ${keyFile}

      ${syncBin}

      echo "[nvme-hw-key] Unmounting and closing secrets_crypt"
      ${umount} /tmp/boot
      ${cryptsetup} luksClose secrets_crypt

      echo "[nvme-hw-key] Injecting key into drives (SED Opal unlock)"
      # Read ASCII passphrase from the staged file (strip trailing newline)
      PW="$(${pkgs.coreutils}/bin/tr -d '\n' < ${keyFile})"
      if [ -z "$PW" ]; then
      echo "nvme.key is empty" >&2
      exit 1
      fi

      # Optional: log current state
      ${nvme} sed discover ${nvme0} || true
      ${nvme} sed discover ${nvme1} || true

      # Unlock both drives (nvme-cli prompts; drive with expect to avoid a TTY)
      for dev in ${nvme0} ${nvme1}; do
        ${pkgs.expect}/bin/expect -c '
          set timeout 20
          set pw  [lindex $argv 0]
          set dev [lindex $argv 1]
          spawn '"${nvme}"' sed unlock $dev --ask-key
          expect -re {(?i)pass(word)?|key.*:} { send -- "$pw\r" }
          expect {
            eof     { }
            timeout { exit 1 }
          }
          # return child exit status
          catch wait result
          exit [lindex $result 3]
        ' "$PW" "$dev"
      done

      # Quick verification that both are unlocked
      for dev in ${nvme0} ${nvme1}; do
        out="$(${nvme} sed discover "$dev" 2>/dev/null || true)"
        locked="$(echo "$out" | ${awk} -F: "/^[[:space:]]*Locked/{gsub(/^[ \\t]+|[ \\t]+$/,\"\",\$2); print \$2}")"
        if [ "$locked" != "No" ]; then
          echo "[nvme-hw-key] ERROR: $dev still locked" >&2
          exit 1
        fi
      done

      echo "[nvme-hw-key] Verifying tmpfs, then shredding key"
      fsType=$(${statBin} -f -c %T ${mountPoint})
      if [ "$fsType" != "tmpfs" ]; then
        echo "ERROR: ${mountPoint} is $fsType, expected tmpfs"
        exit 1
      fi
      ${shred} -u ${keyFile}

      # Drop the tmpfs so the key file cannot be recovered later
      ${umount} ${mountPoint} || true
      rmdir ${mountPoint} 2>/dev/null || true
    '';
  };
}
