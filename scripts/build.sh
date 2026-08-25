#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/output"
BUILDROOT_VERSION="2025.02.2"

mkdir -p "$OUTPUT_DIR"

if [ ! -d "$ROOT_DIR/buildroot/source" ]; then
    mkdir -p "$ROOT_DIR/buildroot"
    wget -q "https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.xz" \
        -O "$ROOT_DIR/buildroot.tar.xz"
    tar -xf "$ROOT_DIR/buildroot.tar.xz" -C "$ROOT_DIR/buildroot"
    mv "$ROOT_DIR/buildroot/buildroot-${BUILDROOT_VERSION}" "$ROOT_DIR/buildroot/source"
fi

# Buildroot integration point. The final configuration will provide:
# - ARM920T toolchain
# - rx1950 kernel
# - root filesystem
# - SD image generation

truncate -s 64M "$OUTPUT_DIR/rx1950-linux.img"

echo "rx1950-linux image placeholder generated"
