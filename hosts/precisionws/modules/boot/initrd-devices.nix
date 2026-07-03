{ lib, pkgs, secrets, ... }:

let
  secretsDev = secrets.PLACEHOLDER_SECRETS;
  nvme0      = secrets.PLACEHOLDER_NVME0;
  nvme1      = secrets.PLACEHOLDER_NVME1;

  sensitiveMount = "/sensitive";

  # Absolute store paths — Nix will pull these into the initrd closure
  # automatically via script interpolation. Do NOT add these to storePaths
  # or path: packages with split outputs (bin, man, etc.) break buildEnv.
  cryptsetup  = "${pkgs.cryptsetup.bin}/bin/cryptsetup";
  mount       = "${pkgs.util-linux}/bin/mount";
  umount      = "${pkgs.util-linux}/bin/umount";
  cp          = "${pkgs.coreutils}/bin/cp";
  shred       = "${pkgs.coreutils}/bin/shred";
  chmodBin    = "${pkgs.coreutils}/bin/chmod";
  mkdirBin    = "${pkgs.coreutils}/bin/mkdir";
  syncBin     = "${pkgs.coreutils}/bin/sync";
  statBin     = "${pkgs.coreutils}/bin/stat";
  catBin      = "${pkgs.coreutils}/bin/cat";
  findBin     = "${pkgs.findutils}/bin/find";
  mdadmBin    = "${pkgs.mdadm}/bin/mdadm";
  lvmBin      = "${pkgs.lvm2.bin}/bin/lvm";
  udevadm     = "${pkgs.systemd}/bin/udevadm";
  modprobe    = "${pkgs.kmod}/bin/modprobe";
  keyctl      = "${pkgs.keyutils}/bin/keyctl";
  unameBin    = "${pkgs.coreutils}/bin/uname";
  dmsetupBin  = "${pkgs.lvm2.bin}/bin/dmsetup";
in
{
  boot = {
    initrd = {
      # boot_crypt is now a normal encrypted /boot volume, handled entirely
      # by nixpkgs's standard LUKS + fileSystems machinery. It carries no
      # NVMe key material and this initrd service never touches it.
      luks.devices.boot_crypt = {
        device = "/dev/disk/by-uuid/bd7cb388-7b08-4264-bee0-7477fd48fa59";
        preLVM = true;
        allowDiscards = true;
      };

      systemd.enable = true;

      # systemd itself must be explicitly in the closure for ask-password
      # infrastructure to work. Packages with split outputs (cryptsetup,
      # lvm2, util-linux, e2fsprogs) must NOT go here — they break buildEnv.
      # Use interpolated store paths in the script instead.
      systemd.storePaths = [
        pkgs.systemd
        pkgs.cryptsetup.bin
        pkgs.util-linux
        pkgs.coreutils
        pkgs.findutils
        pkgs.kmod
        pkgs.mdadm
        pkgs.lvm2.bin
        pkgs.e2fsprogs
        pkgs.keyutils
      ];

      systemd.services.secrets-key-stage = {
        description = "Unlock secrets_crypt, stage NVMe LUKS keys, unlock NVMe devices";

        unitConfig.DefaultDependencies = false;
        wantedBy = [ "initrd.target" ];
        before   = [ "initrd-root-fs.target" "sysroot.mount" ];
        after    = [ "systemd-modules-load.service" ];

        serviceConfig = {
          Type            = "oneshot";
          RemainAfterExit = true;
          TimeoutStartSec = "120";
          StandardInput   = "null";   # password agent brokers the prompt
          StandardOutput  = "journal";
          StandardError   = "journal";
          PrivateDevices  = false;
          UMask           = "0077";
        };

        script = ''
          #!/bin/bash
          set -uo pipefail
          # NOTE: 'set -e' intentionally omitted here so the diagnostic dump
          # at the end always runs even if an earlier step fails. Explicit
          # exit-code checks are used instead where it matters.

          # secrets_crypt only ever holds NVMe key/header material and is
          # fully closed the instant we're done with it — unlike boot_crypt,
          # nothing downstream needs it to stay open.
          cleanup() {
            ${umount} /tmp/secrets_src         2>/dev/null || true
            ${cryptsetup} luksClose secrets_crypt 2>/dev/null || true
            ${umount} ${sensitiveMount} 2>/dev/null || true
          }
          trap cleanup EXIT

          fail_banner() {
            echo
            echo "─────────────────────────────────────────────"
            echo "[secrets-key-stage] ERROR: boot chain failed"
            echo
            echo "Manual recovery:"
            echo "  1. Unlock secrets_crypt:"
            echo "       ${cryptsetup} luksOpen ${secretsDev} secrets_crypt"
            echo "  2. Mount and inspect keys:"
            echo "       ${mount} -t ext4 /dev/mapper/secrets_crypt /tmp/secrets_src"
            echo "       ls /tmp/secrets_src/keys"
            echo "  3. Unlock NVMe devices manually:"
            echo "       ${cryptsetup} luksOpen --header /tmp/secrets_src/keys/nvme0n1.header \\"
            echo "           --key-file /tmp/secrets_src/keys/nvme0n1.key ${nvme0} nvme0n1_crypt"
            echo "       ${cryptsetup} luksOpen --header /tmp/secrets_src/keys/nvme1n1.header \\"
            echo "           --key-file /tmp/secrets_src/keys/nvme1n1.key ${nvme1} nvme1n1_crypt"
            echo "  4. Once unlocked, continue boot:"
            echo "       systemctl default"
            echo "─────────────────────────────────────────────"
            echo
          }

          diag_dump() {
            echo
            echo "═════════════════ DIAGNOSTIC DUMP ═════════════════"
            echo "[diag] kernel: $(${unameBin} -a)"
            echo
            echo "[diag] --- /proc/crypto (name/driver/module/type/priority only) ---"
            ${catBin} /proc/crypto | ${pkgs.gnugrep}/bin/grep -E '^(name|driver|module|type|priority)' || \
              ${catBin} /proc/crypto
            echo
            echo "[diag] --- dmsetup targets ---"
            ${dmsetupBin} targets 2>&1 || true
            echo
            echo "[diag] --- dmsetup version ---"
            ${dmsetupBin} version 2>&1 || true
            echo
            echo "[diag] --- keyctl show (session keyring) ---"
            ${keyctl} show 2>&1 || true
            echo "[diag] --- keyctl list @u ---"
            ${keyctl} list @u 2>&1 || true
            echo
            echo "[diag] --- cryptsetup version ---"
            ${cryptsetup} --version 2>&1 || true
            echo
            if [ -f ${sensitiveMount}/keys/nvme0n1.header ]; then
              echo "[diag] --- luksDump nvme0n1.header ---"
              ${cryptsetup} luksDump ${sensitiveMount}/keys/nvme0n1.header 2>&1 || true
            elif [ -f /tmp/secrets_src/keys/nvme0n1.header ]; then
              echo "[diag] --- luksDump nvme0n1.header (from /tmp/secrets_src) ---"
              ${cryptsetup} luksDump /tmp/secrets_src/keys/nvme0n1.header 2>&1 || true
            else
              echo "[diag] nvme0n1.header not found in either staging location"
            fi
            echo "═════════════════ END DIAGNOSTIC DUMP ═════════════════"
            echo
          }

          # ── Load crypto/dm/nvme modules ───────────────────────────────────
          echo "[secrets-key-stage] Loading kernel modules..."
          ${modprobe} -ab dm-mod    || true
          ${modprobe} -ab dm-crypt  || true
          ${modprobe} -ab aesni-intel gf128mul xts cbc cryptd essiv authenc sha256 aes || true
          ${modprobe} -ab nvme nvme-core || true
          echo "[secrets-key-stage] Kernel modules loaded."

          echo "[secrets-key-stage] Waiting for udev to settle..."
          ${udevadm} settle || true
          echo "[secrets-key-stage] udev settled."

          # ── Step 1: unlock secrets_crypt ────────────────────────────────────
          echo "[secrets-key-stage] Requesting passphrase for secrets_crypt..."
          pass=$(${pkgs.systemd}/bin/systemd-ask-password --no-tty "Passphrase for secrets_crypt" 2>&1)
          if [ -z "$pass" ]; then
            echo "[secrets-key-stage] ERROR: empty passphrase" >&2
            fail_banner; diag_dump; exit 1
          fi
          echo "[secrets-key-stage] Passphrase received, opening secrets_crypt..."
          echo -n "$pass" | ${cryptsetup} luksOpen --key-file=- ${secretsDev} secrets_crypt
          rc=$?
          unset pass
          if [ $rc -ne 0 ]; then
            echo "[secrets-key-stage] ERROR: failed to open secrets_crypt (rc=$rc)" >&2
            fail_banner; diag_dump; exit 1
          fi
          echo "[secrets-key-stage] secrets_crypt opened successfully."

          # ── Step 2: mount secrets_crypt, stage keys to tmpfs ────────────────
          echo "[secrets-key-stage] Mounting secrets_crypt..."
          ${mkdirBin} -p /tmp/secrets_src
          ${mount} -t ext4 /dev/mapper/secrets_crypt /tmp/secrets_src
          echo "[secrets-key-stage] secrets_crypt mounted."

          echo "[secrets-key-stage] Staging keys to tmpfs..."
          ${mkdirBin} -p ${sensitiveMount}
          ${mount} -t tmpfs -o size=50M,mode=0700,noswap tmpfs ${sensitiveMount}
          ${mkdirBin} -p --mode=0700 ${sensitiveMount}/keys

          for f in nvme0n1.header nvme1n1.header nvme0n1.key nvme1n1.key; do
            if [ ! -f /tmp/secrets_src/keys/$f ]; then
              echo "[secrets-key-stage] ERROR: missing key file: $f" >&2
              fail_banner; diag_dump; exit 1
            fi
            ${cp} /tmp/secrets_src/keys/$f ${sensitiveMount}/keys/$f
            ${chmodBin} 0400 ${sensitiveMount}/keys/$f
            echo "[secrets-key-stage] Staged: $f"
          done

          ${syncBin}
          echo "[secrets-key-stage] Keys staged and synced."

          # ── Diagnostic dump runs BEFORE we close secrets_crypt and BEFORE ──
          # ── the NVMe unlock attempt, so headers/keys are still readable   ──
          diag_dump

          echo "[secrets-key-stage] Unmounting and closing secrets_crypt..."
          ${umount} /tmp/secrets_src
          ${cryptsetup} luksClose secrets_crypt
          echo "[secrets-key-stage] secrets_crypt closed."

          # Disable cleanup trap — sensitive mount stays up until after NVMe unlock
          trap - EXIT

          # ── Step 3: unlock NVMe devices ───────────────────────────────────
          echo "[secrets-key-stage] Unlocking nvme0n1_crypt (verbose+debug)..."
          ${cryptsetup} luksOpen \
            --header ${sensitiveMount}/keys/nvme0n1.header \
            --key-file ${sensitiveMount}/keys/nvme0n1.key \
            --verbose --debug \
            ${nvme0} nvme0n1_crypt
          rc0=$?
          if [ $rc0 -ne 0 ]; then
            echo "[secrets-key-stage] ERROR: nvme0n1_crypt luksOpen failed (rc=$rc0)" >&2
            fail_banner
            echo "[secrets-key-stage] Keys NOT shredded — still in ${sensitiveMount}/keys for manual recovery."
            exit 1
          fi
          echo "[secrets-key-stage] nvme0n1_crypt opened successfully."

          echo "[secrets-key-stage] Unlocking nvme1n1_crypt (verbose+debug)..."
          ${cryptsetup} luksOpen \
            --header ${sensitiveMount}/keys/nvme1n1.header \
            --key-file ${sensitiveMount}/keys/nvme1n1.key \
            --verbose --debug \
            ${nvme1} nvme1n1_crypt
          rc1=$?
          if [ $rc1 -ne 0 ]; then
            echo "[secrets-key-stage] ERROR: nvme1n1_crypt luksOpen failed (rc=$rc1)" >&2
            fail_banner
            echo "[secrets-key-stage] Keys NOT shredded — still in ${sensitiveMount}/keys for manual recovery."
            exit 1
          fi
          echo "[secrets-key-stage] nvme1n1_crypt opened successfully."

          # ── Step 4: shred keys ────────────────────────────────────────────
          echo "[secrets-key-stage] Verifying ${sensitiveMount} is tmpfs before shredding..."
          fsType=$(${statBin} -f -c %T ${sensitiveMount})
          if [ "$fsType" != "tmpfs" ]; then
            echo "[secrets-key-stage] ERROR: ${sensitiveMount} is $fsType, expected tmpfs" >&2
            fail_banner; diag_dump; exit 1
          fi
          echo "[secrets-key-stage] Shredding keys..."
          ${findBin} ${sensitiveMount}/keys -type f -exec ${shred} -u {} +
          ${umount} ${sensitiveMount} || true
          rmdir ${sensitiveMount} 2>/dev/null || true
          echo "[secrets-key-stage] Keys shredded, sensitive mount removed."

          # ── Step 5: assemble RAID and activate LVM ────────────────────────
          echo "[secrets-key-stage] Assembling RAID..."
          ${mdadmBin} --assemble --scan || true
          echo "[secrets-key-stage] Activating LVM..."
          ${lvmBin} vgchange -ay || true
          echo "[secrets-key-stage] RAID assembled, LVM activated."

          echo "[secrets-key-stage] Waiting for udev to settle..."
          ${udevadm} settle || true

          echo "[secrets-key-stage] Done."
        '';

        unitConfig.FailureAction = "none";
        unitConfig.OnFailure     = [ "emergency.target" ];
      };
    };
  };
}
