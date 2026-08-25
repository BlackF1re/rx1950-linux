#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="${ROOT_DIR}/output"
BUILDROOT_VERSION="2025.02.2"
BUILDROOT_DIR="${ROOT_DIR}/buildroot/source"
EXTERNAL_TREE="${ROOT_DIR}/buildroot/external/rx1950"

mkdir -p "${OUTPUT_DIR}"

prepare_buildroot() {
    mkdir -p "${ROOT_DIR}/buildroot"

    if [[ ! -d "${BUILDROOT_DIR}" ]]; then
        curl -fsSL "https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.xz" \
            -o "${ROOT_DIR}/buildroot.tar.xz"
        tar -xf "${ROOT_DIR}/buildroot.tar.xz" -C "${ROOT_DIR}/buildroot"
        mv "${ROOT_DIR}/buildroot/buildroot-${BUILDROOT_VERSION}" "${BUILDROOT_DIR}"
    fi
}

build_rootfs() {
    prepare_buildroot

    if [[ ! -f "${EXTERNAL_TREE}/configs/rx1950_defconfig" ]]; then
        echo "Missing rx1950 Buildroot configuration" >&2
        exit 1
    fi

    echo "Buildroot rootfs stage ready"
}

build_kernel() {
    if [[ ! -f "${ROOT_DIR}/kernel/rx1950/defconfig" ]]; then
        echo "Missing rx1950 kernel configuration" >&2
        exit 1
    fi

    echo "Kernel stage ready"
}

assemble_image() {
    mkdir -p "${OUTPUT_DIR}/image"

    if [[ ! -f "${OUTPUT_DIR}/zImage" ]]; then
        echo "Kernel image is not available" >&2
        exit 1
    fi

    if [[ ! -d "${OUTPUT_DIR}/rootfs" ]]; then
        echo "Root filesystem is not available" >&2
        exit 1
    fi

    echo "SD image assembly stage ready"
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
