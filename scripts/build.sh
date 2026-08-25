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
readonly HARET_REVISION="5f82ea95423126097cbfa95bc33841f33c171741"
readonly HARET_TOOLCHAIN_SHA256="dd7e08204330323fb392b83aeb16abdf9d165eeebd9bcb93dc7f9560b8027470"
readonly GMP_VERSION="4.3.2"
readonly GMP_SHA256="936162c0312886c21581002b79932829aa048cfaf9937c6265aeaa14f1cd1775"
readonly MPFR_VERSION="2.4.2"
readonly MPFR_SHA256="c7e75a08a8d49d2082e4caee1591a05d11b9d5627514e678f02d66a124bcf2ba"
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
    # This function returns only the executable path through stdout.  HaRET's
    # legacy configure and make tools are verbose, so route their diagnostics
    # to stderr before the result is captured by assemble_image().
    exec 3>&1
    exec 1>&2
    require make
    require python3
    require tar
    require git
    require gcc

    local toolchain_archive="${DOWNLOAD_DIR}/mingw32ce-0.59.1.tar.bz2"
    local gmp_archive="${DOWNLOAD_DIR}/gmp-${GMP_VERSION}.tar.bz2"
    local mpfr_archive="${DOWNLOAD_DIR}/mpfr-${MPFR_VERSION}.tar.bz2"
    local source="${BUILD_DIR}/haret-${HARET_REVISION}"
    local toolchain="${BUILD_DIR}/mingw32ce-0.59.1"
    local gmp_source="${BUILD_DIR}/gmp-${GMP_VERSION}"
    local gmp_prefix="${BUILD_DIR}/gmp-${GMP_VERSION}-runtime"
    local mpfr_source="${BUILD_DIR}/mpfr-${MPFR_VERSION}"
    local mpfr_prefix="${BUILD_DIR}/mpfr-${MPFR_VERSION}-runtime"
    local binary="${source}/out/haret.exe"

    download "https://sourceforge.net/projects/cegcc/files/cegcc/0.59.1/mingw32ce-0.59.1.tar.bz2/download" \
        "${toolchain_archive}" "${HARET_TOOLCHAIN_SHA256}"
    download "https://ftp.gnu.org/gnu/gmp/gmp-${GMP_VERSION}.tar.bz2" \
        "${gmp_archive}" "${GMP_SHA256}"
    download "https://www.mpfr.org/mpfr-${MPFR_VERSION}/mpfr-${MPFR_VERSION}.tar.bz2" \
        "${mpfr_archive}" "${MPFR_SHA256}"

    if [[ ! -d "${source}" ]]; then
        git init --quiet "${source}"
        git -C "${source}" remote add origin https://github.com/KevinOConnor/haret.git
        git -C "${source}" fetch --quiet --depth 1 origin "${HARET_REVISION}"
        git -C "${source}" checkout --quiet --detach FETCH_HEAD
    fi
    [[ "$(git -C "${source}" rev-parse HEAD)" == "${HARET_REVISION}" ]] || die "unexpected HaRET source revision"
    # Modern GNU as rejects HaRET's SWP operands when gcc allocates the
    # result register over the address register.  The output is written
    # before all inputs are consumed, so it must be marked early-clobber.
    # This is an assembly-constraint correction, not a behavioural change.
    python3 - "${source}/src/l1trace.cpp" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text()
old = ': "=r" (readval)'
new = ': "=&r" (readval)'
if old in text:
    if text.count(old) != 2:
        raise SystemExit("unexpected HaRET SWP constraint count")
    path.write_text(text.replace(old, new))
elif text.count(new) != 2:
    raise SystemExit("HaRET SWP constraints are not patched as expected")
PY
    if [[ ! -d "${toolchain}/opt/mingw32ce" ]]; then
        rm -rf "${toolchain}"
        mkdir -p "${toolchain}"
        tar --extract --bzip2 --file "${toolchain_archive}" --directory "${toolchain}"
    fi
    if [[ ! -f "${gmp_prefix}/lib/libgmp.so.3" ]] || [[ ! -f "${mpfr_prefix}/lib/libmpfr.so.1" ]]; then
        rm -rf "${gmp_source}" "${gmp_prefix}" "${mpfr_source}" "${mpfr_prefix}"
        tar --extract --bzip2 --file "${gmp_archive}" --directory "${BUILD_DIR}"
        (
            cd "${gmp_source}"
            CC=gcc CFLAGS=-m32 ABI=32 ./configure --prefix="${gmp_prefix}" --disable-static || die "cannot configure legacy GMP runtime"
            # GMP 4.3's libtool rules are not safe under the runner's broad
            # inherited jobserver: parallel invocations race on .libs.
            make -j1 || die "cannot build legacy GMP runtime"
            make install || die "cannot install legacy GMP runtime"
        )
        tar --extract --bzip2 --file "${mpfr_archive}" --directory "${BUILD_DIR}"
        (
            cd "${mpfr_source}"
            export LD_LIBRARY_PATH="${gmp_prefix}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
            CC=gcc CFLAGS=-m32 LDFLAGS=-m32 ./configure --prefix="${mpfr_prefix}" --with-gmp="${gmp_prefix}" --disable-static || die "cannot configure legacy MPFR runtime"
            make -j1 || die "cannot build legacy MPFR runtime"
            make install || die "cannot install legacy MPFR runtime"
        )
    fi
    if [[ ! -f "${binary}" ]]; then
        # This vintage Makefile has no order-only dependency from its object
        # targets to OUT.  `make out/haret.exe` therefore needs it created
        # explicitly; forcing one job also avoids races in its legacy rules.
        mkdir -p "${source}/out"
        LD_LIBRARY_PATH="${mpfr_prefix}/lib:${gmp_prefix}/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
            make -C "${source}" -j1 BASE="${toolchain}/opt/mingw32ce" "out/haret.exe"
    fi
    test -s "${binary}" || die "HaRET build did not produce haret.exe"
    printf '%s\n' "${binary}" >&3
    exec 3>&-
}

assemble_image() {
    require dd; require parted; require mkfs.vfat; require mcopy; require debugfs; require e2fsck; require sha256sum; require xz
    [[ -f "${OUTPUT_DIR}/zImage" ]] || die "kernel artifact is not available"
    [[ -f "${OUTPUT_DIR}/rootfs.ext2" ]] || die "root filesystem artifact is not available"

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
        printf 'haret-revision=%s\n' "${HARET_REVISION}"
        printf 'haret-toolchain-sha256=%s\n' "${HARET_TOOLCHAIN_SHA256}"
        printf 'haret-gmp-runtime=%s\n' "${GMP_VERSION}"
        printf 'haret-gmp-sha256=%s\n' "${GMP_SHA256}"
        printf 'haret-mpfr-runtime=%s\n' "${MPFR_VERSION}"
        printf 'haret-mpfr-sha256=%s\n' "${MPFR_SHA256}"
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
