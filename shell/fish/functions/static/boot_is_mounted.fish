function boot_is_mounted --description "Checks if /boot and /boot/EFI are both mounted. If run with 'quiet' argument, simply returns a code."
    set quiet $argv[1]

    # Check if /boot is a mount point
    mountpoint -q /boot
    set boot_mounted $status

    # Check if /boot/EFI is a mount point
    mountpoint -q /boot/EFI
    set efi_mounted $status

    if test $boot_mounted -eq 0 -a $efi_mounted -eq 0
        if not test "$quiet" = "quiet"
            echo "/boot and /boot/EFI are mounted."
        end
        return 0
    else
        if not test "$quiet" = "quiet"
            echo "Boot volumes are not fully mounted."
        end
        return 1
    end
end
