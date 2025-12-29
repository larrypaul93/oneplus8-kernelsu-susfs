# Use x86_64 platform as toolchains are compiled for x86_64
FROM --platform=linux/amd64 ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install build dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    wget \
    bc \
    bison \
    build-essential \
    ccache \
    flex \
    g++-multilib \
    gcc-multilib \
    gnupg \
    gperf \
    imagemagick \
    lib32ncurses-dev \
    lib32z1-dev \
    liblz4-tool \
    libncurses-dev \
    libssl-dev \
    libxml2 \
    libxml2-utils \
    lzop \
    pngcrush \
    rsync \
    schedtool \
    squashfs-tools \
    xsltproc \
    zip \
    zlib1g-dev \
    python3 \
    python3-pip \
    cpio \
    kmod \
    libelf-dev \
    device-tree-compiler \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /kernel

# Download and extract Clang toolchain (using Clang 14 for better kernel 4.19 compatibility)
RUN mkdir -p /toolchains/clang && \
    curl -sL "https://github.com/ZyCromerZ/Clang/releases/download/14.0.6-20250704-release/Clang-14.0.6-20250704.tar.gz" | \
    tar -xzf - -C /toolchains/clang

# Download GCC toolchains
RUN git clone --depth=1 -b android12L-release \
    https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 \
    /toolchains/gcc64

RUN git clone --depth=1 -b android12L-release \
    https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9 \
    /toolchains/gcc32

# Create wrapper scripts for GCC (needed for kernel version detection scripts)
# The kernel scripts check gcc versions even when using clang as the main compiler
RUN echo '#!/bin/bash\nexec gcc "$@"' > /toolchains/gcc64/bin/aarch64-linux-android-gcc && \
    chmod +x /toolchains/gcc64/bin/aarch64-linux-android-gcc && \
    echo '#!/bin/bash\nexec gcc "$@"' > /toolchains/gcc32/bin/arm-linux-androideabi-gcc && \
    chmod +x /toolchains/gcc32/bin/arm-linux-androideabi-gcc

# Set up environment
ENV PATH="/toolchains/clang/bin:/toolchains/gcc64/bin:/toolchains/gcc32/bin:${PATH}"
ENV CROSS_COMPILE="aarch64-linux-android-"
ENV CROSS_COMPILE_ARM32="arm-linux-androideabi-"
ENV CC="clang"
ENV CLANG_TRIPLE="aarch64-linux-gnu-"

# Copy build script
COPY build.sh /kernel/build.sh
RUN chmod +x /kernel/build.sh

ENTRYPOINT ["/kernel/build.sh"]
