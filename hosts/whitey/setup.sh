#!/run/current-system/sw/bin/bash

set -euo pipefail  # Safer script execution
shopt -s lastpipe
export LC_ALL=C

### FUNCTIONS
function confirm() {
    echo -e "\n\033[1;33m[WARNING]\033[0m $1"
    read -p "Type 'YES' to proceed: " response
    if [[ "$response" != "YES" ]]; then
        echo "Aborting."
        exit 1
    fi
}

# ────────────────────────────────────────────────────────────────
# NVMe SED helper functions (no heredocs; inline expect)
# ────────────────────────────────────────────────────────────────

# Reads passphrase from ${KEYS_DIR}/nvme.key (created later)
sed_load_key() {
    SED_KEY="$(sudo tr -d '\n' < "${KEYS_DIR}/nvme.key")"
    if [[ -z "${SED_KEY:-}" ]]; then
        echo -e "\033[1;31m[ERROR]\033[0m nvme.key is empty or missing"
        return 1
    fi
}

# Initialize Opal on a namespace (prompts for *new* password)
sed_initialize() {
    local dev="$1"
    sed_load_key
    echo -e "\033[1;34m[INFO]\033[0m Initializing Opal on ${dev}..."
    expect -c "
        set timeout 60
        spawn sudo nvme sed initialize $dev
        # Different firmwares prompt differently; answer any password/key prompts twice if asked.
        expect {
          -re {(?i)pass(word)?|key.*:} { send -- \"${SED_KEY}\r\"; exp_continue }
          eof
        }
    "
}

# Unlock (needs existing password)
sed_unlock() {
    local dev="$1"
    sed_load_key
    echo -e "\033[1;34m[INFO]\033[0m Unlocking ${dev}..."
    expect -c "
        set timeout 30
        spawn sudo nvme sed unlock $dev --ask-key
        expect -re {(?i)pass(word)?|key.*:} { send -- \"${SED_KEY}\r\" }
        expect eof
    "
}

# Lock the drive (requires current password)
sed_lock() {
    local dev="$1"
    sed_load_key
    echo -e "\033[1;34m[INFO]\033[0m Locking ${dev}..."
    expect -c "
        set timeout 30
        spawn sudo nvme sed lock $dev --ask-key
        expect -re {(?i)pass(word)?|key.*:} { send -- \"${SED_KEY}\r\" }
        expect eof
    "
}

# Revert a drive out of Opal state.
# mode: 'normal' (no flags), 'destructive' (--destructive), or 'psid' (--psid; will prompt for PSID).
sed_revert() {
    local dev="$1"
    local mode="$2"
    echo -e "\033[1;33m[WARN]\033[0m Reverting ${dev} from Opal state (mode=${mode})..."
    case "$mode" in
      normal)
        sudo nvme sed revert "$dev"
        ;;
      destructive)
        sudo nvme sed revert "$dev" --destructive
        ;;
      psid)
        read -rp "Enter PSID for ${dev} (printed on drive label, no dashes): " PSID
        if [[ -z "$PSID" ]]; then
            echo -e "\033[1;31m[ERROR]\033[0m PSID required for PSID revert."
            return 1
        fi
        # Some builds of nvme-cli will prompt; drive it with expect just in case.
        expect -c "
            set timeout 90
            spawn sudo nvme sed revert $dev --psid
            expect {
              -re {(?i)psid.*:} { send -- \"${PSID}\r\"; exp_continue }
              eof
            }
        "
        ;;
      *)
        echo -e "\033[1;31m[ERROR]\033[0m Unknown revert mode: $mode"
        return 1
        ;;
    esac
}

# Minimal runtime cleanup so kernel state is sane before/after SED ops
runtime_sanity() {
    echo -e "\033[1;34m[INFO]\033[0m Preparing runtime state (swapoff, unmounts, md/dm cleanup)…"
    sudo swapoff -a 2>/dev/null || true
    sudo umount -R /mnt 2>/dev/null || sudo umount -lR /mnt 2>/dev/null || true
    sudo umount /mnt/boot/EFI 2>/dev/null || true
    sudo umount /mnt/boot 2>/dev/null || true
    sudo mdadm --stop --scan 2>/dev/null || true
    for md in /dev/md/* /dev/md*; do
      [ -b "$md" ] || continue
      sudo mdadm --stop "$md" 2>/dev/null || true
      sudo mdadm --remove "$md" 2>/dev/null || true
    done
    for map in $(sudo dmsetup ls 2>/dev/null | awk '{print $1}'); do
      sudo dmsetup remove -f "$map" 2>/dev/null || true
    done
    sudo partprobe /dev/nvme0n1 2>/dev/null || true
    sudo partprobe /dev/nvme1n1 2>/dev/null || true
    sudo udevadm settle || true
}

# Assert Opal is enabled and currently unlocked on a device
sed_assert_enabled_unlocked() {
    local dev="$1"
    local out enabled locked
    out="$(sudo nvme sed discover "$dev" 2>/dev/null || true)"
    enabled="$(echo "$out" | awk -F: '/Locking Feature Enabled/{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
    locked="$(echo "$out" | awk -F: '/^[[:space:]]*Locked/{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
    if [[ "$enabled" != "Yes" ]]; then
        echo -e "\033[1;31m[ERROR]\033[0m ${dev}: Locking Feature Enabled != Yes after initialize"; exit 1
    fi
    if [[ "$locked" != "No" ]]; then
        echo -e "\033[1;31m[ERROR]\033[0m ${dev}: drive is locked unexpectedly"; exit 1
    fi
}

# Query and return 'Yes'/'No' for Locking Feature Enabled
sed_enabled() {
    local dev="$1"
    local out
    out="$(sudo nvme sed discover "$dev" 2>/dev/null || true)"
    val="$(echo "$out" | awk -F: '/Locking Feature Enabled/{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
    [[ -z "$val" ]] && echo "Unknown" || echo "$val"
}

# Full reset+init flow for one namespace:
#  - Always try destructive revert (hardware crypto-wipe). If it fails and Opal
#    was previously enabled, offer PSID revert; otherwise continue.
#  - Initialize (sets password via prompt to our key).
#  - Verify lock+unlock; leave unlocked.
sed_reset_and_init() {
    local dev="$1"
    local en
    en=$(sed_enabled "$dev" || echo "Unknown")

    echo -e "\033[1;34m[INFO]\033[0m Checking SED state for ${dev} (Enabled: ${en})"
    echo -e "\033[1;34m[INFO]\033[0m Attempting hardware crypto-wipe (destructive revert) on ${dev}…"
    if ! sed_revert "$dev" destructive; then
        if [[ "$en" == "Yes" ]]; then
            echo -e "\033[1;33m[WARN]\033[0m Destructive revert failed and Opal was enabled; offering PSID revert."
            sed_revert "$dev" psid
        else
            echo -e "\033[1;33m[WARN]\033[0m Destructive revert not supported/failed on ${dev}; continuing."
        fi
    fi
    # Reset controller node after revert so the kernel forgets stale state
    sudo nvme reset "${dev%%n*}" 2>/dev/null || true; sudo udevadm settle || true

    # Initialize and set password
    sed_initialize "$dev"

    # Some firmware needs a moment to settle before state reflects correctly
    sudo udevadm settle || true; sleep 0.5

    # Must report enabled after init
    sed_assert_enabled_unlocked "$dev"

    # Verification: lock then unlock using our key, leave unlocked
    echo -e "\033[1;34m[INFO]\033[0m Verifying lock/unlock on ${dev}…"
    sed_lock "$dev" || { echo -e "\033[1;31m[ERROR]\033[0m Failed to lock ${dev}"; exit 1; }
    sed_unlock "$dev" || { echo -e "\033[1;31m[ERROR]\033[0m Failed to unlock ${dev} after locking"; exit 1; }

    echo -e "\033[1;34m[INFO]\033[0m Post-verification SED state for ${dev}:"
    sed_assert_enabled_unlocked "$dev"
    sudo nvme sed discover "$dev" || true
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
BOOT_MOUNT="/mnt/boot"
SECRETS_MOUNT="/mnt/secrets"
EFI_PARTITION="${DEFAULT_BOOT}1"
BOOT_PARTITION="${DEFAULT_BOOT}2"
SECRETS_PARTITION="${DEFAULT_BOOT}3"
DATA_PARTITION="${DEFAULT_BOOT}4"

# keys will live on the encrypted /secrets partition
KEYS_DIR="${SECRETS_MOUNT}/keys"

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
for cmd in openssl parted mdadm pvcreate vgcreate lvcreate mkfs.ext4 mkfs.f2fs mkfs.vfat git nvme expect dmsetup; do
    check_command "$cmd"
done

### RUNTIME SANITY (compact) ###
runtime_sanity

echo -e "\033[1;34m[INFO]\033[0m Proceeding with SED hardware crypto-wipe & init before provisioning…"

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

# ────────────────────────────────────────────────────────────────
# Create/keep SED passphrase & (optionally) reset pre-encrypted drives
# ────────────────────────────────────────────────────────────────
sudo mkdir -p "${KEYS_DIR}"
# 24-byte random, base64 (~32 chars). Regenerate only if missing.
if [[ ! -f "${KEYS_DIR}/nvme.key" ]]; then
  echo -e "\033[1;34m[INFO]\033[0m Generating SED passphrase (Base64, 24 bytes)…"
  sudo openssl rand -base64 24 | sudo tee "${KEYS_DIR}/nvme.key" >/dev/null
  sudo chmod 0400 "${KEYS_DIR}/nvme.key"
  sync
else
  echo -e "\033[1;33m[WARN]\033[0m ${KEYS_DIR}/nvme.key already exists; reusing."
fi

# Hardware crypto-wipe + initialize + verify lock/unlock on both namespaces
for dev in "/dev/${BLOCK_01}" "/dev/${BLOCK_02}"; do
  sed_reset_and_init "$dev"
done

### CREATING RAID-0 ###

echo -e "\033[1;34m[INFO]\033[0m Ensuring no stale md0 is present..."
sudo mdadm --stop /dev/md0 || true
sudo mdadm --remove /dev/md0 || true

for i in {1..5}; do
    if [ -e /dev/md0 ]; then
        echo -e "\033[1;33m[WAITING]\033[0m md0 still present... waiting 1s"
        sleep 1
    else
        break
    fi
done

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
echo -e "\033[1;34m[INFO]\033[0m Formatting Logical Volumes with F2FS..."
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
mv /mnt/etc/nixos/hardware-configuration.nix /mnt/etc/nixos/hosts/$HOSTNAME/hardware.nix

HWC_PATH="/mnt/etc/nixos/hosts/$HOSTNAME/hardware.nix"

# 🔩 Add required kernel modules if not already present
#echo -e "\033[1;34m[INFO]\033[0m Injecting required initrd kernel modules..."
#sed -i '/boot\.initrd\.availableKernelModules = \[/,/];/c\
  #boot.initrd.availableKernelModules = [\
    #"nvme" "xhci_pci" "ahci" "thunderbolt" "usb_storage" "usbhid" "sd_mod"\
    #"trusted" "encrypted_keys" "tpm" "tpm_crb" "tpm_tis" "key_type_trusted" "key_type_encrypted"\
  #];' "$HWC_PATH"

# 🧠 Enable firmware, hardware, graphics, and QMK support
echo -e "\033[1;34m[INFO]\033[0m Enabling firmware and QMK keyboard support..."
sed -i '/^}/i\
  hardware.enableAllFirmware = true;\
  hardware.enableAllHardware = true;\
  hardware.graphics.enable = true;\
  hardware.keyboard.qmk.enable = true;\
' "$HWC_PATH"

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
echo -e "\033[1;34m[INFO]\033[0m Verifying extracted values exist in hardware.nix..."

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

# 🧼 Remove /secrets mount entry to avoid early-stage mount issues
echo -e "\033[1;34m[INFO]\033[0m Removing /secrets filesystem entry from hardware.nix..."
sed -i '/fileSystems\."\/secrets"/,/^\s*};/d' "$HWC_PATH"

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
