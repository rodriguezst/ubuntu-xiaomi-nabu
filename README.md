<img align="right" src="https://raw.githubusercontent.com/rodriguezst/ubuntu-xiaomi-nabu/master/ubnt.png" width="425" alt="Ubuntu 23.04 Running On A Xiaomi Pad 5">

# Ubuntu for Xiaomi Pad 5
This repository contains scripts for automated building of Ubuntu rootfs and kernel for Xiaomi Pad 5.

## Getting Started

### Download Required Files
1. Navigate to the "Actions" tab
2. Locate the latest successful build
3. Download the following file based on your needs:
   - For fresh installation: `rootfs_[VARIANT].zip` and `unified_kernel_image.zip`

     Replace `[VARIANT]` with `dd` or `fastboot` depending on the flash method you plan on using
   - For updates: `xiaomi-nabu-debs.zip` and `unified_kernel_image.zip`

### Installation Process
1. Extract the downloaded rootfs ZIP file
2. Extract the resulting `.xz` file to obtain `rootfs.img` (for dd) or `rootfs.sparse.img` (for fastboot)
3. Prepare your partitions:
   - Flash `rootfs.img` to the partition named "linux"
      - a) Using fastboot from another computer:
      ```bash
      fastboot flash linux rootfs.img
      ```
      - b) Using dd (from Linux/Termux/TWRP...):
      ```bash
      dd if=rootfs.sparse.img of=/dev/block/platform/soc/1d84000.ufshc/by-name/linux bs=100M status=progress
      ```
   - Ensure EFI boot partition is named "esp"
4. Copy `uki-[KERNEL-VERSION].efi` file to `esp` at `EFI/ubuntu/uki-[KERNEL-VERSION].efi`

   NOTE: If using UEFI from Project Renegade rename kernel to `EFI/ubuntu/grubaa64.efi` so that it gets autodetected by simple-init

### Update Process
1. Extract the downloaded update ZIP file
2. Install the Debian packages:
   ```bash
   dpkg -i *-xiaomi-nabu.deb
   ```
3. Copy `uki-[KERNEL-VERSION].efi` file to `esp` at `EFI/ubuntu/uki-[KERNEL-VERSION].efi`
