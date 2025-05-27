{ hostname, ... }:

''
##
# mount_boot ────────────────────────────────────────────────────────────
# Convenience wrapper for interactive / script use.
#
# • Works when the secrets-USB is *still locked* thanks to the tiny
#   cache written at activation time:  /etc/nixos/cache/boot.json
#   ─────────────────────────────────────────────────────────────────
#     {
#       "boot_device": "/dev/disk/by-uuid/…",   # ext4 inside LUKS
#       "efi_device":  "/dev/disk/by-uuid/…"    # FAT ESP
#     }
# • Falls back to `nix eval` if the cache is missing (e.g. first
#   generation after rebuild, rescue shell, etc.).
# • Opens the LUKS container if necessary, mounts /boot and /boot/EFI.
##
function mount_boot --description \
        'Mount encrypted /boot and ESP; understands cached boot.json'
    pushd /etc/nixos >/dev/null

    # ── 1. discover devices ────────────────────────────────────────────
    set cache_file /etc/nixos/cache/boot.json

    if test -f $cache_file
        set boot_device (jq -r '.boot_device' $cache_file)
        set efi_device  (jq -r '.efi_device'  $cache_file)
    else
        # Fallback to eval-time lookup (slower, but always works)
        set boot_device (nix eval --raw \
            ".#nixosConfigurations.${hostname}.config.my.boot.device" 2>/dev/null)
        set efi_device  (nix eval --raw \
            ".#nixosConfigurations.${hostname}.config.my.boot.efiDevice" 2>/dev/null)
    end

    # UUID /dev-by-id entries may be symlinks – dereference them
    set boot_device (readlink -f "$boot_device")
    set efi_device  (readlink -f "$efi_device")

    # Encrypted container path (still lives in Nix config, never secret)
    set luks_dev (nix eval --raw \
        ".#nixosConfigurations.${hostname}.config.boot.initrd.luks.devices.\"boot_crypt\".device" 2>/dev/null)
    set luks_dev (readlink -f "$luks_dev")

    if test -z "$luks_dev"
        echo "❌  Cannot find boot_crypt device path."
        popd >/dev/null
        return 1
    end

    # ── 2. open LUKS if needed ────────────────────────────────────────
    if not test -e /dev/mapper/boot_crypt
        echo "🔐  Opening LUKS container for /boot..."
        sudo cryptsetup luksOpen "$luks_dev" boot_crypt; or return 1
    end

    # ── 3. mount /boot  ───────────────────────────────────────────────
    if not mountpoint -q /boot
        echo "📂  Mounting /boot..."
        sudo mount /dev/mapper/boot_crypt /boot; or return 1
    else
        echo "ℹ️   /boot already mounted."
    end

    # ── 4. mount ESP  ────────────────────────────────────────────────
    if not mountpoint -q /boot/EFI
        echo "📂  Mounting /boot/EFI..."
        sudo mount "$efi_device" /boot/EFI; or return 1
    else
        echo "ℹ️   /boot/EFI already mounted."
    end

    echo "✅  Boot partitions mounted."
    popd >/dev/null
end
''
