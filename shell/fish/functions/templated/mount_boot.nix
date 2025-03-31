{ hostname, ... }:

''
function mount_boot --description 'Mount the encrypted /boot and /boot/EFI partitions using Nix expressions'
    pushd /etc/nixos
    # Extract encrypted device path using Nix expressions
    set encrypted_device (nix eval --raw '.#nixosConfigurations.${hostname}.config.boot.initrd.luks.devices."boot_crypt".device')
    if test -z "$encrypted_device"
        echo "Could not retrieve encrypted device path from NixOS configuration."
        return 1
    end

    # Resolve physical device if the device path is a symlink
    set encrypted_device_physical (readlink -f "$encrypted_device")
    if test -z "$encrypted_device_physical"
        echo "Could not resolve physical encrypted device path."
        return 1
    end

    # Check if boot_crypt is already open
    if test -e /dev/mapper/boot_crypt
        echo "Encrypted boot device is already open. Skipping luksOpen..."
    else
        echo "Opening encrypted boot partition..."
        sudo cryptsetup luksOpen "$encrypted_device_physical" boot_crypt
        if test $status -ne 0
            echo "Failed to open encrypted boot partition."
            return 1
        end
    end

    # Mount /boot if not already mounted
    if mountpoint -q /boot
        echo "/boot is already mounted. Skipping mount..."
    else
        echo "Mounting /boot..."
        sudo mount /dev/mapper/boot_crypt /boot
        if test $status -ne 0
            echo "Failed to mount /boot."
            return 1
        end
    end

    # Extract device path for /boot/EFI using Nix expressions
    set efi_device (nix eval --raw '.#nixosConfigurations.${hostname}.config.fileSystems."/boot/EFI".device')
    if test -z "$efi_device"
        echo "Could not retrieve /boot/EFI device path from NixOS configuration."
        return 1
    end

    # Resolve physical device if the device path is a symlink
    set efi_device_physical (readlink -f "$efi_device")
    if test -z "$efi_device_physical"
        echo "Could not resolve physical /boot/EFI device path."
        return 1
    end

    # Mount /boot/EFI if not already mounted
    if mountpoint -q /boot/EFI
        echo "/boot/EFI is already mounted. Skipping mount..."
    else
        echo "Mounting /boot/EFI..."
        sudo mount "$efi_device_physical" /boot/EFI
        if test $status -ne 0
            echo "Failed to mount /boot/EFI."
            return 1
        end
    end

    echo "Boot partitions have been mounted successfully."
    popd
end
''
