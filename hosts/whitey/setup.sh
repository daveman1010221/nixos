#!/run/current-system/sw/bin/bash

set -euo pipefail  # Safer script execution

### FUNCTIONS
function confirm() {
    echo -e "\n\033[1;33m[WARNING]\033[0m $1"
    read -p "Type 'YES' to proceed: " response
    if [[ "$response" != "YES" ]]; then
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

### IDENTIFY TARGET DRIVE ###
echo -e "\033[1;34m[INFO]\033[0m Detecting available disks..."
lsblk -o NAME,MODEL,SIZE,TYPE,MOUNTPOINT

# Filter out nvme, and loop devices to avoid picking them accidentally
DEFAULT_BOOT=$(
  lsblk -dno NAME,SIZE \
  | grep -vE 'nvme|loop' \
  | sort -h -k2 \
  | head -n 1 \
  | awk '{print "/dev/" $1}'
)

if [[ -z "$DEFAULT_BOOT" ]]; then
    echo -e "\033[1;31m[ERROR]\033[0m Could not detect a valid boot drive!"
    exit 1
fi

echo -e "\n\033[1;33m[WARNING]\033[0m The target boot drive is set to: \033[1;36m${DEFAULT_BOOT}\033[0m"
echo "Detected details:"
sudo fdisk -l "${DEFAULT_BOOT}" 2>/dev/null | grep "Disk ${DEFAULT_BOOT}"

confirm "Is this the correct drive? This will ERASE and REINSTALL your system! Type 'YES' to proceed."

BLOCK_01="nvme0n1"
BLOCK_02="nvme1n1"
DEV_BLOCKS=("${BLOCK_01}" "${BLOCK_02}")
BOOT_MOUNT="/mnt/boot"
SECRETS_MOUNT="/mnt/secrets"
EFI_PARTITION="${DEFAULT_BOOT}1"
BOOT_PARTITION="${DEFAULT_BOOT}2"
SECRETS_PARTITION="${DEFAULT_BOOT}3"
DATA_PARTITION="${DEFAULT_BOOT}4"

# keys will live on the encrypted /secrets partition
KEYS_DIR="${SECRETS_MOUNT}/keys"

NIXOS_REPO="https://github.com/daveman1010221/nixos.git"

# Ensure OpenSSL is installed
if ! command -v openssl &>/dev/null; then
    echo -e "\033[1;34m[INFO]\033[0m Installing OpenSSL..."
    if ! nix profile install nixpkgs#openssl --extra-experimental-features nix-command --extra-experimental-features flakes; then
        echo -e "\033[1;31m[ERROR]\033[0m Failed to install OpenSSL! Check your Nix setup."
        exit 1
    fi
fi

### PRE-FLIGHT CHECKS
echo -e "\033[1;34m[INFO]\033[0m Checking required commands..."
for cmd in openssl parted mdadm pvcreate vgcreate lvcreate mkfs.ext4 mkfs.f2fs mkfs.vfat git; do
    check_command "$cmd"
done

### CLEANUP ANY PARTIAL STATE ###
echo -e "\033[1;34m[INFO]\033[0m Ensuring all partitions and RAID devices are released..."

# 1) Turn off all swap, if any
echo -e "\033[1;34m[INFO]\033[0m Turning off swap (if active)..."
sudo swapoff -a || true

# 2) Unmount everything under /mnt (including nested mounts like /mnt/boot, /mnt/boot/EFI, etc.)
echo -e "\033[1;34m[INFO]\033[0m Unmounting all filesystems from /mnt..."
if mount | grep -q "/mnt/"; then
    sudo umount -R /mnt || {
        echo -e "\033[1;33m[WARNING]\033[0m Some /mnt submounts may still be busy. Forcing lazy unmount..."
        sudo umount -lR /mnt || true
    }
fi

# If your script sometimes mounts /mnt/boot or /mnt/boot/EFI separately, unmount them, too:
if mount | grep -q "/mnt/boot/EFI"; then
    sudo umount /mnt/boot/EFI || umount -l /mnt/boot/EFI || true
fi
if mount | grep -q "/mnt/boot "; then
    sudo umount /mnt/boot || umount -l /mnt/boot || true
fi

# 3) Remove LVM logical volumes and the volume group
#    You have LVs named nix-root, nix-home, etc. So let's just remove them all
#    forcibly, then remove the VG itself.

echo -e "\033[1;34m[INFO]\033[0m Removing LVM volumes & volume group..."
if vgs nix &>/dev/null; then
    # Remove all logical volumes in the "nix" VG
    sudo lvremove -fy nix || true

    # Remove the "nix" volume group entirely
    sudo vgremove -fy nix || true
fi

# 4) Stop and remove ANY active mdadm RAID arrays (like /dev/md0)
echo -e "\033[1;34m[INFO]\033[0m Stopping RAID arrays..."
sudo mdadm --stop --scan || true

# Double-check each /dev/md* in case it didn't get removed
for array in $(ls /dev/md* 2>/dev/null || true); do
    sudo mdadm --stop "$array"   2>/dev/null || true
    sudo mdadm --remove "$array" 2>/dev/null || true
    # Also zero superblock if it’s still recognized as an MD device
    sudo mdadm --zero-superblock "$array" 2>/dev/null || true
    sudo wipefs -a "$array"      2>/dev/null || true
done

# 5) Close or remove ANY leftover device mapper nodes because now LVM and RAID
# are gone, they should not be "busy" anymore.

echo -e "\033[1;34m[INFO]\033[0m Removing leftover device mapper entries..."

function nuke_mapper_device() {
    local mapper_name="$1"
    if dmsetup info "$mapper_name" &>/dev/null; then
        echo -e "\033[1;33m[WARNING]\033[0m Forcing removal of /dev/mapper/$mapper_name"
        sudo dmsetup remove -f "$mapper_name" || true
    fi
}

while read -r mapper_line; do
    mapper_device=$(echo "$mapper_line" | awk '{print $1}')
    # "No devices found" line is possible
    [[ "$mapper_device" == "No" ]] && continue
    nuke_mapper_device "$mapper_device"
done < <(sudo dmsetup ls 2>/dev/null || echo "")

# 6) Finally, wipe the partition table on the DEFAULT_BOOT drive
echo -e "\033[1;34m[INFO]\033[0m Wiping partition table on ${DEFAULT_BOOT}..."
for i in {1..3}; do
    sudo wipefs -a "${DEFAULT_BOOT}" || true
done
sudo partprobe "${DEFAULT_BOOT}" || echo "Reboot may be required."

### PARTITIONING ###
echo -e "\033[1;34m[INFO]\033[0m Partitioning ${DEFAULT_BOOT}..."
sudo parted -s ${DEFAULT_BOOT} mklabel gpt

# 1  ESP    512 MiB
sudo parted -s ${DEFAULT_BOOT} mkpart ESP fat32     1MiB  551MiB
sudo parted -s ${DEFAULT_BOOT} set   1 esp on

# 2  /boot  2 GiB
sudo parted -s ${DEFAULT_BOOT} mkpart BOOT ext4    551MiB 2599MiB

# 3  /secrets 256 MiB (will be LUKS2 → ext4)
sudo parted -s ${DEFAULT_BOOT} mkpart SECRETS ext4 2599MiB 2855MiB

# 4  /data  remainder of the stick
sudo parted -s ${DEFAULT_BOOT} mkpart DATA ext4    2855MiB 100%

### FORMATTING EFI ###
echo -e "\033[1;34m[INFO]\033[0m Formatting EFI partition..."
sudo mkfs.vfat -v -F 32 ${EFI_PARTITION}

### FORMATTING & MOUNTING /BOOT ###
echo -e "\033[1;34m[INFO]\033[0m Formatting and mounting /boot..."
sudo mkfs.ext4 ${BOOT_PARTITION}
sudo mkdir -p ${BOOT_MOUNT}
sudo mount ${BOOT_PARTITION} ${BOOT_MOUNT}
sudo mkdir -p ${BOOT_MOUNT}/EFI
sudo mount ${EFI_PARTITION} ${BOOT_MOUNT}/EFI

# create & unlock the **LUKS2 /secrets** slice
echo -e "\033[1;34m[INFO]\033[0m Creating encrypted /secrets partition (you’ll be prompted once)..."
sudo cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 --key-size 512 --hash sha256 ${SECRETS_PARTITION}
sudo cryptsetup luksOpen ${SECRETS_PARTITION} secrets_crypt
sudo mkfs.ext4  /dev/mapper/secrets_crypt
sudo mkdir -p   ${SECRETS_MOUNT}
sudo mount      /dev/mapper/secrets_crypt ${SECRETS_MOUNT}

# This is the hardware encryption key. This can be multiple keys. Keeping it simple for now.
sudo mkdir -p ${KEYS_DIR}
sudo openssl rand -out ${KEYS_DIR}/nvme.key 64
sudo chmod 400 ${KEYS_DIR}/nvme.key

### CREATING RAID-0 ###
if [ -e /dev/md0 ]; then
    echo -e "\033[1;34m[INFO]\033[0m Stopping existing RAID-0 array..."
    sudo mdadm --stop /dev/md0 || true
    sudo mdadm --remove /dev/md0 || true
    sudo wipefs -a /dev/md0 || true
    sudo mdadm --zero-superblock /dev/${BLOCK_01} /dev/${BLOCK_02} || true
fi

echo -e "\033[1;34m[INFO]\033[0m Creating RAID-0 array..."
sudo mdadm --create --verbose /dev/md0 --level=0 --raid-devices=2 --chunk=512K /dev/${BLOCK_01} /dev/${BLOCK_02}

### CREATING LVM ###
echo -e "\033[1;34m[INFO]\033[0m Creating LVM structure..."

# 1️⃣  Create the Physical Volume
sudo pvcreate -ff /dev/md0 || { echo -e "\033[1;31m[ERROR]\033[0m Failed to create Physical Volume!"; exit 1; }

# 2️⃣  Create the Volume Group
sudo vgcreate -s 16M nix /dev/md0 || { echo -e "\033[1;31m[ERROR]\033[0m Failed to create Volume Group!"; exit 1; }

# 3️⃣  Create Logical Volumes
sudo lvcreate -L 96G  -n swap nix -C y || { echo -e "\033[1;31m[ERROR]\033[0m Failed to create swap LV!"; exit 1; }
sudo lvcreate -L 80G  -n tmp  nix -C y || { echo -e "\033[1;31m[ERROR]\033[0m Failed to create tmp LV!"; exit 1; }
sudo lvcreate -L 80G  -n var  nix -C y || { echo -e "\033[1;31m[ERROR]\033[0m Failed to create var LV!"; exit 1; }
sudo lvcreate -L 200G -n root nix -C y || { echo -e "\033[1;31m[ERROR]\033[0m Failed to create root LV!"; exit 1; }
sudo lvcreate -L 500G -n home nix -C y || { echo -e "\033[1;31m[ERROR]\033[0m Failed to create home LV!"; exit 1; }

# 4️⃣  Verify LVM setup
echo -e "\033[1;34m[INFO]\033[0m Verifying LVM setup..."
sudo vgdisplay nix
sudo lvdisplay nix

# 5️⃣  Format Logical Volumes with F2FS
echo -e "\033[1;34m[INFO]\033[0m Formatting Logical Volumes with F2FS...",fs_verity
sudo mkfs.f2fs -f -O extra_attr,inode_checksum,sb_checksum,flexible_inline_xattr -z 512 /dev/nix/tmp  || { echo -e "\033[1;31m[ERROR]\033[0m Failed to format tmp LV!"; exit 1; }
sudo mkfs.f2fs -f -O extra_attr,inode_checksum,sb_checksum,flexible_inline_xattr -z 512 /dev/nix/var  || { echo -e "\033[1;31m[ERROR]\033[0m Failed to format var LV!"; exit 1; }
sudo mkfs.f2fs -f -O extra_attr,inode_checksum,sb_checksum,flexible_inline_xattr -z 512 /dev/nix/root || { echo -e "\033[1;31m[ERROR]\033[0m Failed to format root LV!"; exit 1; }
sudo mkfs.f2fs -f -O extra_attr,inode_checksum,sb_checksum,flexible_inline_xattr -z 512 /dev/nix/home || { echo -e "\033[1;31m[ERROR]\033[0m Failed to format home LV!"; exit 1; }

# 6️⃣  Configure Swap
echo -e "\033[1;34m[INFO]\033[0m Configuring Swap..."
sudo mkswap /dev/nix/swap
sudo swapon /dev/nix/swap

# 6.5 Unmount Boot and EFI (First step)
echo -e "\033[1;34m[INFO]\033[0m Unmounting Boot and EFI..."
sudo umount ${BOOT_MOUNT}/EFI || true
sudo umount ${BOOT_MOUNT} || true
sudo umount ${SECRETS_MOUNT}  || true
sudo cryptsetup luksClose secrets_crypt || true

# 7️⃣  Mount Logical Volumes
echo -e "\033[1;34m[INFO]\033[0m Mounting Logical Volumes..."
sudo mount /dev/nix/root /mnt || { echo -e "\033[1;31m[ERROR]\033[0m Failed to mount root!"; exit 1; }
sudo mkdir -p /mnt/tmp  && mount /dev/nix/tmp  /mnt/tmp
sudo mkdir -p /mnt/var  && mount /dev/nix/var  /mnt/var
sudo mkdir -p /mnt/home && mount /dev/nix/home /mnt/home

# 8️⃣  Remount Boot and EFI
echo -e "\033[1;34m[INFO]\033[0m Remounting Boot and EFI..."
sudo mkdir -p ${BOOT_MOUNT} && mount ${BOOT_PARTITION} ${BOOT_MOUNT}
sudo mkdir -p ${BOOT_MOUNT}/EFI && mount ${EFI_PARTITION} ${BOOT_MOUNT}/EFI

# remount secrets for the copy-to-nixos step
sudo mkdir -p ${SECRETS_MOUNT}
sudo cryptsetup luksOpen ${SECRETS_PARTITION} secrets_crypt
sudo mount /dev/mapper/secrets_crypt ${SECRETS_MOUNT}

echo -e "\033[1;34m[INFO]\033[0m Verifying that all devices and filesystems are correctly set up..."

# Check RAID status
if ! grep -q "md0" /proc/mdstat; then
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

echo -e "\033[1;34m[INFO]\033[0m Waiting for all LVM volumes to settle..."
REQUIRED_MOUNTS=("tmp" "var" "home" "boot" "boot/EFI")

# Wait for up to 10 seconds for all required mounts
for i in {1..10}; do
    MISSING_MOUNTS=()

    for mountpoint in "${REQUIRED_MOUNTS[@]}"; do
        if ! findmnt -r "/mnt/$mountpoint" &>/dev/null; then
            MISSING_MOUNTS+=("$mountpoint")
        fi
    done

    if [ ${#MISSING_MOUNTS[@]} -eq 0 ]; then
        echo -e "\033[1;32m[OK]\033[0m All required filesystems are mounted."
        break
    fi

    echo -e "\033[1;33m[WAITING]\033[0m Still waiting for: ${MISSING_MOUNTS[*]}... retrying in 1 second."
    sleep 1
done

# Final hard check to fail if any mounts are still missing
MISSING_FINAL=()
for mountpoint in "${REQUIRED_MOUNTS[@]}"; do
    if ! findmnt -r "/mnt/$mountpoint" &>/dev/null; then
        MISSING_FINAL+=("$mountpoint")
    fi
done

if [ ${#MISSING_FINAL[@]} -ne 0 ]; then
    echo -e "\033[1;31m[ERROR]\033[0m The following mount points are still missing: ${MISSING_FINAL[*]}"
    exit 1
fi

echo -e "\033[1;34m[INFO]\033[0m All devices, filesystems, and mounts are correctly set up."

### CLONING NIXOS CONFIG FROM GIT ###
echo -e "\033[1;34m[INFO]\033[0m Generating initial hardware configuration..."
sudo nixos-generate-config --root /mnt  # <-- Creates initial /mnt/etc/* files

### ASK USER FOR HOSTNAME ###
echo -e "\033[1;34m[INFO]\033[0m Please enter the hostname for this system:"
read -p "Hostname: " HOSTNAME

# Ensure it's a valid hostname (no spaces or special characters)
if [[ ! "$HOSTNAME" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    echo -e "\033[1;31m[ERROR]\033[0m Invalid hostname. Use only letters, numbers, dots, hyphens, and underscores."
    exit 1
fi

echo -e "\033[1;34m[INFO]\033[0m Copying NixOS flake repo to its official destination..."
sudo cp -r /home/nixos/nixos /mnt/etc

echo -e "\033[1;34m[INFO]\033[0m Moving the hardware configuration to the host-specific path in the repo..."
mv /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/hosts/$HOSTNAME/hardware-configuration.nix
mv /mnt/etc/nixos/configuration.nix /mnt/etc/nixos/configuration.nix.installer

echo -e "\033[1;34m[INFO]\033[0m Extracting hardware-specific details for flake configuration..."

# Get UUIDs for devices and filesystems
boot_uuid=$(blkid -s UUID -o value ${DEFAULT_BOOT}2)
boot_fs_uuid=$(blkid -s UUID -o value ${BOOT_PARTITION})
efi_fs_uuid=$(blkid -s UUID -o value ${EFI_PARTITION})
root_fs_uuid=$(findmnt -no UUID /mnt)
var_fs_uuid=$(findmnt -no UUID /mnt/var)
tmp_fs_uuid=$(findmnt -no UUID /mnt/tmp)
home_fs_uuid=$(findmnt -no UUID /mnt/home)

# UUID of the *unencrypted* mapper device
secrets_fs_uuid=$(blkid -s UUID -o value /dev/mapper/secrets_crypt)

# Get persistent device paths
nvme0_path=$(ls -l /dev/disk/by-id/ | awk '/nvme-uuid.*nvme0n1/ {print "/dev/disk/by-id/" $9}' | head -n1)
nvme1_path=$(ls -l /dev/disk/by-id/ | awk '/nvme-uuid.*nvme1n1/ {print "/dev/disk/by-id/" $9}' | head -n1)

if [[ -z "$nvme0_path" || -z "$nvme1_path" ]]; then
    echo -e "\033[1;31m[ERROR]\033[0m Failed to determine NVMe device paths!"
    echo "Check your system's device list manually and update flake.nix as needed."
    exit 1
fi

# Validate extracted values against hardware-configuration.nix
HWC_PATH="/mnt/etc/nixos/hosts/$HOSTNAME/hardware-configuration.nix"
echo -e "\033[1;34m[INFO]\033[0m Verifying extracted values exist in hardware-configuration.nix..."

MISSING_VALUES=0
check_value "$boot_uuid" "Boot UUID"
check_value "$boot_fs_uuid" "Boot Filesystem UUID"
check_value "$efi_fs_uuid" "EFI Filesystem UUID"
check_value "$secrets_fs_uuid"  "Secrets Filesystem UUID"

if [[ $MISSING_VALUES -gt 0 ]]; then
    echo -e "\033[1;31m[ERROR]\033[0m Some expected values were not found in hardware-configuration.nix!"
    echo "Please check hardware-configuration.nix and ensure all required values are present."
    exit 1
fi

echo -e "\033[1;34m[INFO]\033[0m Writing ${BOOT_MOUNT}/secrets/flakey.json ..."

# ensure the directory exists on the *boot* filesystem
sudo mkdir -p "${BOOT_MOUNT}/secrets"

sudo cat > "${BOOT_MOUNT}/secrets/flakey.json" <<EOF
{
  "PLACEHOLDER_NVME0":  "${nvme0_path}",
  "PLACEHOLDER_NVME1":  "${nvme1_path}",

  "PLACEHOLDER_BOOT_FS_UUID":   "/dev/disk/by-uuid/${boot_fs_uuid}",
  "PLACEHOLDER_EFI_FS_UUID":    "/dev/disk/by-uuid/${efi_fs_uuid}",

  "PLACEHOLDER_ROOT":  "/dev/disk/by-uuid/${root_fs_uuid}",
  "PLACEHOLDER_VAR":   "/dev/disk/by-uuid/${var_fs_uuid}",
  "PLACEHOLDER_TMP":   "/dev/disk/by-uuid/${tmp_fs_uuid}",
  "PLACEHOLDER_HOME":  "/dev/disk/by-uuid/${home_fs_uuid}",

  "PLACEHOLDER_SECRETS": "/dev/disk/by-uuid/${secrets_fs_uuid}",

  "GIT_SMTP_PASS": "mlucmulyvpqlfprb"
}
EOF

sudo chmod 600 "${BOOT_MOUNT}/secrets/flakey.json"

### APPLYING SYSTEM CONFIGURATION ###

echo -e "\033[1;34m[INFO]\033[0m Installing NixOS from flake..."
nixos-install \
  --flake /mnt/etc/nixos#${HOSTNAME} \
  --override-input secrets-empty path:${BOOT_MOUNT}/secrets/flakey.json

sudo umount ${SECRETS_MOUNT}
sudo cryptsetup luksClose secrets_crypt
sudo umount "${BOOT_MOUNT}/EFI"
sudo umount "${BOOT_MOUNT}"

echo -e "\033[1;32m[SUCCESS]\033[0m Installation complete! Reboot when ready."
