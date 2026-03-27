function nixos_update --description 'Update NixOS configuration with automatic boot mount handling'
    # Check if boot is mounted
    boot_is_mounted "quiet"
    set -l boot_was_mounted $status
    # If boot was not mounted originally, mount it now
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
    # Run nixos-rebuild switch
    echo "Running nixos-rebuild switch, please wait..."
    pushd /etc/nixos
    begin
        sudo nixos-rebuild switch \
            --flake .#precisionws \
            --no-write-lock-file \
            --override-input secrets-empty path:/boot/secrets/flakey.json \
            --option extra-sandbox-paths /boot/secrets \
            --option allowed-impure-host-deps /boot/secrets
    end 2>&1 | grep -Ev 'not writing modified lock file|Updated input .secrets-empty|^\s+'\''path:\./secrets-empty|^\s+[→]\s+'\''path:/boot/secrets/flakey'
    popd
    set rebuild_status $status
    # After the rebuild, unmount only if we mounted them in this function
    if test $boot_was_mounted -ne 0
        echo "Unmounting boot volumes (since they were not mounted originally)."
        boot_toggle_mounts
        if test $status -ne 0
            echo "Failed to unmount boot volumes."
        end
    else
        echo "WARNING: Boot volumes remain mounted."
    end
    # Return nixos-rebuild's status
    return $rebuild_status
end
