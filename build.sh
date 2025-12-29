#!/bin/bash
set -e

# Configuration - can be overridden via environment variables
KERNEL_SOURCE="${KERNEL_SOURCE:-https://github.com/JackA1ltman/android_kernel_oneplus_sm8250_los_noksu.git}"
KERNEL_BRANCH="${KERNEL_BRANCH:-staging}"
DEFCONFIG="${DEFCONFIG:-vendor/kona-perf_defconfig}"
DEVICE_NAME="${DEVICE_NAME:-OnePlus8_Series}"
KERNELSU_VARIANT="${KERNELSU_VARIANT:-ksu}"
SUSFS_ENABLED="${SUSFS_ENABLED:-true}"
PATCHES_REPO="${PATCHES_REPO:-JackA1ltman/NonGKI_Kernel_Patches}"
PATCHES_BRANCH="${PATCHES_BRANCH:-op_kernel}"

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

# Clone patches repo
clone_patches() {
    log "Cloning patches repo..."
    if [ ! -d "patches" ]; then
        git clone --depth=1 -b "$PATCHES_BRANCH" "https://github.com/$PATCHES_REPO.git" patches
    fi
}

# Setup KernelSU based on variant
setup_kernelsu() {
    log "Setting up KernelSU (variant: $KERNELSU_VARIANT)..."
    cd kernel_source

    case "$KERNELSU_VARIANT" in
        ksu)
            log "Setting up original KernelSU (tiann)..."
            curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -
            ;;
        sukisu)
            log "Setting up SukiSU-Ultra..."
            curl -LSs "https://raw.githubusercontent.com/ShirkNeko/SukiSU-Ultra/main/kernel/setup.sh" | bash -s main
            ;;
        next)
            log "Setting up KernelSU-Next (legacy)..."
            curl -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/legacy/kernel/setup.sh" | bash -s legacy
            ;;
        rsuntk)
            log "Setting up rsuntk KernelSU..."
            curl -LSs "https://raw.githubusercontent.com/rsuntk/KernelSU/main/kernel/setup.sh" | bash -s main
            ;;
        *)
            error "Unknown KernelSU variant: $KERNELSU_VARIANT"
            ;;
    esac

    cd ..
}

# Apply SUSFS patches following official instructions
apply_susfs() {
    if [ "$SUSFS_ENABLED" != "true" ]; then
        log "SUSFS disabled, skipping..."
        return
    fi

    log "Applying SUSFS patches..."
    cd kernel_source

    # Find KernelSU directory
    KSU_DIR=$(find . -maxdepth 1 -type d -name "KernelSU*" | head -1)
    log "KernelSU directory: $KSU_DIR"

    # Clone susfs4ksu for kernel patches (kernel-4.19 branch)
    log "Cloning susfs4ksu (kernel-4.19 branch)..."
    git clone --depth=1 https://gitlab.com/simonpunk/susfs4ksu.git -b kernel-4.19 susfs4ksu || \
    git clone --depth=1 https://github.com/sidex15/susfs4ksu.git -b kernel-4.19 susfs4ksu

    # Step 1: Apply revert commit in KernelSU (as per official instructions)
    log "Step 1: Reverting kprobe commit in KernelSU..."
    if [ -n "$KSU_DIR" ] && [ -d "$KSU_DIR" ]; then
        cd "$KSU_DIR"
        git revert --no-commit 898e9d4f8ca9b2f46b0c6b36b80a872b5b88d899 2>/dev/null || log "Revert may not be needed for this version"
        cd ..
    fi

    # Step 2: Disable kprobes in KernelSU (replace #ifdef CONFIG_KPROBES with #if defined(CONFIG_KPROBES) && 0)
    log "Step 2: Disabling kprobes in KernelSU..."
    if [ -n "$KSU_DIR" ] && [ -d "$KSU_DIR" ]; then
        find "$KSU_DIR" -name "*.c" -o -name "*.h" | xargs sed -i 's/#ifdef CONFIG_KPROBES/#if defined(CONFIG_KPROBES) \&\& 0/g' 2>/dev/null || true
        find "$KSU_DIR" -name "*.c" -o -name "*.h" | xargs sed -i 's/#if defined(CONFIG_KPROBES)/#if defined(CONFIG_KPROBES) \&\& 0/g' 2>/dev/null || true
    fi

    # Step 3: Copy SUSFS patch to KernelSU folder and apply
    log "Step 3: Copying and applying SUSFS KernelSU patch..."
    if [ -f "susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch" ]; then
        cp susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch "$KSU_DIR/"
        cd "$KSU_DIR"
        patch -p1 < 10_enable_susfs_for_ksu.patch || log "KernelSU SUSFS patch may need adjustment"
        cd ..
    fi

    # Step 4: Copy SUSFS source files to kernel
    log "Step 4: Copying SUSFS source files..."
    cp -v susfs4ksu/kernel_patches/fs/* fs/ 2>/dev/null || true
    cp -v susfs4ksu/kernel_patches/include/linux/* include/linux/ 2>/dev/null || true

    # Step 5: Copy and apply kernel SUSFS patch
    log "Step 5: Applying kernel SUSFS patch..."
    cp susfs4ksu/kernel_patches/50_add_susfs_in_kernel-4.19.patch ./
    patch -p1 < 50_add_susfs_in_kernel-4.19.patch || log "Kernel SUSFS patch may need manual adjustment"

    # Step 6: Apply device-specific fixes if available
    if [ -f "../patches/kona_cos15_a15/susfs_fixed.patch" ]; then
        log "Step 6: Applying device-specific SUSFS fixes..."
        patch -p1 < ../patches/kona_cos15_a15/susfs_fixed.patch || log "Device patch may already be applied"
    fi

    cd ..
}

# Apply VFS hook patches
apply_vfs_patches() {
    log "Applying VFS hook patches..."
    cd kernel_source
    if [ -f "../patches/vfs_hook_patches.sh" ]; then
        bash ../patches/vfs_hook_patches.sh || log "VFS patches may already be applied"
    fi
    cd ..
}

# Configure kernel
configure_kernel() {
    log "Configuring kernel..."
    cd kernel_source

    make O=out ARCH=arm64 CC=clang \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-android- \
        CROSS_COMPILE_ARM32=arm-linux-androideabi- \
        "$DEFCONFIG"

    # Enable KernelSU
    ./scripts/config --file out/.config -e KSU

    # Enable SUSFS if enabled
    if [ "$SUSFS_ENABLED" = "true" ]; then
        ./scripts/config --file out/.config -e KSU_SUSFS || true
        ./scripts/config --file out/.config -e KSU_SUSFS_SUS_PATH || true
        ./scripts/config --file out/.config -e KSU_SUSFS_SUS_MOUNT || true
        ./scripts/config --file out/.config -e KSU_SUSFS_SUS_KSTAT || true
        ./scripts/config --file out/.config -e KSU_SUSFS_TRY_UMOUNT || true
        ./scripts/config --file out/.config -e KSU_SUSFS_SPOOF_UNAME || true
        ./scripts/config --file out/.config -e KSU_SUSFS_ENABLE_LOG || true
        ./scripts/config --file out/.config -e KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS || true
    fi

    # Regenerate config
    make O=out ARCH=arm64 olddefconfig

    cd ..
}

# Build kernel
build_kernel() {
    log "Building kernel..."
    cd kernel_source

    # Get CPU count
    CPUS=$(nproc --all)

    # Use 'yes ""' to auto-accept default for any config prompts
    # LLVM_IAS=0 to use GCC assembler instead of Clang's integrated assembler (vDSO compatibility)
    yes "" | make -j"$CPUS" O=out ARCH=arm64 CC=clang \
        CLANG_TRIPLE=aarch64-linux-gnu- \
        CROSS_COMPILE=aarch64-linux-android- \
        CROSS_COMPILE_ARM32=arm-linux-androideabi- \
        LLVM_IAS=0 \
        NM=llvm-nm \
        OBJDUMP=llvm-objdump \
        STRIP=llvm-strip \
        2>&1 | tee build.log

    cd ..
}

# Check build result
check_build() {
    cd kernel_source
    if [ ! -f "out/arch/arm64/boot/Image" ]; then
        error "Kernel image not found! Build failed."
    fi
    log "Kernel built successfully!"
    ls -la out/arch/arm64/boot/
    cd ..
}

# Package kernel with AnyKernel3
package_kernel() {
    log "Packaging kernel..."
    cd kernel_source

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
    [ -f "../out/arch/arm64/boot/dtb" ] && cp ../out/arch/arm64/boot/dtb .

    # Copy DTBO if exists
    [ -f "../out/arch/arm64/boot/dtbo.img" ] && cp ../out/arch/arm64/boot/dtbo.img .

    # Configure anykernel.sh for OnePlus 8 series
    sed -i "s/do.devicecheck=.*/do.devicecheck=1/g" anykernel.sh
    sed -i "s/do.modules=.*/do.modules=0/g" anykernel.sh
    sed -i "s/device.name1=.*/device.name1=instantnoodle/g" anykernel.sh
    sed -i "s/device.name2=.*/device.name2=instantnoodlep/g" anykernel.sh
    sed -i "s|block=.*|block=/dev/block/bootdevice/by-name/boot;|g" anykernel.sh
    sed -i "s/is_slot_device=.*/is_slot_device=1;/g" anykernel.sh

    # Create flashable zip
    TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    SUSFS_TAG=""
    [ "$SUSFS_ENABLED" = "true" ] && SUSFS_TAG="_SUSFS"
    ZIP_NAME="KernelSU-${KERNELSU_VARIANT}${SUSFS_TAG}_${DEVICE_NAME}_${TIMESTAMP}.zip"
    zip -r9 "/output/$ZIP_NAME" * -x .git README.md *placeholder

    log "Created: /output/$ZIP_NAME"
    cd ../..

    # Copy kernel image to output
    cp kernel_source/out/arch/arm64/boot/Image /output/ 2>/dev/null || true
}

# Main
main() {
    log "=== OnePlus SM8250 Kernel Build with KernelSU + SUSFS ==="
    log "Kernel Source: $KERNEL_SOURCE"
    log "Branch: $KERNEL_BRANCH"
    log "Defconfig: $DEFCONFIG"
    log "KernelSU Variant: $KERNELSU_VARIANT"
    log "SUSFS Enabled: $SUSFS_ENABLED"
    log ""

    clone_kernel
    clone_patches
    setup_kernelsu
    apply_susfs
    apply_vfs_patches
    configure_kernel
    build_kernel
    check_build
    package_kernel

    log "=== Build Complete! ==="
    log "Output files are in /output directory"
}

main "$@"
