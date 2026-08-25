#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/output"
BUILDROOT_VERSION="2025.02.2"
BUILDROOT_DIR="$ROOT_DIR/buildroot/source"

mkdir -p "$OUTPUT_DIR"

prepare_buildroot() {
    if [[ ! -d "$BUILDROOT_DIR" ]]; then
        mkdir -p "$ROOT_DIR/buildroot"
        curl -L "https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.xz" -o "$ROOT_DIR/buildroot.tar.xz"
        tar -xf "$ROOT_DIR/buildroot.tar.xz" -C "$ROOT_DIR/buildroot"
        mv "$ROOT_DIR/buildroot/buildroot-${BUILDROOT_VERSION}" "$BUILDROOT_DIR"
    fi
}

build_rootfs() {
    prepare_buildroot
    echo "Buildroot rootfs stage prepared"
    # External tree integration is added in the next hardware enablement stage.
}

build_kernel() {
    echo "Kernel build stage prepared"
    # Linux source checkout and rx1950 defconfig integration are added here.
}

build_image() {
    mkdir -p "$OUTPUT_DIR"
    truncate -s 64M "$OUTPUT_DIR/rx1950-linux.img"
    echo "SD image assembly stage prepared"
}

case "${1:-all}" in
    rootfs) build_rootfs ;;
    kernel) build_kernel ;;
    image) build_image ;;
    all) build_rootfs; build_kernel; build_image ;;
    *) echo "Usage: $0 {rootfs|kernel|image|all}" >&2; exit 1 ;;
esac
