#!/bin/bash

# Exit on any error, undefined variable, or pipe failure
set -euo pipefail

# Configuration
KERNEL_REPO="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"
KERNEL_BRANCH=v6.13.6
BUILD_DIR="linux"
DTB_PATH="qcom/sm8150-xiaomi-nabu.dtb"
DEBIAN_PACKAGES=(
    "linux-xiaomi-nabu"
    "firmware-xiaomi-nabu"
    "alsa-xiaomi-nabu"
)

# Cleanup function
cleanup() {
    local exit_code=$?
    echo "Performing cleanup..."
    if [ -d "$BUILD_DIR" ]; then
        rm -rf "$BUILD_DIR"
    fi
    exit "$exit_code"
}

# Register cleanup function
trap cleanup EXIT INT TERM

# Clone kernel repository
echo "Cloning kernel repository..."
git clone "$KERNEL_REPO" --branch "$KERNEL_BRANCH" --depth 1 "$BUILD_DIR"
cd "$BUILD_DIR"
echo "Applying patches..."
git am --whitespace=fix ../kernel-files/*.patch

# Copy kernel configuration
cp "../kernel-files/config" .config

# Determine system architecture and set build configuration
echo "Configuring build environment..."
ARCH="arm64"
MAKE_FLAGS=(
    "-j$(nproc)"
    "ARCH=$ARCH"
)

# Only use cross-compiler if not running on aarch64
if ! uname -m | grep -q "aarch64"; then
    CROSS_COMPILE="aarch64-linux-gnu-"
    # Check if cross-compiler is available
    if ! command -v "${CROSS_COMPILE}gcc" >/dev/null 2>&1; then
        echo "Error: Cross-compiler (${CROSS_COMPILE}gcc) not found" >&2
        echo "Please install gcc-aarch64-linux-gnu package" >&2
        exit 1
    fi
    MAKE_FLAGS+=("CROSS_COMPILE=$CROSS_COMPILE")
fi

echo "Building kernel..."
make "${MAKE_FLAGS[@]}" oldconfig
make "${MAKE_FLAGS[@]}" Image.gz modules dtbs

# Get kernel version
_kernel_version="$(make kernelrelease -s)"
echo "Kernel version: $_kernel_version"

# Install kernel and device tree
echo "Installing kernel and device tree..."
mkdir -p "../linux-xiaomi-nabu/boot"

# Copy kernel image and device tree
cp "arch/arm64/boot/Image" "../linux-xiaomi-nabu/boot/vmlinux-$_kernel_version"
cp "arch/arm64/boot/Image.gz" "../linux-xiaomi-nabu/boot/vmlinuz-$_kernel_version"
cp "arch/arm64/boot/dts/$DTB_PATH" "../linux-xiaomi-nabu/boot/dtb-$_kernel_version"

# Build Unified Kernel Image (UKI)
ukify build \
    --linux="../linux-xiaomi-nabu/boot/vmlinux-$_kernel_version" \
    --cmdline="console=tty0 root=PARTLABEL=linux quiet splash" \
    --uname="$_kernel_version" \
    --devicetree="../linux-xiaomi-nabu/boot/dtb-$_kernel_version" \
    --secureboot-private-key="../sb.key" \
    --secureboot-certificate="../sb.crt" \
    --output="../uki-$_kernel_version.efi"

# Update package version
echo "Updating package version..."
sed -i "s/Version:.*/Version: ${_kernel_version}/" "../linux-xiaomi-nabu/DEBIAN/control"

# Install kernel modules
echo "Installing kernel modules..."
rm -rf "../linux-xiaomi-nabu/lib"
make "${MAKE_FLAGS[@]}" INSTALL_MOD_PATH="../linux-xiaomi-nabu" modules_install
rm -f "../linux-xiaomi-nabu/lib/modules/"*"/build"

# Return to parent directory
cd ..

# Build Debian packages
echo "Building Debian packages..."
for package in "${DEBIAN_PACKAGES[@]}"; do
    echo "Building package: $package"
    if [ ! -d "$package" ]; then
        echo "Error: Package directory $package not found" >&2
        exit 1
    fi
    dpkg-deb --build --root-owner-group "$package"
done

echo "Build complete!"
