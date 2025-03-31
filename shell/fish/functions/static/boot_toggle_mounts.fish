function boot_toggle_mounts --description="Toggle mounting of encrypted boot volumes"
    if boot_is_mounted "quiet"
        # If boot is mounted, unmount it
        unmount_boot
        # Check if unmount was successful
        if not boot_is_mounted "quiet"
            echo "Boot volumes have been unmounted successfully."
            return 0
        else
            echo "Failed to unmount boot volumes."
            return 1
        end
    else
        # If boot is not mounted, mount it
        mount_boot
        # Check if mount was successful
        if boot_is_mounted "quiet"
            echo "Boot volumes have been mounted successfully."
            return 0
        else
            echo "Failed to mount boot volumes."
            return 1
        end
    end
end
