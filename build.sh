#!/bin/bash
set -e

# Configuration
KERNEL_SOURCE="${KERNEL_SOURCE:-https://github.com/HELLBOY017/kernel_oneplus_sm8250.git}"
KERNEL_BRANCH="${KERNEL_BRANCH:-thirteen}"
DEFCONFIG="${DEFCONFIG:-vendor/kona-perf_defconfig}"
DEVICE_NAME="${DEVICE_NAME:-oneplus8}"
SUSFS_VERSION="${SUSFS_VERSION:-v1.5.9}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[BUILD]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Clone kernel source
clone_kernel() {
    log "Cloning kernel source..."
    if [ -d "kernel_source" ]; then
        log "Kernel source already exists, pulling latest..."
        cd kernel_source && git pull || true
        cd ..
    else
        git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_SOURCE" kernel_source
    fi
}

# Setup KernelSU-Next
setup_kernelsu() {
    log "Setting up KernelSU-Next..."
    cd kernel_source

    # Remove existing KernelSU if present
    rm -rf KernelSU KernelSU-Next drivers/kernelsu

    # Clone KernelSU-Next
    git clone --depth=1 https://github.com/KernelSU-Next/KernelSU-Next.git -b next

    # Create symlink
    ln -sf ../KernelSU-Next/kernel drivers/kernelsu

    # Add to Makefile if not present
    if ! grep -q "kernelsu" drivers/Makefile; then
        echo 'obj-$(CONFIG_KSU) += kernelsu/' >> drivers/Makefile
    fi

    # Add to Kconfig if not present
    if ! grep -q "kernelsu/Kconfig" drivers/Kconfig; then
        sed -i '/endmenu/i source "drivers/kernelsu/Kconfig"' drivers/Kconfig
    fi

    cd ..
}

# Apply SUSFS patches
apply_susfs() {
    log "Applying SUSFS patches..."
    cd kernel_source

    # Clone SUSFS patches for kernel 4.19
    if [ ! -d "susfs4ksu" ]; then
        git clone --depth=1 https://gitlab.com/simonpunk/susfs4ksu.git -b kernel-4.19 susfs4ksu || \
        git clone --depth=1 https://github.com/sidex15/susfs4ksu.git -b kernel-4.19 susfs4ksu
    fi

    # Apply kernel patches
    if [ -d "susfs4ksu/kernel_patches" ]; then
        log "Applying SUSFS kernel patches..."
        for patch in susfs4ksu/kernel_patches/*.patch; do
            if [ -f "$patch" ]; then
                log "Applying $(basename $patch)..."
                git apply "$patch" || warn "Patch $(basename $patch) may have already been applied"
            fi
        done
    fi

    # Copy SUSFS source files
    if [ -d "susfs4ksu/kernel_patches/fs" ]; then
        cp -r susfs4ksu/kernel_patches/fs/* fs/ 2>/dev/null || true
    fi
    if [ -d "susfs4ksu/kernel_patches/include" ]; then
        cp -r susfs4ksu/kernel_patches/include/* include/ 2>/dev/null || true
    fi

    # Apply KernelSU-Next SUSFS patch
    log "Downloading KernelSU-Next SUSFS integration patch..."
    curl -sL "https://raw.githubusercontent.com/wshamroukh/KernelSU-Next-SUSFS-kernelv4.19/legacy/susfs-v2.0.0_kernelsu-next-legacy.patch" -o ksu_susfs.patch

    cd KernelSU-Next
    git apply ../ksu_susfs.patch || warn "KSU SUSFS patch may have already been applied"
    cd ..

    cd ..
}

# Configure kernel
configure_kernel() {
    log "Configuring kernel..."
    cd kernel_source

    # Make defconfig
    make O=out ARCH=arm64 CC=clang \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-android- \
        CROSS_COMPILE_ARM32=arm-linux-androideabi- \
        "$DEFCONFIG"

    # Enable KernelSU
    ./scripts/config --file out/.config -e KSU
    ./scripts/config --file out/.config -e KSU_SUSFS
    ./scripts/config --file out/.config -e KSU_SUSFS_SUS_PATH
    ./scripts/config --file out/.config -e KSU_SUSFS_SUS_MOUNT
    ./scripts/config --file out/.config -e KSU_SUSFS_SUS_KSTAT
    ./scripts/config --file out/.config -e KSU_SUSFS_TRY_UMOUNT
    ./scripts/config --file out/.config -e KSU_SUSFS_SPOOF_UNAME
    ./scripts/config --file out/.config -e KSU_SUSFS_ENABLE_LOG
    ./scripts/config --file out/.config -e KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS

    cd ..
}

# Build kernel
build_kernel() {
    log "Building kernel..."
    cd kernel_source

    # Get CPU count
    CPUS=$(nproc --all)

    make -j"$CPUS" O=out ARCH=arm64 CC=clang \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-android- \
        CROSS_COMPILE_ARM32=arm-linux-androideabi- \
        NM=llvm-nm \
        OBJDUMP=llvm-objdump \
        STRIP=llvm-strip \
        2>&1 | tee build.log

    cd ..
}

# Package kernel with AnyKernel3
package_kernel() {
    log "Packaging kernel..."
    cd kernel_source

    # Check if kernel was built successfully
    if [ ! -f "out/arch/arm64/boot/Image" ]; then
        error "Kernel image not found! Build may have failed."
    fi

    # Clone AnyKernel3
    if [ ! -d "AnyKernel3" ]; then
        git clone --depth=1 https://github.com/osm0sis/AnyKernel3.git
    fi

    # Clean and prepare AnyKernel3
    cd AnyKernel3
    rm -rf .git modules patch ramdisk

    # Copy kernel image
    cp ../out/arch/arm64/boot/Image .

    # Copy DTB if exists
    if [ -f "../out/arch/arm64/boot/dtb" ]; then
        cp ../out/arch/arm64/boot/dtb .
    fi

    # Copy DTBO if exists
    if [ -f "../out/arch/arm64/boot/dtbo.img" ]; then
        cp ../out/arch/arm64/boot/dtbo.img .
    fi

    # Update anykernel.sh for OnePlus 8 series
    cat > anykernel.sh << 'EOF'
# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers

properties() { '
kernel.string=KernelSU-SUSFS Kernel for OnePlus 8 Series
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=instantnoodle
device.name2=instantnoodlep
device.name3=kebab
device.name4=lemonades
device.name5=OnePlus8
device.name6=OnePlus8Pro
device.name7=OnePlus8T
device.name8=OnePlus9R
supported.versions=11-15
supported.patchlevels=
'; }

block=/dev/block/bootdevice/by-name/boot;
is_slot_device=1;
ramdisk_compression=auto;

. tools/ak3-core.sh;

set_perm_recursive 0 0 755 644 $ramdisk/*;
set_perm_recursive 0 0 750 750 $ramdisk/init* $ramdisk/sbin;

dump_boot;
write_boot;
EOF

    # Create flashable zip
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    ZIP_NAME="KernelSU-SUSFS_${DEVICE_NAME}_${TIMESTAMP}.zip"
    zip -r9 "../out/$ZIP_NAME" * -x .git README.md *placeholder

    log "Created: out/$ZIP_NAME"
    cd ../..

    # Copy to output
    mkdir -p /output
    cp kernel_source/out/*.zip /output/ 2>/dev/null || true
    cp kernel_source/out/arch/arm64/boot/Image /output/ 2>/dev/null || true
}

# Main
main() {
    log "=== OnePlus SM8250 Kernel Build with KernelSU-Next + SUSFS ==="
    log "Kernel Source: $KERNEL_SOURCE"
    log "Branch: $KERNEL_BRANCH"
    log "Defconfig: $DEFCONFIG"

    clone_kernel
    setup_kernelsu
    apply_susfs
    configure_kernel
    build_kernel
    package_kernel

    log "=== Build Complete! ==="
    log "Output files are in /output directory"
}

main "$@"
