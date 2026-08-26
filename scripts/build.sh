#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly OUTPUT_DIR="${ROOT_DIR}/output"
readonly DOWNLOAD_DIR="${ROOT_DIR}/dl"
readonly BUILD_DIR="${ROOT_DIR}/.build"
readonly BUILDROOT_VERSION="2025.02.2"
readonly BUILDROOT_SHA256="4a74e9a6f82ef8660ae2ef865d0ad61a4e9ccd67e2aeef885cae1165581ed5ac"
readonly KERNEL_VERSION="6.2"
readonly KERNEL_SHA256="74862fa8ab40edae85bb3385c0b71fe103288bce518526d63197800b3cbdecb1"
readonly HARET_VERSION="2011-06-07-rx1950"
readonly HARET_SHA256="5831d7cc8aba6ebd08709893101deca9da78e38ecde519a57adedfb164c86902"
readonly KERNEL_OFFSET=0x1000000
readonly KERNEL_ZRELADDR=0x8000
readonly CROSS_COMPILE="${CROSS_COMPILE:-arm-linux-gnueabi-}"

mkdir -p "${OUTPUT_DIR}" "${DOWNLOAD_DIR}" "${BUILD_DIR}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }
sha256() { printf '%s  %s\n' "$2" "$1" | sha256sum --check --status; }

download() {
    local url="$1" destination="$2" expected="$3"
    if [[ ! -f "${destination}" ]] || ! sha256 "${destination}" "${expected}"; then
        rm -f "${destination}"
        curl --fail --location --retry 3 --proto '=https' --tlsv1.2 "${url}" --output "${destination}"
    fi
    sha256 "${destination}" "${expected}" || die "checksum mismatch for ${destination}"
}

prepare_buildroot() {
    local archive="${DOWNLOAD_DIR}/buildroot-${BUILDROOT_VERSION}.tar.xz"
    local source="${BUILD_DIR}/buildroot-${BUILDROOT_VERSION}"
    download "https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.xz" "${archive}" "${BUILDROOT_SHA256}"
    if [[ ! -d "${source}" ]]; then
        tar --extract --file "${archive}" --directory "${BUILD_DIR}"
    fi
    printf '%s\n' "${source}"
}

prepare_kernel() {
    local archive="${DOWNLOAD_DIR}/linux-${KERNEL_VERSION}.tar.xz"
    local source="${BUILD_DIR}/linux-${KERNEL_VERSION}"
    download "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz" "${archive}" "${KERNEL_SHA256}"
    if [[ ! -d "${source}" ]]; then
        tar --extract --file "${archive}" --directory "${BUILD_DIR}"
    fi
    printf '%s\n' "${source}"
}

apply_kernel_patches() {
    local source="$1" patch_file
    require patch
    for patch_file in "${ROOT_DIR}"/kernel/patches/*.patch; do
        [[ -e "${patch_file}" ]] || continue
        if patch --directory="${source}" --strip=1 --dry-run --forward --batch < "${patch_file}"; then
            patch --directory="${source}" --strip=1 --forward --batch < "${patch_file}"
        elif patch --directory="${source}" --strip=1 --dry-run --reverse --batch < "${patch_file}"; then
            : # The source tree is already patched from a previous local build.
        else
            die "cannot apply kernel patch ${patch_file}"
        fi
    done
}

build_rootfs() {
    require make
    chmod +x "${ROOT_DIR}/buildroot/external/rx1950/board/hp_rx1950/post-build.sh"
    local source
    source="$(prepare_buildroot)"
    local out="${BUILD_DIR}/buildroot-output"
    mkdir -p "${out}"
    make -C "${source}" O="${out}" BR2_EXTERNAL="${ROOT_DIR}/buildroot/external/rx1950" rx1950_defconfig
    make -C "${source}" O="${out}" -j"$(nproc)"
    cp "${out}/images/rootfs.ext2" "${OUTPUT_DIR}/rootfs.ext2"
    cp "${out}/.config" "${OUTPUT_DIR}/buildroot.config"
}

build_kernel() {
    require make
    require "${CROSS_COMPILE}gcc"
    local source
    source="$(prepare_kernel)"
    apply_kernel_patches "${source}"
    local out="${BUILD_DIR}/kernel-output"
    rm -rf "${out}"
    mkdir -p "${out}"
    cp "${ROOT_DIR}/kernel/rx1950_defconfig" "${out}/.config"
    sed -i \
        -e 's|^CONFIG_CMDLINE=.*|CONFIG_CMDLINE="root=/dev/mmcblk0p2 rootwait rw console=ttySAC0,115200n8 console=tty0 loglevel=8 ignore_loglevel consoleblank=0 printk.time=1"|' \
        -e '/^CONFIG_CMDLINE_FORCE=/d' \
        "${out}/.config"
    printf '%s\n' 'CONFIG_CMDLINE_FORCE=y' >> "${out}/.config"
    make -C "${source}" O="${out}" ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" olddefconfig
    make -C "${source}" O="${out}" ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" -j"$(nproc)" zImage
    cp "${out}/arch/arm/boot/zImage" "${OUTPUT_DIR}/zImage"
    cp "${out}/.config" "${OUTPUT_DIR}/kernel.config"
}

prepare_haret() {
    # This RX1950-specific binary is the historically deployed loader for
    # the device.  It reaches the target from locked stock WM 6.1 systems,
    # unlike binaries built with contemporary Windows CE toolchains.
    local binary="${DOWNLOAD_DIR}/haret-${HARET_VERSION}.exe"
    download "https://downloads.tuxfamily.org/linuxrx1950/bootloader/haret-7jun2011.exe" \
        "${binary}" "${HARET_SHA256}"
    printf '%s\n' "${binary}"
}

validate_zimage_placement() {
    # HaRET places zImage at RAMADDR + KERNEL_OFFSET.  The ARM decompressor
    # writes the inflated Image from RAMADDR + 0x8000 upwards.  The historical
    # 5 MiB RX1950 offset was adequate for 2.6-era kernels, but a current
    # kernel can overwrite unread compressed input before the first board
    # callback runs.  Check the actual payload rather than relying on a
    # version-specific estimate.
    require grep; require gzip; require tail; require wc
    local image="$1" gzip_offset inflated_size available
    gzip_offset="$(LC_ALL=C grep --text --byte-offset --only-matching $'\x1f\x8b\x08' "${image}" | head --lines=1 | cut --delimiter=: --fields=1)"
    [[ "${gzip_offset}" =~ ^[0-9]+$ ]] || die "cannot locate gzip payload in ${image}"
    # zImage appends an ARM boot trailer after the gzip member. GNU gzip
    # reports that trailer with status 2 even though it has emitted the full
    # decompressed kernel, so count the stream with pipefail disabled here.
    inflated_size="$(
        set +o pipefail
        tail --bytes="+$((gzip_offset + 1))" "${image}" | gzip --decompress --stdout 2>/dev/null | wc --bytes
    )"
    available=$((KERNEL_OFFSET - KERNEL_ZRELADDR))
    (( inflated_size > 0 )) || die "cannot read compressed kernel payload"
    (( inflated_size < available )) || die "zImage expands to ${inflated_size} bytes, exceeding the ${available}-byte safe decompression window"
}

assemble_image() {
    require dd; require parted; require mkfs.vfat; require mcopy; require debugfs; require e2fsck; require sha256sum; require xz
    [[ -f "${OUTPUT_DIR}/zImage" ]] || die "kernel artifact is not available"
    [[ -f "${OUTPUT_DIR}/rootfs.ext2" ]] || die "root filesystem artifact is not available"
    validate_zimage_placement "${OUTPUT_DIR}/zImage"

    local haret bootfs image root_start rootfs_size image_size
    haret="$(prepare_haret)"
    bootfs="${OUTPUT_DIR}/boot.fat"
    image="${OUTPUT_DIR}/rx1950-linux-sd.img"
    root_start=34816

    rm -f "${bootfs}" "${image}"
    truncate --size 16M "${bootfs}"
    mkfs.vfat -F 16 -n RX1950BOOT "${bootfs}"
    mcopy -i "${bootfs}" "${haret}" ::haret.exe
    mcopy -i "${bootfs}" "${ROOT_DIR}/board/hp_rx1950/startup.txt" ::startup.txt
    mcopy -i "${bootfs}" "${OUTPUT_DIR}/zImage" ::zImage
    mcopy -i "${bootfs}" "${ROOT_DIR}/board/hp_rx1950/README.txt" ::README.txt

    e2fsck -fp "${OUTPUT_DIR}/rootfs.ext2"

    rootfs_size="$(stat --format='%s' "${OUTPUT_DIR}/rootfs.ext2")"
    test $((rootfs_size % 512)) -eq 0 || die "root filesystem is not sector-aligned"
    image_size=$((root_start * 512 + rootfs_size))
    rm -f "${image}.xz"
    truncate --size "${image_size}" "${image}"
    parted --script "${image}" mklabel msdos mkpart primary fat16 1MiB 17MiB mkpart primary ext4 17MiB 100% set 1 boot on
    dd if="${bootfs}" of="${image}" bs=512 seek=2048 conv=notrunc status=none
    dd if="${OUTPUT_DIR}/rootfs.ext2" of="${image}" bs=512 seek="${root_start}" conv=notrunc status=none
    xz --keep --force --threads=0 --check=crc32 "${image}"
    (
        cd "${OUTPUT_DIR}"
        sha256sum rx1950-linux-sd.img rx1950-linux-sd.img.xz > SHA256SUMS
    )
    {
        printf 'build=%s\n' "${BUILD_ID:-local}"
        printf 'buildroot=%s\n' "${BUILDROOT_VERSION}"
        printf 'kernel=%s\n' "${KERNEL_VERSION}"
        printf 'haret-version=%s\n' "${HARET_VERSION}"
        printf 'haret-sha256=%s\n' "${HARET_SHA256}"
        printf 'rootfs=ext4\n'
        printf 'profile=boot-probe\n'
        printf 'seed-image-bytes=%s\n' "${image_size}"
    } > "${OUTPUT_DIR}/provenance.txt"
}

case "${1:-all}" in
    rootfs) build_rootfs ;;
    kernel) build_kernel ;;
    image) assemble_image ;;
    all) build_rootfs; build_kernel; assemble_image ;;
    *) die "usage: $0 {rootfs|kernel|image|all}" ;;
esac
