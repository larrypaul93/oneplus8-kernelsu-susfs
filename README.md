# OnePlus 8 Series Kernel Builder

Build KernelSU + SUSFS kernel for OnePlus 8 series devices using GitHub Actions.

## Supported Devices

- OnePlus 8 (instantnoodle)
- OnePlus 8 Pro (instantnoodlep)
- OnePlus 8T (kebab)
- OnePlus 9R (lemonades)

## Features

- **KernelSU Variants:**
  - KernelSU-Next
  - rsuntk KernelSU
  - SukiSU-Ultra
  - WildKernelSU

- **SUSFS Support:** Root hiding with SUSFS v2.0.0

## Usage

### Method 1: GitHub Actions (Recommended)

1. Fork this repository
2. Go to **Actions** tab
3. Select **Build OnePlus 8 Kernel with KernelSU-Next + SUSFS**
4. Click **Run workflow**
5. Configure options:
   - Kernel source repo
   - Kernel branch
   - KernelSU variant
   - Enable/disable SUSFS
6. Wait for build to complete
7. Download from **Releases** or **Artifacts**

### Method 2: Local Build with Docker

```bash
# Build Docker image
docker build -t kernel-builder .

# Run build
docker run -v $(pwd)/output:/output kernel-builder
```

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| `kernel_source` | HELLBOY017/kernel_oneplus_sm8250 | Kernel source repo |
| `kernel_branch` | thirteen | Branch to build |
| `kernelsu_variant` | next | KernelSU variant |
| `susfs_enabled` | true | Enable SUSFS |

## Installation

### Via Recovery (TWRP)

1. Boot into TWRP recovery
2. Flash the AnyKernel3 zip
3. Reboot

### Via Fastboot

```bash
# Extract Image from zip, then:
fastboot flash boot Image
# Or if you have boot.img:
fastboot flash boot boot.img
```

## Credits

- [HELLBOY017](https://github.com/HELLBOY017) - Meteoric Kernel
- [KernelSU-Next](https://github.com/KernelSU-Next/KernelSU-Next)
- [SUSFS](https://gitlab.com/simonpunk/susfs4ksu)
- [JackA1ltman](https://github.com/JackA1ltman/NonGKI_Kernel_Build_2nd) - Build references

## License

GPL-2.0
