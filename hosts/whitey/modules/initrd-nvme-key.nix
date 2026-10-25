{ config, pkgs, secrets, lib, ... }:

let
  s = secrets;

  # Prefer a stable by-id GLOB here, e.g. "/dev/disk/by-id/usb-Keypad200_*"
  # UUIDs change when you reformat and may not exist in initrd yet.
  secretsDev = s.PLACEHOLDER_SECRETS;     # LUKS partition (by-uuid or by-id)

  nvme0      = s.PLACEHOLDER_NVME0;       # first NVMe namespace/drive
  nvme1      = s.PLACEHOLDER_NVME1;       # second NVMe namespace/drive

  mountPoint = "/mnt/secrets-stage1";

  # If secretsDev is NOT a glob, we can synthesize the .device unit name.
  isGlob = lib.any (p: lib.hasInfix p secretsDev) [ "*" "?" "[" ];

  devPath  = lib.removePrefix "/dev/" secretsDev;

  # Escape '-' first, then '/' → '-' (systemd device unit convention)
  devEscHy = lib.replaceStrings [ "-" ] [ "\\x2d" ] devPath;
  devEsc   = lib.replaceStrings [ "/" ] [ "-" ] devEscHy;
  devUnit  = "dev-" + devEsc + ".device";

  # absolute store paths (so the script never relies on $PATH)
  cryptsetupBin = "${pkgs.cryptsetup}/bin/cryptsetup";
  mount      = "${pkgs.util-linux}/bin/mount";
  umount     = "${pkgs.util-linux}/bin/umount";
  nvme       = "${pkgs.nvme-cli}/bin/nvme";
  statBin    = "${pkgs.coreutils}/bin/stat";
  sedKeyBin  = "${pkgs.sed-key}/bin/sed-key";
  shred      = "${pkgs.coreutils}/bin/shred";
  awk        = "${pkgs.gawk}/bin/awk";
  cp         = "${pkgs.coreutils}/bin/cp";
  chmodBin   = "${pkgs.coreutils}/bin/chmod";
  modprobe   = "${pkgs.kmod}/bin/modprobe";
  syncBin    = "${pkgs.coreutils}/bin/sync";
  findBin    = "${pkgs.findutils}/bin/find";
  lvmBin     = "${pkgs.lvm2}/bin/lvm";
  mdadmBin   = "${pkgs.mdadm}/bin/mdadm";
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
    sed-key           # replaces expect + nvme sed unlock (didn't work because of the tty issue)
    systemd           # udevadm + systemd-ask-password in stage-1
    kmod              # modprobe in stage-1
    findutils
    mdadm
    lvm2
  ];

  boot.initrd.systemd.services.nvme-hw-key = {
    description = "Inject NVMe hardware-encryption key (stage-1)";

    # Run *very* early, and finish before md/LVM/fsck/root try to start.
    unitConfig.DefaultDependencies = false;
    wantedBy = [ "initrd.target" ];
    before = [ "initrd-root-fs.target" ];

    # Don’t even start until modules are loaded; if we have a concrete device
    # (no glob), also wait for its .device unit.
    after    = [ "systemd-modules-load.service" ] ++ lib.optionals (!isGlob) [ devUnit ];

    # keep $PATH convenience (but script uses absolute paths anyway)
    path = with pkgs; [ bash coreutils util-linux cryptsetup nvme-cli gawk kmod systemd findutils sed-key mdadm lvm2];

    serviceConfig = {
      Type = "oneshot";
      TimeoutStartSec = "60";

      # Early-boot hygiene and make sure nvme-cli can get a TTY
      StandardInput  = "null";
      StandardOutput = "journal";
      StandardError  = "journal";
      PrivateDevices = false;
      UMask = "0077";  # keep any temp copies/dirs locked down
    };
    unitConfig.FailureAction = "none";
    unitConfig.OnFailure = [ "nvme-hw-key-diag.service" "emergency.target" ];

    script = ''
      #!${pkgs.bash}/bin/bash
      set -euo pipefail
      
      cleanup() {
        ${umount} /tmp/boot 2>/dev/null || true
        ${cryptsetupBin} luksClose secrets_crypt 2>/dev/null || true
        ${umount} ${mountPoint} 2>/dev/null || true
      }
      trap cleanup EXIT

      fail_banner() {
        echo
        echo "─────────────────────────────────────────────"
        echo "[nvme-hw-key] ERROR: failed to unlock NVMe SED devices"
        echo "[nvme-hw-key] Data is still encrypted; system cannot boot root."
        echo "View logs:   journalctl -b -u nvme-hw-key.service"
        echo
        echo "Manual recovery steps:"
        echo "  1. Unlock the LUKS /secrets volume:"
        echo "       ${cryptsetupBin} luksOpen ${secretsDev} secrets_crypt"
        echo
        echo "  2. Mount it read-only and inspect staged keys:"
        echo "       ${mount} -o ro /dev/mapper/secrets_crypt /mnt"
        echo "       ls /mnt/keys"
        echo
        echo "  3. Manually unlock each NVMe device:"
        echo "       ${nvme} sed unlock ${nvme0} --ask-key"
        echo "       ${nvme} sed unlock ${nvme1} --ask-key"
        echo
        echo "  4. Verify unlock state:"
        echo "       ${nvme} sed discover ${nvme0} | grep Locked"
        echo "       ${nvme} sed discover ${nvme1} | grep Locked"
        echo
        echo "  5. Once drives show 'Locked: No', continue boot with:"
        echo "       systemctl default"
        echo "─────────────────────────────────────────────"
        echo
      }

      # Ensure the dm + crypto stack is live even if we race module load
      ${modprobe} -ab nvme nvme_core || true
      ${modprobe} -ab dm_mod || true
      ${modprobe} -ab encrypted_keys trusted || true
      ${modprobe} -ab xts aesni_intel gf128mul crypto_simd sha256 essiv || true
      ${modprobe} -ab dm_crypt || true

      # Be explicit: don’t proceed until udev finished creating nodes we care about
      ${pkgs.systemd}/bin/udevadm settle || true

      nvme_bin="${nvme}"   # binary path provided by Nix
      [ -x "$nvme_bin" ] || { echo "[nvme-hw-key] nvme-cli missing in initrd"; fail_banner; exit 1; }

      # Resolve the token device from a by-* glob at *runtime* (no build-time expansion).
      SECRETS_GLOB='${secretsDev}'
      NODE=""
      for i in $(seq 1 30); do
        # Use absolute ls and `--` to avoid oddities if the glob starts with '-'
        NODE="$(${pkgs.coreutils}/bin/ls -1 -- $SECRETS_GLOB 2>/dev/null | head -n1 || true)"
        if [ -n "$NODE" ] && [ -e "$NODE" ]; then
          break
        fi
        printf '[nvme-hw-key] waiting for "%s" …\n' "$SECRETS_GLOB"
        ${pkgs.systemd}/bin/udevadm settle || true
        sleep 0.25
      done
      if [ -z "$NODE" ] || [ ! -e "$NODE" ]; then
        printf '[nvme-hw-key] Device "%s" never appeared\n' "$SECRETS_GLOB" >&2
        fail_banner
        exit 1
      fi

      echo "[nvme-hw-key] luksOpen $NODE"
      pass=$(${pkgs.systemd}/bin/systemd-ask-password --no-tty \
          "Passphrase for secrets_crypt" 2>&1)
      [ -n "$pass" ] || { echo "[nvme-hw-key] Empty passphrase"; fail_banner; exit 1; }
      echo -n "$pass" | ${cryptsetupBin} luksOpen --key-file=- \
          "$NODE" secrets_crypt

      echo "[nvme-hw-key] Mounting secrets_crypt read-only"
      mkdir -p /tmp/boot
      ${mount} -o ro /dev/mapper/secrets_crypt /tmp/boot

      echo "[nvme-hw-key] Staging key in tmpfs"
      mkdir -p ${mountPoint}
      ${mount} -t tmpfs -o size=10M,mode=0700 tmpfs ${mountPoint}
      mkdir -p ${mountPoint}/keys

      echo "[nvme-hw-key] Staging keys directory"
      [ -d /tmp/boot/keys ] || { echo "keys/ directory missing in secrets volume"; fail_banner; exit 1; }

      # copy only key files; preserve mode, but enforce 0400 later per file
      old_umask="$(umask)"; umask 077
      ${cp} -a /tmp/boot/keys/. ${mountPoint}/keys/
      umask "$old_umask"
      ${chmodBin} 0700 ${mountPoint}/keys || true

      ${syncBin}

      echo "[nvme-hw-key] Unmounting and closing secrets_crypt"
      ${umount} /tmp/boot
      ${cryptsetupBin} luksClose secrets_crypt

      echo "[nvme-hw-key] Injecting keys per-controller (SED Opal unlock)"

      # Helper: read controller serial from a namespace node
      get_serial() {
        local dev="$1" ctrl out sn
        [[ -n "$dev" ]] || return 2

        [[ "$dev" == /dev/* ]] || dev="/dev/$dev"
        local real; real="$(readlink -f -- "$dev" 2>/dev/null || echo "$dev")"

        local base; base="$(basename -- "$real")"
        if [[ "$base" =~ ^(nvme[0-9]+)n[0-9]+(p[0-9]+)?$ ]]; then
          ctrl="/dev/''${BASH_REMATCH[1]}"
        else
          ctrl="$real"
        fi

        out="$("$nvme_bin" id-ctrl "$ctrl" 2>/dev/null)" || return 1
        sn="$(printf '%s\n' "$out" | awk -F: '/^[[:space:]]*sn[[:space:]]*:/{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')"
        [[ -n "$sn" ]] || return 1
        printf '%s\n' "$sn"
      }
      
      # Return "no", "yes", or "unknown" for Locked: … (case/spacing tolerant)
      locked_state() {
        local dev="$1" out state
        out="$("$nvme_bin" sed discover "$dev" 2>/dev/null || true)"
        # Extract the value to the right of "Locked:" (any spacing), trim, lower-case
        state="$(printf '%s\n' "$out" \
          | ${awk} -F: '/^[[:space:]]*Locked[[:space:]]*/{
                v=$2; gsub(/^[ \t]+|[ \t]+$/, "", v);
                print tolower(v); exit
            }')"
        case "$state" in
          yes|no) printf '%s\n' "$state" ;;
          *)      printf '%s\n' "unknown"; echo "$out" >&2 ;;
        esac
      }

      # Iterate both placeholders (namespaces)
      for dev in ${nvme0} ${nvme1}; do
        if [ ! -e "$dev" ]; then
          echo "[nvme-hw-key] ERROR: device $dev not present in initrd" >&2
          fail_banner
          exit 1
        fi
      
        serial="$(get_serial "$dev")" || serial=""
        if [ -z "$serial" ] || [ "$serial" = "???" ]; then
          echo "[nvme-hw-key] ERROR: could not read controller serial for $dev" >&2
          fail_banner
          exit 1
        fi
      
        keyfile="${mountPoint}/keys/nvme-''${serial}.key"
        if [ ! -r "$keyfile" ]; then
          echo "[nvme-hw-key] ERROR: missing key file: $keyfile" >&2
          fail_banner
          exit 1
        fi
      
        # Read ASCII key, trim trailing newline
        PW="$(${pkgs.coreutils}/bin/tr -d '\r\n' < "$keyfile")"
        if [ -z "$PW" ]; then
          echo "[nvme-hw-key] ERROR: empty key in $keyfile" >&2
          fail_banner
          exit 1
        fi
        ${chmodBin} 0400 "$keyfile" || true
      
        # Show pre-state (ignore failures)
        "$nvme_bin" sed discover "$dev" || true

# [nixos@nixos:~/nixos/hosts/whitey]$ sudo nvme sed discover /dev/nvme0n1
# Locking Features:
#   Locking Supported:         Yes
#   Locking Feature Enabled:   Yes
#   Locked:                    No

# [nixos@nixos:~/nixos/hosts/whitey]$ sudo nvme sed discover /dev/nvme1n1
# Locking Features:
#   Locking Supported:         Yes
#   Locking Feature Enabled:   Yes
#   Locked:                    Yes

        # Check lock state first (robust)
        locked="$(locked_state "$dev")"
        if [ "$locked" = "no" ]; then
          echo "[nvme-hw-key] $dev already unlocked, skipping"
          continue
        fi
        if [ "$locked" = "unknown" ]; then
          echo "[nvme-hw-key] WARN: could not parse lock state for $dev; attempting unlock anyway"
        fi

        # Use sed-key directly; password piped on stdin
        if ! echo -n "$PW" | ${sedKeyBin} unlock "$dev" -; then
          rc=$?
          echo "[nvme-hw-key] ERROR: unlock failed for $dev (rc=$rc)" >&2
          fail_banner
          exit $rc
        fi

        # Verify Locked: No (robust)
        locked="$(locked_state "$dev")"
        if [ "$locked" != "no" ]; then
          echo "[nvme-hw-key] DEBUG: post-unlock Locked='$locked' for $dev" >&2
          echo "[nvme-hw-key] ERROR: $dev still locked after unlock" >&2
          fail_banner
          exit 1
        fi
        echo "[nvme-hw-key] OK: $dev unlocked"
      done

      # Optional: log current state (post-unlock)
      "$nvme_bin" sed discover ${nvme0} || true
      "$nvme_bin" sed discover ${nvme1} || true
      unset pass PW || true

      # Let udev/LVM notice the now-unlocked namespaces before root discovery
      ${pkgs.systemd}/bin/udevadm settle || true

      # Quick verification that both are unlocked
      for dev in ${nvme0} ${nvme1}; do
        locked="$(locked_state "$dev")"
        if [ "$locked" != "no" ]; then
          echo "[nvme-hw-key] DEBUG: final Locked='$locked' for $dev" >&2
          echo "[nvme-hw-key] ERROR: $dev still locked" >&2
          fail_banner
          exit 1
        fi
      done

      echo "[nvme-hw-key] Verifying ${mountPoint} is tmpfs, then shredding keys"
      fsType=$(${statBin} -f -c %T ${mountPoint})
      if [ "$fsType" != "tmpfs" ]; then
        echo "ERROR: ${mountPoint} is $fsType, expected tmpfs" >&2
        fail_banner
        exit 1
      fi

      # Shred key materials (harmless on tmpfs, but consistent)
      ${findBin} ${mountPoint}/keys -type f -name 'nvme-*.key' -exec ${shred} -u {} +
      ${umount} ${mountPoint} || true
      rmdir ${mountPoint} 2>/dev/null || true

      # Now assemble RAID and activate LVM
      ${mdadmBin} --assemble --scan || true
      ${lvmBin} vgchange -ay || true

      ${pkgs.systemd}/bin/udevadm settle || true
    '';
  };

  # ────────────────────────────────────────────────────────────────
  # When nvme-hw-key fails or times out, save what udev and the kernel
  # were doing to /boot (on the Keypad200, writable before the NVMe drives
  # unlock), so an intermittent cold-boot hang leaves evidence behind.
  # It only reads state, and never looks at the keys staged in ${mountPoint}.
  # ────────────────────────────────────────────────────────────────
  boot.initrd.systemd.services.nvme-hw-key-diag =
    let
      sd       = config.boot.initrd.systemd.package;   # the initrd's own journalctl/udevadm/systemctl
      cu       = "${pkgs.coreutils}/bin";
      bootDev  = (config.fileSystems."/boot" or { device = ""; }).device;
      diagRoot = "/run/nvme-hw-key-diag";
    in {
      description = "Save diagnostics after nvme-hw-key fails (stage-1)";
      unitConfig.DefaultDependencies = false;
      # Run before the emergency shell takes the console.
      before = [ "emergency.service" ];

      serviceConfig = {
        Type = "oneshot";
        TimeoutStartSec = "90";
        StandardOutput = "journal+console";
        StandardError  = "journal+console";
      };

      script = ''
        set -u
        echo "[nvme-hw-key-diag] nvme-hw-key failed; saving diagnostics to /boot"
        ${cu}/mkdir -p ${diagRoot}
        if ! ${pkgs.util-linux}/bin/mountpoint -q ${diagRoot}; then
          ${pkgs.util-linux}/bin/mount -t ext4 "${bootDev}" ${diagRoot} || {
            echo "[nvme-hw-key-diag] could not mount ${bootDev}; nothing saved"; exit 0; }
        fi
        D="${diagRoot}/hang-$(${cu}/date +%Y%m%d-%H%M%S)"
        ${cu}/mkdir -p "$D"

        ${cu}/cat /proc/uptime /proc/loadavg > "$D/uptime.txt" 2>&1
        ${sd}/bin/journalctl -b -o short-monotonic --no-pager > "$D/journal.txt" 2>&1
        ${sd}/bin/systemctl list-jobs --no-pager > "$D/jobs.txt" 2>&1
        ${sd}/bin/systemctl status systemd-udevd nvme-hw-key --no-pager -l > "$D/status.txt" 2>&1

        # Is the event queue moving? Two snapshots, five seconds apart.
        count_io_errors() {
          ${sd}/bin/journalctl -b -k --no-pager 2>/dev/null \
            | ${pkgs.gawk}/bin/awk 'tolower($0) ~ /i\/o error|buffer i\/o/ { n++ } END { print n + 0 }'
        }
        for n in 1 2; do
          { echo "== snapshot $n at $(${cu}/cat /proc/uptime)"
            echo "queue file: $(${cu}/ls /run/udev/queue 2>&1)"
            ${sd}/bin/udevadm control --ping 2>&1; echo "ping rc=$?"
            echo "I/O error lines so far: $(count_io_errors)"
          } >> "$D/progress.txt"
          [ "$n" = 1 ] && ${cu}/sleep 5
        done

        # Ten seconds of block-device events, as the kernel sends them and as udev finishes them.
        ${cu}/timeout 10 ${sd}/bin/udevadm monitor --kernel --udev --property --subsystem-match=block \
          > "$D/monitor.txt" 2>&1

        # Every process with its state and wait channel; kernel stacks of the udev and disk tools.
        for p in /proc/[0-9]*; do
          printf '%s %s %s %s\n' "''${p#/proc/}" \
            "$(${pkgs.gawk}/bin/awk '{print $3}' "$p/stat" 2>/dev/null)" \
            "$(${cu}/cat "$p/wchan" 2>/dev/null)" \
            "$(${cu}/tr '\0' ' ' < "$p/cmdline" 2>/dev/null | ${cu}/cut -c1-200)"
        done > "$D/ps.txt"
        for p in /proc/[0-9]*; do
          c="$(${cu}/tr '\0' ' ' < "$p/cmdline" 2>/dev/null)"
          case "$c" in
            *udev*|*blkid*|*mdadm*|*lvm*|*nvme*|*sed-key*)
              echo "== ''${p#/proc/} $c"; ${cu}/cat "$p/stack" 2>/dev/null ;;
          esac
        done > "$D/stacks.txt"

        # udevd's cgroups, including systemd 262's sibling 'workers' cgroup.
        ${pkgs.findutils}/bin/find /sys/fs/cgroup -path '*udev*' \( -name cgroup.procs -o -name cgroup.events \) 2>/dev/null \
          | while read -r f; do echo "== $f"; ${cu}/cat "$f"; done > "$D/cgroups.txt"

        # What udev knows about the NVMe drives, and their raw uevents.
        for d in /sys/block/nvme*; do
          n="''${d##*/}"
          { echo "== $d/uevent"; ${cu}/cat "$d/uevent"
            echo "== udevadm info"; ${sd}/bin/udevadm info "/dev/$n"
          } > "$D/info-$n.txt" 2>&1
        done

        ${cu}/sync
        echo "[nvme-hw-key-diag] saved to /boot/''${D##*/}"
        ${pkgs.util-linux}/bin/umount ${diagRoot} || true
      '';
    };
}
