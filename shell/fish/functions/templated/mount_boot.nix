{ hostname, ... }:

''
##
# mount_boot ────────────────────────────────────────────────────────────
# Convenience wrapper for interactive / script use.
# Host-aware: some hosts (e.g. whitey) have a plain /boot with no LUKS
# container; others (e.g. precisionws) encrypt /boot and need it opened
# first. Detected automatically via boot.initrd.luks.devices."boot_crypt".
##
function mount_boot --description \
        'Mount /boot and ESP; understands cached boot.json and per-host encryption'
    pushd /etc/nixos >/dev/null

    # ── 1. discover devices ────────────────────────────────────────────
    set cache_file /etc/nixos/cache/boot.json

    if test -f $cache_file
        set boot_device (jq -r '.boot_device' $cache_file)
        set efi_device  (jq -r '.efi_device'  $cache_file)
    else
        set boot_device (nix eval --raw \
            ".#nixosConfigurations.${hostname}.config.my.boot.device" 2>/dev/null)
        set efi_device  (nix eval --raw \
            ".#nixosConfigurations.${hostname}.config.my.boot.efiDevice" 2>/dev/null)
    end

    set boot_device (readlink -f "$boot_device")
    set efi_device  (readlink -f "$efi_device")

    # Encrypted container path, if this host uses one (empty if not)
    set luks_dev (nix eval --raw \
        ".#nixosConfigurations.${hostname}.config.boot.initrd.luks.devices.\"boot_crypt\".device" 2>/dev/null)

    if test -n "$luks_dev"
        set luks_dev (readlink -f "$luks_dev")
    end

    # ── 2. open LUKS if this host uses it ─────────────────────────────
    if test -n "$luks_dev"
        if not test -e /dev/mapper/boot_crypt
            echo "🔐  Opening LUKS container for /boot..."
            sudo cryptsetup luksOpen "$luks_dev" boot_crypt; or return 1
        end
        set boot_mount_source /dev/mapper/boot_crypt
    else
        set boot_mount_source $boot_device
    end

    # ── 3. mount /boot  ───────────────────────────────────────────────
    if not mountpoint -q /boot
        echo "📂  Mounting /boot..."
        sudo mount "$boot_mount_source" /boot; or return 1
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
