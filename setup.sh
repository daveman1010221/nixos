#!/run/current-system/sw/bin/bash

set -euo pipefail  # Safer script execution

### FUNCTIONS
function confirm() {
    echo -e "\n\033[1;33m[WARNING]\033[0m $1"
    read -p "Type 'yes' to proceed: " response
    if [[ "$response" != "yes" ]]; then
        echo "Aborting."
        exit 1
    fi
}

function check_command() {
    if ! command -v "$1" &>/dev/null; then
        echo -e "\033[1;31m[ERROR]\033[0m Required command '$1' not found. Install it before proceeding."
        exit 1
    fi
}

function check_value() {
    local value="$1"
    local name="$2"

    if ! grep -qF "$value" "$HWC_PATH"; then
        echo -e "\033[1;31m[ERROR]\033[0m Expected $name ($value) not found in $HWC_PATH!"
        MISSING_VALUES=$((MISSING_VALUES + 1))
    else
        echo -e "\033[1;32m[OK]\033[0m Found $name ($value) in hardware-configuration.nix."
    fi
}

### CONFIGURATION

### IDENTIFY TARGET DRIVE ###
echo -e "\033[1;34m[INFO]\033[0m Detecting available disks..."
lsblk -o NAME,MODEL,SIZE,TYPE,MOUNTPOINT

DEFAULT_BOOT=$(lsblk -dno NAME,SIZE | grep -v "nvme" | grep -v "loop" | sort -h -k2 | head -n 1 | awk '{print "/dev/" $1}')
if [[ -z "$DEFAULT_BOOT" ]]; then
    echo -e "\033[1;31m[ERROR]\033[0m Could not detect a valid boot drive!"
    exit 1
fi

echo -e "\n\033[1;33m[WARNING]\033[0m The target boot drive is set to: \033[1;36m${DEFAULT_BOOT}\033[0m"
echo "Detected details:"
fdisk -l ${DEFAULT_BOOT} 2>/dev/null | grep "Disk ${DEFAULT_BOOT}"

confirm "Is this the correct drive? This will ERASE and REINSTALL your system! Type 'yes' to proceed."

# Ensure the boot drive is not mounted before proceeding
if mount | grep -q "${DEFAULT_BOOT}"; then
    echo -e "\033[1;33m[WARNING]\033[0m ${DEFAULT_BOOT} is currently mounted. It must be unmounted before proceeding."
    confirm "Unmount ${DEFAULT_BOOT} and continue?"
    umount ${DEFAULT_BOOT}* || true
fi

BLOCK_01="nvme0n1"
BLOCK_02="nvme1n1"
DEV_BLOCKS=("${BLOCK_01}" "${BLOCK_02}")
BOOT_MOUNT="/mnt/boot"
EFI_PARTITION="${DEFAULT_BOOT}1"
BOOT_PARTITION="${DEFAULT_BOOT}2"
KEYS_DIR="${BOOT_MOUNT}/keys"
NIXOS_REPO="https://github.com/daveman1010221/nixos.git"

### PRE-FLIGHT CHECKS
echo -e "\033[1;34m[INFO]\033[0m Checking required commands..."
for cmd in parted cryptsetup mdadm pvcreate vgcreate lvcreate mkfs.ext4 mkfs.vfat git; do
    check_command "$cmd"
done

# Ensure OpenSSL is installed
if ! command -v openssl &>/dev/null; then
    echo -e "\033[1;34m[INFO]\033[0m Installing OpenSSL..."
    if ! nix profile install nixpkgs#openssl --extra-experimental-features nix-command --extra-experimental-features flakes; then
        echo -e "\033[1;31m[ERROR]\033[0m Failed to install OpenSSL! Check your Nix setup."
        exit 1
    fi
fi

### CLEANUP ANY PARTIAL STATE ###
echo -e "\033[1;34m[INFO]\033[0m Ensuring all partitions, RAID, and LUKS devices are released..."

# Unmount everything first
echo -e "\033[1;34m[INFO]\033[0m Unmounting all filesystems..."
mount | grep "/mnt" && umount -R /mnt || true
mount | grep "${DEFAULT_BOOT}" && umount ${DEFAULT_BOOT}* || true

# Close any open LUKS devices
echo -e "\033[1;34m[INFO]\033[0m Checking for existing LUKS devices..."
cryptsetup status boot_crypt &>/dev/null && cryptsetup luksClose boot_crypt || true

for device in "${DEV_BLOCKS[@]}"; do
    if cryptsetup status ${device}_crypt &>/dev/null; then
        echo -e "\033[1;34m[INFO]\033[0m Closing existing LUKS device: ${device}_crypt"
        umount /dev/mapper/${device}_crypt* || true
        cryptsetup luksClose ${device}_crypt || dmsetup remove ${device}_crypt || true
    fi
done

# Stop any existing RAID arrays
echo -e "\033[1;34m[INFO]\033[0m Stopping RAID arrays..."
for array in $(ls /dev/md* 2>/dev/null || true); do
    mdadm --stop "$array" || true
    mdadm --remove "$array" || true
done

# Deactivate any active LVM volume groups
echo -e "\033[1;34m[INFO]\033[0m Deactivating LVM volumes..."
vgs nix &>/dev/null && vgchange -an nix || true

# Ensure partitions are released
echo -e "\033[1;34m[INFO]\033[0m Wiping partition table on ${DEFAULT_BOOT}..."
for i in {1..3}; do wipefs -a ${DEFAULT_BOOT} || true; done
partprobe ${DEFAULT_BOOT} || echo "Reboot may be required."

### PARTITIONING ###
echo -e "\033[1;34m[INFO]\033[0m Partitioning ${DEFAULT_BOOT}..."
parted -s ${DEFAULT_BOOT} mklabel gpt
parted -s ${DEFAULT_BOOT} mkpart ESP fat32 1MiB 551MiB
parted -s ${DEFAULT_BOOT} set 1 esp on
parted -s ${DEFAULT_BOOT} mkpart BOOT ext4 551MiB 2599MiB

### FORMATTING EFI ###
echo -e "\033[1;34m[INFO]\033[0m Formatting EFI partition..."
mkfs.vfat -v -F 32 ${EFI_PARTITION}

### ENCRYPTING /BOOT ###
echo -e "\033[1;34m[INFO]\033[0m Encrypting /boot (You will be prompted for a passphrase)..."
cryptsetup luksFormat --type luks1 --hash sha256 --key-size 512 --cipher aes-xts-plain64 --pbkdf pbkdf2 ${BOOT_PARTITION}
cryptsetup luksOpen ${BOOT_PARTITION} boot_crypt

### FORMATTING & MOUNTING /BOOT ###
echo -e "\033[1;34m[INFO]\033[0m Formatting and mounting encrypted /boot..."
mkfs.ext4 /dev/mapper/boot_crypt
mkdir -p ${BOOT_MOUNT}
mount /dev/mapper/boot_crypt ${BOOT_MOUNT}
mkdir -p ${BOOT_MOUNT}/EFI
mount ${EFI_PARTITION} ${BOOT_MOUNT}/EFI

### PREPARING KEYS ###
echo -e "\033[1;34m[INFO]\033[0m Generating LUKS headers and keys..."
mkdir -p ${KEYS_DIR}
for device in "${DEV_BLOCKS[@]}"; do
    fallocate -l 4MiB ${KEYS_DIR}/${device}.header
    openssl rand -out ${KEYS_DIR}/${device}.key 32
done
chmod -R 400 ${KEYS_DIR}

### ENCRYPTING NVME DEVICES ###
echo -e "\033[1;34m[INFO]\033[0m Encrypting NVMe devices..."
for device in "${DEV_BLOCKS[@]}"; do
    if cryptsetup isLuks /dev/${device}; then
        echo -e "\033[1;33m[WARNING]\033[0m ${device} is already encrypted!"
        confirm "Do you want to reformat and erase the encryption?"
    fi
    dd if=/dev/zero of=/dev/${device} bs=1M count=512 status=progress
    cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 --key-size 256 --hash sha256 --key-file ${KEYS_DIR}/${device}.key --header ${KEYS_DIR}/${device}.header /dev/${device}
    cryptsetup luksOpen --key-file ${KEYS_DIR}/${device}.key --header ${KEYS_DIR}/${device}.header /dev/${device} ${device}_crypt
done

### CREATING RAID-0 ###
if [ -e /dev/md0 ]; then
    echo -e "\033[1;34m[INFO]\033[0m Stopping existing RAID-0 array..."
    mdadm --stop /dev/md0 || true
    mdadm --remove /dev/md0 || true
    wipefs -a /dev/md0 || true
    mdadm --zero-superblock /dev/mapper/${BLOCK_01}_crypt /dev/mapper/${BLOCK_02}_crypt || true
fi

echo -e "\033[1;34m[INFO]\033[0m Creating RAID-0 array..."
mdadm --create --verbose /dev/md0 --level=0 --raid-devices=2 --chunk=512K /dev/mapper/${BLOCK_01}_crypt /dev/mapper/${BLOCK_02}_crypt

### CREATING LVM ###
echo -e "\033[1;34m[INFO]\033[0m Creating LVM structure..."

# 1️⃣ Create the Physical Volume
pvcreate /dev/md0 || { echo -e "\033[1;31m[ERROR]\033[0m Failed to create Physical Volume!"; exit 1; }

# 2️⃣ Create the Volume Group
vgcreate -s 16M nix /dev/md0 || { echo -e "\033[1;31m[ERROR]\033[0m Failed to create Volume Group!"; exit 1; }

# 3️⃣ Create Logical Volumes
lvcreate -L 96G  -n swap nix -C y || { echo -e "\033[1;31m[ERROR]\033[0m Failed to create swap LV!"; exit 1; }
lvcreate -L 20G  -n tmp  nix -C y || { echo -e "\033[1;31m[ERROR]\033[0m Failed to create tmp LV!"; exit 1; }
lvcreate -L 120G -n var  nix -C y || { echo -e "\033[1;31m[ERROR]\033[0m Failed to create var LV!"; exit 1; }
lvcreate -L 200G -n root nix -C y || { echo -e "\033[1;31m[ERROR]\033[0m Failed to create root LV!"; exit 1; }
lvcreate -L 200G -n home nix -C y || { echo -e "\033[1;31m[ERROR]\033[0m Failed to create home LV!"; exit 1; }

# 4️⃣ Verify LVM setup
echo -e "\033[1;34m[INFO]\033[0m Verifying LVM setup..."
vgdisplay nix
lvdisplay nix

# 5️⃣ Format Logical Volumes with EXT4
echo -e "\033[1;34m[INFO]\033[0m Formatting Logical Volumes with EXT4..."
mkfs.ext4 -O ^has_journal -E stride=128,stripe-width=256 /dev/nix/tmp  || { echo -e "\033[1;31m[ERROR]\033[0m Failed to format tmp LV!"; exit 1; }
mkfs.ext4 -O ^has_journal -E stride=128,stripe-width=256 /dev/nix/var  || { echo -e "\033[1;31m[ERROR]\033[0m Failed to format var LV!"; exit 1; }
mkfs.ext4 -O ^has_journal -E stride=128,stripe-width=256 /dev/nix/root || { echo -e "\033[1;31m[ERROR]\033[0m Failed to format root LV!"; exit 1; }
mkfs.ext4 -O ^has_journal -E stride=128,stripe-width=256 /dev/nix/home || { echo -e "\033[1;31m[ERROR]\033[0m Failed to format home LV!"; exit 1; }

# 6️⃣ Configure Swap
echo -e "\033[1;34m[INFO]\033[0m Configuring Swap..."
mkswap /dev/nix/swap
swapon /dev/nix/swap

# 7️⃣ Mount Logical Volumes
echo -e "\033[1;34m[INFO]\033[0m Mounting Logical Volumes..."
mount /dev/nix/root /mnt || { echo -e "\033[1;31m[ERROR]\033[0m Failed to mount root!"; exit 1; }
mkdir -p /mnt/tmp  && mount /dev/nix/tmp  /mnt/tmp
mkdir -p /mnt/var  && mount /dev/nix/var  /mnt/var
mkdir -p /mnt/home && mount /dev/nix/home /mnt/home

# 8️⃣ Remount Boot and EFI
umount ${BOOT_MOUNT}/EFI || true
umount ${BOOT_MOUNT} || true
mkdir -p ${BOOT_MOUNT} && mount /dev/mapper/boot_crypt ${BOOT_MOUNT}
mkdir -p ${BOOT_MOUNT}/EFI && mount ${EFI_PARTITION} ${BOOT_MOUNT}/EFI

echo -e "\033[1;34m[INFO]\033[0m Verifying that all devices and filesystems are correctly set up..."

# Check if LUKS devices are open
for device in "${DEV_BLOCKS[@]}"; do
    if ! cryptsetup status ${device}_crypt &>/dev/null; then
        echo -e "\033[1;31m[ERROR]\033[0m LUKS device ${device}_crypt is NOT open!"
        exit 1
    else
        echo -e "\033[1;32m[OK]\033[0m LUKS device ${device}_crypt is open."
    fi
done

# Check RAID status
if ! cat /proc/mdstat | grep -q "md0"; then
    echo -e "\033[1;31m[ERROR]\033[0m RAID array /dev/md0 is NOT active!"
    exit 1
else
    echo -e "\033[1;32m[OK]\033[0m RAID array /dev/md0 is active."
fi

# Check if LVM volumes exist
for lv in root var home tmp swap; do
    if [ ! -e "/dev/nix/$lv" ]; then
        echo -e "\033[1;31m[ERROR]\033[0m LVM volume nix/$lv does NOT exist!"
        exit 1
    else
        echo -e "\033[1;32m[OK]\033[0m LVM volume nix/$lv exists."
    fi
done

echo -e "\033[1;34m[INFO]\033[0m Waiting for LVM volumes to settle..."
sleep 3

# Verify all required mounts
REQUIRED_MOUNTS=( "tmp" "var" "home" "boot" "boot/EFI")

for mountpoint in "/mnt/${REQUIRED_MOUNTS[@]}"; do
    if ! mount | grep -q "on ${mountpoint} "; then
        echo -e "\033[1;31m[ERROR]\033[0m ${mountpoint} is NOT mounted!"
        exit 1
    else
        echo -e "\033[1;32m[OK]\033[0m ${mountpoint} is mounted."
    fi
done

echo -e "\033[1;34m[INFO]\033[0m All devices, filesystems, and mounts are correctly set up."

### CLONING NIXOS CONFIG FROM GIT ###
echo -e "\033[1;34m[INFO]\033[0m Generating initial hardware configuration..."
nixos-generate-config --root /mnt  # <-- Creates initial /mnt/etc/* files

echo -e "\033[1;34m[INFO]\033[0m Backing up hardware configuration..."
mv /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/hardware-configuration.nix.bak

### ASK USER FOR HOSTNAME ###
echo -e "\033[1;34m[INFO]\033[0m Please enter the hostname for this system:"
read -p "Hostname: " HOSTNAME

# Ensure it's a valid hostname (no spaces or special characters)
if [[ ! "$HOSTNAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo -e "\033[1;31m[ERROR]\033[0m Invalid hostname. Use only letters, numbers, dots, hyphens, and underscores."
    exit 1
fi

echo -e "\033[1;34m[INFO]\033[0m Cloning NixOS flake configuration..."
rm -rf /mnt/etc/nixos  # Remove any existing repo (to avoid conflicts)
git clone ${NIXOS_REPO} /mnt/etc/nixos

echo -e "\033[1;34m[INFO]\033[0m Updating flake.nix with hostname: $HOSTNAME..."
sed -i "s|nixosConfigurations\.[a-zA-Z0-9._-]*|nixosConfigurations.${HOSTNAME}|" /mnt/etc/nixos/flake.nix

echo -e "\033[1;34m[INFO]\033[0m Restoring hardware configuration..."
mv /mnt/etc/hardware-configuration.nix.bak /mnt/etc/nixos/hardware-configuration.nix

echo -e "\033[1;34m[INFO]\033[0m Extracting hardware-specific details for flake configuration..."

# Get UUIDs for LUKS devices and filesystems
boot_uuid=$(blkid -s UUID -o value /dev/${DEFAULT_BOOT}2)      # Returns a UUID
boot_fs_uuid=$(blkid -s UUID -o value /dev/mapper/boot_crypt)  # Returns a UUID
efi_fs_uuid=$(blkid -s UUID -o value ${EFI_PARTITION})

# Get persistent device paths
nvme0_path=$(ls -l /dev/disk/by-id/ | awk '/nvme-eui.*nvme0n1/ {print "/dev/disk/by-id/" $9}' | head -n1)
nvme1_path=$(ls -l /dev/disk/by-id/ | awk '/nvme-eui.*nvme1n1/ {print "/dev/disk/by-id/" $9}' | head -n1)

# Ensure device paths are set before continuing
if [[ -z "$nvme0_path" || -z "$nvme1_path" ]]; then
    echo -e "\033[1;31m[ERROR]\033[0m Failed to determine NVMe device paths!"
    echo "Check your system's device list manually and update flake.nix as needed."
    exit 1
fi

# Validate extracted values against hardware-configuration.nix
HWC_PATH="/mnt/etc/nixos/hardware-configuration.nix"
echo -e "\033[1;34m[INFO]\033[0m Verifying extracted values exist in hardware-configuration.nix..."

MISSING_VALUES=0

# Check each value
check_value "$boot_uuid" "Boot LUKS UUID"
check_value "$boot_fs_uuid" "Boot Filesystem UUID"
check_value "$efi_fs_uuid" "EFI Filesystem UUID"
check_value "$nvme0_path" "NVMe0 Device Path"
check_value "$nvme1_path" "NVMe1 Device Path"

# If any values are missing, abort before modifying flake.nix
if [[ $MISSING_VALUES -gt 0 ]]; then
    echo -e "\033[1;31m[ERROR]\033[0m Some expected values were not found in hardware-configuration.nix!"
    echo "Please check hardware-configuration.nix and ensure all required values are present."
    exit 1
fi

echo -e "\033[1;34m[INFO]\033[0m Updating flake.nix with detected hardware details..."

# Update flake.nix using explicit placeholders
sed -i "s|PLACEHOLDER_NVME0|${nvme0_path}|g" /mnt/etc/nixos/flake.nix
sed -i "s|PLACEHOLDER_NVME1|${nvme1_path}|g" /mnt/etc/nixos/flake.nix
sed -i "s|PLACEHOLDER_BOOT_UUID|/dev/disk/by-uuid/${boot_uuid}|g" /mnt/etc/nixos/flake.nix
sed -i "s|PLACEHOLDER_BOOT_FS_UUID|/dev/disk/by-uuid/${boot_fs_uuid}|g" /mnt/etc/nixos/flake.nix
sed -i "s|PLACEHOLDER_EFI_FS_UUID|/dev/disk/by-uuid/${efi_fs_uuid}|g" /mnt/etc/nixos/flake.nix

echo -e "\033[1;34m[INFO]\033[0m Flake configuration updated successfully!"

### APPLYING SYSTEM CONFIGURATION ###
if [[ -z "$HOSTNAME" ]]; then
    echo -e "\033[1;31m[ERROR]\033[0m No hostname provided. Aborting installation."
    exit 1
fi

echo -e "\033[1;34m[INFO]\033[0m Installing NixOS from flake..."
nixos-install --flake /mnt/etc/nixos#$HOSTNAME

echo -e "\033[1;32m[SUCCESS]\033[0m Installation complete! Reboot when ready."
