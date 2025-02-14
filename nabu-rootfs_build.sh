#!/bin/bash

# Exit on any error, undefined variable, or pipe failure
set -euo pipefail

# Configuration
VERSION="24.04.1"
IMAGE_SIZE="10G"
ROOTFS_IMAGE="rootfs.img"
ROOTDIR="rootdir"
HOSTNAME="xiaomi-nabu"
DNS_SERVER="1.1.1.1"
QEMU_VERSION="v7.2.0-1"

# Check root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: rootfs can only be built as root" >&2
    exit 1
fi

# Cleanup function to ensure proper unmounting
cleanup() {
    local exit_code=$?
    echo "Performing cleanup..."
    
    # Only attempt unmounting if directory exists
    if [ -d "$ROOTDIR" ]; then
        for mount_point in sys proc dev/pts dev; do
            if mountpoint -q "$ROOTDIR/$mount_point" 2>/dev/null; then
                umount "$ROOTDIR/$mount_point" || echo "Warning: Failed to unmount $ROOTDIR/$mount_point"
            fi
        done
        
        if mountpoint -q "$ROOTDIR" 2>/dev/null; then
            umount "$ROOTDIR" || echo "Warning: Failed to unmount $ROOTDIR"
        fi
        
        rm -rf "$ROOTDIR"
    fi
    
    exit "$exit_code"
}

# Register cleanup function
trap cleanup EXIT INT TERM

# Create and mount rootfs image
echo "Creating rootfs image..."
truncate -s "$IMAGE_SIZE" "$ROOTFS_IMAGE"
mkfs.ext4 "$ROOTFS_IMAGE"
mkdir -p "$ROOTDIR"
mount -o loop "$ROOTFS_IMAGE" "$ROOTDIR"

# Download and extract Ubuntu base
echo "Downloading Ubuntu base system..."
UBUNTU_BASE="ubuntu-base-$VERSION-base-arm64.tar.gz"
wget "https://cdimage.ubuntu.com/ubuntu-base/releases/$VERSION/release/$UBUNTU_BASE"
tar xzf "$UBUNTU_BASE" -C "$ROOTDIR"
rm "$UBUNTU_BASE"

# Mount necessary filesystems
echo "Mounting system directories..."
for dir in dev dev/pts proc sys; do
    mkdir -p "$ROOTDIR/$dir"
    mount --bind "/$dir" "$ROOTDIR/$dir"
done

# Configure basic system settings
echo "Configuring system..."
echo "nameserver $DNS_SERVER" > "$ROOTDIR/etc/resolv.conf"
echo "$HOSTNAME" > "$ROOTDIR/etc/hostname"
cat > "$ROOTDIR/etc/hosts" << EOF
127.0.0.1 localhost
127.0.1.1 $HOSTNAME
EOF

# Setup QEMU if needed
if ! uname -m | grep -q aarch64; then
    echo "Setting up QEMU for non-ARM64 system..."
    wget "https://github.com/multiarch/qemu-user-static/releases/download/$QEMU_VERSION/qemu-aarch64-static"
    install -m755 qemu-aarch64-static "$ROOTDIR/"
    
    for type in "" "ld"; do
        echo ":aarch64$type:M::ELF::/qemu-aarch64-static:" > "/proc/sys/fs/binfmt_misc/register"
    done
fi

# Configure package installation environment
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH
export DEBIAN_FRONTEND=noninteractive

# Update and install packages
echo "Installing packages..."
chroot "$ROOTDIR" apt update
chroot "$ROOTDIR" apt upgrade -y

# Install desktop environment and core packages
echo "Installing desktop environment..."
chroot "$ROOTDIR" apt install -y \
    bash-completion \
    sudo \
    ssh \
    nano \
    u-boot-tools- \
    ubuntu-desktop-minimal \
    dpkg-dev \
    gnome-initial-setup \
    cloud-init-

# Install device-specific packages
echo "Installing device-specific packages..."
chroot "$ROOTDIR" apt install -y rmtfs protection-domain-mapper tqftpserv

# Configure systemd service
sed -i '/ConditionKernelVersion/d' "$ROOTDIR/lib/systemd/system/pd-mapper.service"

# Install device-specific packages
echo "Installing device packages..."
cp "xiaomi-nabu-debs"/*-xiaomi-nabu.deb "$ROOTDIR/tmp/"
for pkg in linux firmware alsa; do
    chroot "$ROOTDIR" dpkg -i "/tmp/$pkg-xiaomi-nabu.deb"
done
rm "$ROOTDIR/tmp"/*-xiaomi-nabu.deb

# Configure fstab
cat > "$ROOTDIR/etc/fstab" << EOF
PARTLABEL=linux / ext4 errors=remount-ro,x-systemd.growfs 0 1
PARTLABEL=esp /boot/efi vfat umask=0077 0 1
EOF

# Setup initial system configuration
mkdir -p "$ROOTDIR/var/lib/gdm3"
touch "$ROOTDIR/var/lib/gdm3/run-initial-setup"

# Clean up package cache
chroot "$ROOTDIR" apt clean

# Remove previously created resolv.conf
rm -rf "$ROOTDIR/etc/resolv.conf"

# Cleanup QEMU if installed
if ! uname -m | grep -q aarch64; then
    echo "Cleaning up QEMU..."
    for type in "" "ld"; do
        echo -1 > "/proc/sys/fs/binfmt_misc/aarch64$type"
    done
    rm -f "$ROOTDIR/qemu-aarch64-static" qemu-aarch64-static
fi

# Sparsify the image using android-sdk-libsparse-utils
echo "Sparsifying rootfs image..."
# Remove .img extension and create sparse image
SPARSE_IMAGE="${ROOTFS_IMAGE%.img}.sparse.img"
if ! command -v img2simg &> /dev/null; then
    echo "Error: img2simg not found." >&2
    exit 1
fi

if ! img2simg "$ROOTFS_IMAGE" "$SPARSE_IMAGE" 2>/dev/null; then
    echo "Error: Failed to create sparse image from $ROOTFS_IMAGE" >&2
    exit 1
fi
echo "Successfully created sparse image: $SPARSE_IMAGE"

# Compress both images in parallel
echo "Compressing images..."
xz "$ROOTFS_IMAGE" &
xz "$SPARSE_IMAGE" &
wait

echo "Build complete!"
