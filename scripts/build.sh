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
    mkdir -p "$OUTPUT_DIR/rootfs"
    printf 'rx1950 rootfs build stage\n' > "$OUTPUT_DIR/rootfs/README"
    tar -czf "$OUTPUT_DIR/rootfs.tar.gz" -C "$OUTPUT_DIR" rootfs
}

build_kernel() {
    mkdir -p "$OUTPUT_DIR/kernel"
    printf 'rx1950 kernel build stage\n' > "$OUTPUT_DIR/kernel/zImage"
    tar -czf "$OUTPUT_DIR/kernel.tar.gz" -C "$OUTPUT_DIR" kernel
}

assemble_image() {
    mkdir -p "$OUTPUT_DIR/image"
    truncate -s 128M "$OUTPUT_DIR/rx1950-linux.img"
}

case "${1:-all}" in
    rootfs) build_rootfs ;;
    kernel) build_kernel ;;
    image) assemble_image ;;
    all)
        build_rootfs
        build_kernel
        assemble_image
        ;;
    *)
        echo "Usage: $0 {rootfs|kernel|image|all}" >&2
        exit 1
        ;;
esac
