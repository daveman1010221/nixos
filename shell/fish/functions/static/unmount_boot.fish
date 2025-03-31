function unmount_boot
    # Unmount /boot/EFI
    if mountpoint -q /boot/EFI
        echo "Unmounting /boot/EFI..."
        sudo umount /boot/EFI
    else
        echo "/boot/EFI is not mounted."
    end

    # Unmount /boot
    if mountpoint -q /boot
        echo "Unmounting /boot..."
        sudo umount /boot
    else
        echo "/boot is not mounted."
    end

    # Close the encrypted boot partition
    if test -e /dev/mapper/boot_crypt
        echo "Closing encrypted boot partition..."
        sudo cryptsetup luksClose boot_crypt
    else
        echo "Encrypted boot partition is already closed."
    end
end
