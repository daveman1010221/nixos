{ hostname, ... }:

''
##
# nixos_update ───────────────────────────────────────────────────────────
# Update NixOS configuration with automatic boot mount handling.
# Host-aware: rebuilds against the flake output matching this machine.
##
function nixos_update --description 'Update NixOS configuration with automatic boot mount handling'
    boot_is_mounted "quiet"
    set -l boot_was_mounted $status
    if test $boot_was_mounted -ne 0
        echo "Boot volumes are not fully mounted. Mounting them now..."
        boot_toggle_mounts
        if test $status -ne 0
            echo "Failed to mount boot volumes. Aborting update."
            return 1
        end
    else
        echo "Boot volumes are already mounted."
    end

    echo "Running nixos-rebuild switch, please wait..."
    pushd /etc/nixos
    sudo nixos-rebuild switch \
        --flake .#${hostname} \
        --no-write-lock-file \
        --override-input secrets-empty path:/boot/secrets/flakey.json \
        --option extra-sandbox-paths /boot/secrets \
        --option allowed-impure-host-deps /boot/secrets
    set -l rebuild_status $status
    popd

    if test $boot_was_mounted -ne 0
        echo "Unmounting boot volumes (since they were not mounted originally)."
        boot_toggle_mounts
        if test $status -ne 0
            echo "Failed to unmount boot volumes."
        end
    else
        echo "WARNING: Boot volumes remain mounted."
    end

    return $rebuild_status
end
''
