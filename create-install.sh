#!/bin/bash

# Script to create a custom Ubuntu autoinstall ISO for Ubuntu 24.04
# Assumes ubuntu-24.04.1-live-server-amd64.iso is in home dir and autoinstall.yaml is in the current directory

# Exit immediately if a command exits with a non-zero status
set -e

# Variables
ISO_NAME="$(pwd)/ubuntu-24.04.1-live-server-amd64.iso"
ISO_CUSTOM="$(pwd)/ubuntu-24.04.1-live-server-autoinstall.iso"
WORK_DIR="$(pwd)/ubuntu-autoinstall"
MOUNT_DIR="$WORK_DIR/mount"
ISO_DIR="$WORK_DIR/iso"
AUTOINSTALL_FILE="autoinstall.yaml"

# Check for required files
if [[ ! -f "$ISO_NAME" ]]; then
    echo "ISO file '$ISO_NAME' not found in the current directory."
    exit 1
fi

if [[ ! -f "$AUTOINSTALL_FILE" ]]; then
    echo "Autoinstall file '$AUTOINSTALL_FILE' not found in the current directory."
    exit 1
fi

# Install required packages
echo "Installing required packages..."
sudo apt-get update
sudo apt-get install -y xorriso grub-pc-bin grub-efi-amd64-bin grub-efi-ia32-bin mtools rsync dosfstools

# Create working directories
echo "Creating working directories..."
mkdir -p "$MOUNT_DIR" "$ISO_DIR"

# Mount the original ISO
echo "Mounting the original ISO..."
sudo mount -o loop "$ISO_NAME" "$MOUNT_DIR"

# Copy the contents of the ISO to the working directory
echo "Copying ISO contents..."
sudo rsync -a "$MOUNT_DIR/" "$ISO_DIR/"

# Unmount the ISO
echo "Unmounting the original ISO..."
sudo umount "$MOUNT_DIR"

# Change ownership to current user for editing
echo "Adjusting permissions..."
sudo chown -R "$(whoami):$(whoami)" "$ISO_DIR/"
sudo chmod -R u+w "$ISO_DIR/"

# Copy autoinstall.yaml to the root of the ISO
echo "Adding autoinstall configuration..."
cp "$AUTOINSTALL_FILE" "$ISO_DIR/"

# Modify GRUB configuration for both BIOS and UEFI boot
echo "Modifying GRUB configuration..."
GRUB_CFG="$ISO_DIR/boot/grub/grub.cfg"
sudo tee "$GRUB_CFG" > /dev/null <<EOF
search --set=root --file /casper/vmlinuz
set default=0
set timeout=5

menuentry "Autoinstall Ubuntu Server" {
    linux /casper/vmlinuz autoinstall ---
    initrd /casper/initrd
}
EOF

# Create GRUB EFI image
echo "Creating GRUB EFI image..."
mkdir -p "$ISO_DIR/EFI/boot"
grub-mkstandalone \
    --format=x86_64-efi \
    --output="$ISO_DIR/EFI/boot/bootx64.efi" \
    --locales="" \
    --fonts="" \
    "boot/grub/grub.cfg=$GRUB_CFG"

# Create UEFI boot image
echo "Creating UEFI boot image..."
dd if=/dev/zero of="$ISO_DIR/boot/grub/efi.img" bs=1M count=10
mkfs.vfat "$ISO_DIR/boot/grub/efi.img"
mmd -i "$ISO_DIR/boot/grub/efi.img" efi efi/boot
mcopy -i "$ISO_DIR/boot/grub/efi.img" "$ISO_DIR/EFI/boot/bootx64.efi" ::efi/boot/

# Updating MD5 checksums
echo "Updating MD5 checksums..."
cd "$ISO_DIR"
sudo chmod u+w md5sum.txt
sudo rm md5sum.txt
sudo find . -type f ! -name 'md5sum.txt' ! -path './ubuntu/*' -exec md5sum {} \; | sudo tee md5sum.txt

# Create the new ISO image
echo "Creating the custom ISO..."
cd "$WORK_DIR"
xorriso -as mkisofs \
    -iso-level 3 \
    -o "$ISO_CUSTOM" \
    -full-iso9660-filenames \
    -volid "UBUNTU_24_04_1_SERVER_AMD64" \
    -eltorito-boot boot/grub/i386-pc/eltorito.img \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
    -eltorito-alt-boot \
    -e boot/grub/efi.img \
        -no-emul-boot \
    -isohybrid-gpt-basdat \
    "$ISO_DIR"


# Clean up
echo "Cleaning up temporary files..."
sudo rm -rf "$WORK_DIR"

echo "Custom autoinstall ISO created successfully: $ISO_CUSTOM"
