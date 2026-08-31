#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly EPOCH=1767225600
readonly ROOTFS_UUID=19501950-1950-4195-8195-019501950195

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

validate_source() {
    local build="${ROOT_DIR}/scripts/build.sh"
    local feed="${ROOT_DIR}/scripts/build-opkg-feed.sh"
    local config="${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
    local post="${ROOT_DIR}/buildroot/external/rx1950/board/hp_rx1950/post-build.sh"

    grep -Fqx 'BR2_REPRODUCIBLE=y' "$config" || die 'Buildroot reproducible mode is disabled'
    grep -Fq -- "-U ${ROOTFS_UUID}" "$config" || die 'rootfs UUID is not fixed'
    grep -Fq "hash_seed=${ROOTFS_UUID}" "$config" || die 'ext4 directory hash seed is not fixed'
    grep -Fq 'lazy_itable_init=0,lazy_journal_init=0' "$config" || die 'ext4 lazy initialization is enabled'
    grep -Fq "SOURCE_DATE_EPOCH:-${EPOCH}" "$build" || die 'build epoch is not pinned'
    grep -Fq "SOURCE_DATE_EPOCH:-${EPOCH}" "$feed" || die 'package feed epoch is not pinned'
    grep -Fq 'KBUILD_BUILD_TIMESTAMP' "$build" || die 'kernel timestamp is not normalized'
    grep -Fq 'KBUILD_BUILD_USER' "$build" || die 'kernel build user is not normalized'
    grep -Fq 'KBUILD_BUILD_HOST' "$build" || die 'kernel build host is not normalized'
    grep -Fq 'tar --sort=name --mtime=' "$build" || die 'module tar metadata is not normalized'
    grep -Fq 'mkfs.vfat --invariant' "$build" || die 'FAT filesystem metadata is not invariant'
    grep -Fq 'seek=440' "$build" || die 'MBR disk signature is not normalized'
    grep -Fq 'xz --keep --force --threads=1 --check=crc32' "$build" || die 'XZ output is host-CPU dependent'
    grep -Fq 'e2fsck -fn' "$build" || die 'rootfs verification may mutate filesystem metadata'
    ! grep -Fq 'e2fsck -fp' "$build" || die 'mutating e2fsck mode is still present'
    grep -Fq 'VERSION="${RELEASE_VERSION}"' "$post" || die '/etc/os-release still depends on checkout identity'
}

validate_artifacts() {
    local out="${1:-${ROOT_DIR}/output}"
    local image
    image="$(find "$out" -maxdepth 1 -type f -name 'rx1950-linux-*.img' -print -quit)"
    [[ -n "$image" ]] || die 'assembled image not found'
    [[ -f "$out/zImage" ]] || die 'zImage not found'
    [[ -f "$out/zImage-recovery" ]] || die 'embedded recovery kernel not found'
    [[ -f "$out/kernel-modules.tar" ]] || die 'kernel module bundle not found'
    [[ -f "$out/rootfs.ext2" ]] || die 'rootfs.ext2 not found'
    [[ -f "$out/provenance.txt" ]] || die 'provenance not found'

    # 0x19501950 as little-endian bytes at the DOS MBR disk-signature field.
    [[ "$(dd if="$image" bs=1 skip=440 count=4 status=none | od -An -tx1 | tr -d ' \n')" == '50195019' ]] ||
        die 'assembled image has a non-deterministic MBR disk signature'

    grep -Fqx "source-date-epoch=${EPOCH}" "$out/provenance.txt" ||
        die 'provenance does not record the reproducible epoch'

    if command -v tune2fs >/dev/null 2>&1; then
        tune2fs -l "$out/rootfs.ext2" 2>/dev/null | \
            grep -Eq "^Filesystem UUID:[[:space:]]+${ROOTFS_UUID}$" ||
            die 'rootfs UUID does not match the reproducible UUID'
    fi
}

case "${1:-source}" in
    source) validate_source ;;
    artifacts) validate_artifacts "${2:-${ROOT_DIR}/output}" ;;
    *) die 'usage: validate-reproducible.sh {source|artifacts [output-dir]}' ;;
esac
