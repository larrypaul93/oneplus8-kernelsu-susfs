FROM ubuntu:22.04

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
    lib32ncurses5-dev \
    lib32readline-dev \
    lib32z1-dev \
    liblz4-tool \
    libncurses5-dev \
    libsdl1.2-dev \
    libssl-dev \
    libwxgtk3.0-gtk3-dev \
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
    pahole \
    device-tree-compiler \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /kernel

# Download and extract Clang toolchain
RUN mkdir -p /toolchains/clang && \
    curl -sL "https://github.com/ZyCromerZ/Clang/releases/download/10.0.1-20220724-release/Clang-10.0.1-20220724.tar.gz" | \
    tar -xzf - -C /toolchains/clang

# Download GCC toolchains
RUN git clone --depth=1 -b android12L-release \
    https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/aarch64/aarch64-linux-android-4.9 \
    /toolchains/gcc64

RUN git clone --depth=1 -b android12L-release \
    https://android.googlesource.com/platform/prebuilts/gcc/linux-x86/arm/arm-linux-androideabi-4.9 \
    /toolchains/gcc32

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
