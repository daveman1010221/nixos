#!/run/current-system/sw/bin/bash

set -e

# This script sets up an encrypted raid0 over two devices, configures lvm, and
# stores keys and headers on an encrypted boot device.

# Variables for device identifiers and mount points
BOOT="/dev/sda"
BLOCK_01="nvme0n1"
BLOCK_02="nvme1n1"
DEV_BLOCKS=("${BLOCK_01}" "${BLOCK_02}")
BOOT_MOUNT="/mnt/boot"
EFI_PARTITION="${BOOT}1"
BOOT_PARTITION="${BOOT}2"
KEYS_DIR="${BOOT_MOUNT}/keys"

# Step 1: Partition the removable device
echo "Partitioning ${BOOT}..."

dd if=/dev/zero of=${BOOT} bs=1M count=4096

parted -s ${BOOT} mklabel gpt || { echo "Error: " >&2; exit 1; }
parted -s ${BOOT} mkpart ESP fat32 1MiB 551MiB || { echo "Error: " >&2; exit 1; }
parted -s ${BOOT} set 1 esp on || { echo "Error: " >&2; exit 1; }
parted -s ${BOOT} mkpart BOOT ext4 551MiB 2599MiB || { echo "Error: " >&2; exit 1; }

# Step 2: Format the EFI System Partition
echo "Formatting the EFI System Partition..."
mkfs.vfat -v -F 32 ${EFI_PARTITION} || { echo "Error: " >&2; exit 1; }

# Step 3: Encrypt the /boot partition using LUKS1 for compatibility with GRUB
echo "Encrypting ${BOOT_PARTITION} for /boot with LUKS1..."
cryptsetup luksFormat \
    --type luks1 ${BOOT_PARTITION} \
    --hash sha256 \
    --key-size 512 \
    --cipher aes-xts-plain64 \
    --pbkdf pbkdf2 || { echo "Error: " >&2; exit 1; }

cryptsetup luksOpen ${BOOT_PARTITION} boot_crypt || { echo "Error: " >&2; exit 1; }

# Step 4: Format the encrypted /boot partition as EXT4
echo "Formatting the encrypted /boot partition..."
mkfs.ext4 /dev/mapper/boot_crypt || { echo "Error: " >&2; exit 1; }

# Step 5: Mount the encrypted /boot partition
echo "Mounting the encrypted /boot partition..."
mkdir -p ${BOOT_MOUNT} || { echo "Error: " >&2; exit 1; }
mount /dev/mapper/boot_crypt ${BOOT_MOUNT} || { echo "Error: " >&2; exit 1; }

# Step 6: Create and mount the EFI partition under /boot/EFI
echo "Mounting the EFI partition..."
mkdir -p ${BOOT_MOUNT}/EFI || { echo "Error: " >&2; exit 1; }
mount ${EFI_PARTITION} ${BOOT_MOUNT}/EFI || { echo "Error: " >&2; exit 1; }

udevadm settle

# Prepare keys directory
echo "Creating keys directory..."
mkdir -p ${KEYS_DIR} || { echo "Error: " >&2; exit 1; }

# Prepare detached headers for NVMe devices using fallocate
echo "Creating LUKS header files..."
fallocate -l 4MiB ${KEYS_DIR}/${BLOCK_01}.header || { echo "Error: " >&2; exit 1; }
fallocate -l 4MiB ${KEYS_DIR}/${BLOCK_02}.header || { echo "Error: " >&2; exit 1; }

# Generate cryptographically secure keyfiles for NVMe devices

echo "Installing temporary openssl..."
nix-env -iA nixos.openssl

echo "Generating key files..."
openssl rand -out ${KEYS_DIR}/${BLOCK_01}.key 32 || { echo "Error: " >&2; exit 1; }
openssl rand -out ${KEYS_DIR}/${BLOCK_02}.key 32 || { echo "Error: " >&2; exit 1; }

chmod -R 400 ${KEYS_DIR}

# Encrypt NVMe volumes with created keyfiles, using LUKS2, detached keys and
# headers, and FIPS-compliant algorithm parameters
echo "Encrypting NVMe volumes with LUKS2 and opening them..."

# Find RAID arrays
shopt -s nullglob

arrays=$(/dev/md*)

# Iterate over each RAID array
for array in $arrays; do
    # Check if the RAID array exists
    if [ -e "$array" ]; then
        # Stop the RAID array
        mdadm --stop "$array"
    fi
done

for device in "${DEV_BLOCKS[@]}"; do
    # 1. Wipe them.
    dd if=/dev/zero of=/dev/${device} bs=1M count=512

    # 2. Format them for encryption.
    cryptsetup luksFormat \
        --type luks2 /dev/${device} \
        --key-file ${KEYS_DIR}/${device}.key \
        --header ${KEYS_DIR}/${device}.header \
        --cipher aes-xts-plain64 \
        --key-size 256 \
        --hash sha256 || { echo "Error: " >&2; exit 1; }

    # 3. Open the encrypted volume
    cryptsetup luksOpen \
        --key-file ${KEYS_DIR}/${device}.key \
        --header ${KEYS_DIR}/${device}.header \
        /dev/${device} ${device}_crypt || { echo "Error: " >&2; exit 1; }
done

# Create RAID 0 array
echo "Creating Raid0 multi-device..."
mdadm \
    --create \
    --verbose /dev/md0 \
    --level=0 \
    --raid-devices=2 \
    /dev/mapper/${BLOCK_01}_crypt /dev/mapper/${BLOCK_02}_crypt || { echo "Error: " >&2; exit 1; }

# Create LVM Physical Volume, Volume Group, and Logical Volume
echo "Creating LVM PV..."
pvcreate /dev/md0 || { echo "Error: " >&2; exit 1; }

echo "Creating LVM VG..."
vgcreate -s 16M nix /dev/md0 || { echo "Error: " >&2; exit 1; }

echo "Creating LVM LVs..."
lvcreate -L 96G  -n swap nix -C y || { echo "Error: " >&2; exit 1; }
lvcreate -L 20G  -n tmp  nix -C y || { echo "Error: " >&2; exit 1; }
lvcreate -L 120G -n var  nix -C y || { echo "Error: " >&2; exit 1; }
lvcreate -L 200G -n root nix -C y || { echo "Error: " >&2; exit 1; }
lvcreate -L 200G -n home nix -C y || { echo "Error: " >&2; exit 1; }

# Format the LV with EXT4 without a journal and with RAID alignment
echo "Formatting LVs..."
mkfs.ext4 -O ^has_journal -E stride=128,stripe-width=256 /dev/nix/tmp  || { echo "Error: " >&2; exit 1; }
mkfs.ext4 -O ^has_journal -E stride=128,stripe-width=256 /dev/nix/var  || { echo "Error: " >&2; exit 1; }
mkfs.ext4 -O ^has_journal -E stride=128,stripe-width=256 /dev/nix/root || { echo "Error: " >&2; exit 1; }
mkfs.ext4 -O ^has_journal -E stride=128,stripe-width=256 /dev/nix/home || { echo "Error: " >&2; exit 1; }

# Mount the LV
echo "Mounting LVs..."

# We needed to mount the boot and efi partitions earlier. Now, we need to
# unmount them and re-mount them to our temporary root.
# 0.
umount ${BOOT_MOUNT}/EFI
umount ${BOOT_MOUNT}

# 1. root
mount /dev/nix/root /mnt || { echo "Error: " >&2; exit 1; }

# 2. tmp
mkdir -p /mnt/tmp || { echo "Error: " >&2; exit 1; }
mount /dev/nix/tmp /mnt/tmp || { echo "Error: " >&2; exit 1; }

# 3. var
mkdir -p /mnt/var || { echo "Error: " >&2; exit 1; }
mount /dev/nix/var /mnt/var || { echo "Error: " >&2; exit 1; }

# 4. home
mkdir -p /mnt/home || { echo "Error: " >&2; exit 1; }
mount /dev/nix/home /mnt/home || { echo "Error: " >&2; exit 1; }

# Remount boot and EFI
# 5. boot
mkdir -p ${BOOT_MOUNT} || { echo "Error: " >&2; exit 1; }
mount /dev/mapper/boot_crypt ${BOOT_MOUNT} || { echo "Error: " >&2; exit 1; }

# 6. EFI
mkdir -p ${BOOT_MOUNT}/EFI || { echo "Error: " >&2; exit 1; }
mount ${EFI_PARTITION} ${BOOT_MOUNT}/EFI || { echo "Error: " >&2; exit 1; }

# 7. Swap
echo "Configuring swap..."
mkswap /dev/nix/swap
swapon /dev/nix/swap

echo "Generating initial configuration..."
nixos-generate-config --root /mnt || { echo "Error: " >&2; exit 1; }

echo "Replacing initial config with the real one..."
cp ./configuration.nix /mnt/etc/nixos/configuration.nix

echo "Setup complete. Remember to unmount and close the encrypted /boot partition when finished."
