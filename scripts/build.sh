#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly OUTPUT_DIR="${ROOT_DIR}/output"
readonly DOWNLOAD_DIR="${ROOT_DIR}/dl"
readonly BUILD_DIR="${ROOT_DIR}/.build"
# shellcheck source=sources.lock.sh
source "${ROOT_DIR}/scripts/sources.lock.sh"
readonly CROSS_COMPILE="${CROSS_COMPILE:-arm-linux-gnueabi-}"
readonly IMAGE_NAME="${RX1950_IMAGE_NAME:-rx1950-linux-sd}"

# Reproducible build epoch: 2026-01-01 00:00:00 UTC. Source identity and the
# release commit remain in provenance, not inside payloads. An explicit caller
# value is honoured so downstream rebuilders can use the same contract.
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-1767225600}"
export TZ="${TZ:-UTC}"
export LANG=C
export LC_ALL=C
export KBUILD_BUILD_TIMESTAMP="${KBUILD_BUILD_TIMESTAMP:-@${SOURCE_DATE_EPOCH}}"
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-rx1950-linux}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-reproducible}"
export KBUILD_BUILD_VERSION="${KBUILD_BUILD_VERSION:-1}"

mkdir -p "${OUTPUT_DIR}" "${DOWNLOAD_DIR}" "${BUILD_DIR}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }
sha256() { printf '%s  %s\n' "$2" "$1" | sha256sum --check --status; }

download() {
    local url="$1" destination="$2" expected="$3" protocols="${4:-=https}"
    if [[ ! -f "${destination}" ]] || ! sha256 "${destination}" "${expected}"; then
        local temporary="${destination}.download"
        rm -f "${destination}"
        rm -f "${temporary}"
        if ! curl --fail --location --retry 3 --proto "${protocols}" \
            "${url}" --output "${temporary}"; then
            rm -f "${temporary}"
            die "failed to download ${url}"
        fi
        if ! sha256 "${temporary}" "${expected}"; then
            rm -f "${temporary}"
            die "checksum mismatch for ${url}"
        fi
        mv "${temporary}" "${destination}"
    fi
    sha256 "${destination}" "${expected}" || die "checksum mismatch for ${destination}"
}

prepare_acx_firmware() {
    local archive="${DOWNLOAD_DIR}/acx-firmware-${ACX_FIRMWARE_VERSION}.tgz"
    # The historical OpenBSD firmware endpoint has a mismatched TLS
    # certificate. Pin the complete archive digest instead of trusting HTTP.
    download \
        "http://firmware.openbsd.org/firmware/7.7/acx-firmware-${ACX_FIRMWARE_VERSION}.tgz" \
        "${archive}" "${ACX_FIRMWARE_SHA256}" '=http,https'
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

prepare_regdb() {
    local archive="${DOWNLOAD_DIR}/wireless-regdb-${WIRELESS_REGDB_VERSION}.tar.xz"
    local stage="${BUILD_DIR}/wireless-regdb-${WIRELESS_REGDB_VERSION}"
    download \
        "https://cdn.kernel.org/pub/software/network/wireless-regdb/wireless-regdb-${WIRELESS_REGDB_VERSION}.tar.xz" \
        "${archive}" "${WIRELESS_REGDB_SHA256}"
    if [[ ! -s "${stage}/regulatory.db" || ! -s "${stage}/regulatory.db.p7s" ]]; then
        rm -rf "${stage}"
        mkdir -p "${stage}"
        tar --extract --file "${archive}" --directory "${stage}" --strip-components=1
    fi
    test -s "${stage}/regulatory.db" || die "wireless regulatory database is missing"
    test -s "${stage}/regulatory.db.p7s" || die "wireless regulatory signature is missing"
    printf '%s\n' "${stage}"
}

install_kernel_regdb() {
    local kernel_source="$1" regdb_source
    regdb_source="$(prepare_regdb)"
    mkdir -p "${kernel_source}/firmware"
    install -m 0644 "${regdb_source}/regulatory.db" "${kernel_source}/firmware/regulatory.db"
    install -m 0644 "${regdb_source}/regulatory.db.p7s" "${kernel_source}/firmware/regulatory.db.p7s"
}

prepare_acx() {
    require git
    require patch
    local source="${BUILD_DIR}/acx-mac80211"
    local patch_file
    if [[ ! -d "${source}/.git" ]]; then
        rm -rf "${source}"
        git clone --filter=blob:none --no-checkout "${ACX_REPOSITORY}" "${source}"
    fi
    git -C "${source}" fetch --force --depth=1 origin "${ACX_COMMIT}"
    git -C "${source}" checkout --force --detach "${ACX_COMMIT}"
    [[ "$(git -C "${source}" rev-parse HEAD)" == "${ACX_COMMIT}" ]] ||
        die "ACX source is not pinned to ${ACX_COMMIT}"

    for patch_file in "${ROOT_DIR}"/kernel/acx-patches/*.patch; do
        [[ -e "${patch_file}" ]] || continue
        if patch --directory="${source}" --strip=1 --dry-run --forward --batch < "${patch_file}" >&2; then
            patch --directory="${source}" --strip=1 --forward --batch < "${patch_file}" >&2
        elif patch --directory="${source}" --strip=1 --dry-run --reverse --batch < "${patch_file}" >&2; then
            : # Already patched in a reusable local tree.
        else
            die "cannot apply ACX patch ${patch_file}"
        fi
    done

    grep -Fq 'adev->irq_reason |= deferred;' "${source}/merge.c" ||
        die "ACX MEM interrupt latch patch is missing"
    grep -Fq 'irqmasked & ~HOST_INT_CMD_COMPLETE' "${source}/merge.c" ||
        die "ACX command completion IRQ can be consumed before the poller"
    grep -Fq '.cancel_hw_scan' "${source}/mem.c" ||
        die "ACX scan cancellation callback is missing"
    grep -Fq 'test_and_clear_bit(ACX_FLAG_SCANNING' "${source}/merge.c" ||
        die "ACX scan completion is not serialized"
    grep -Fq 'write_reg16(adev, IO_ACX_IRQ_ACK, deferred);' "${source}/merge.c" ||
        die "ACX MEM interrupt ACK patch is missing"
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

validate_kernel_source() {
    local source="$1" clk_file serial_file board_file
    clk_file="${source}/drivers/clk/samsung/clk-s3c2410.c"
    serial_file="${source}/drivers/tty/serial/samsung_tty.c"
    board_file="${source}/arch/arm/mach-s3c/mach-rx1950.c"

    [[ "$(grep -Fc '.clk_sel = S3C2410_UCON_CLKSEL3,' "${board_file}")" -eq 3 ]] ||
        die "RX1950 UARTs no longer select the historical FCLK/n source"
    grep -Fq 'static unsigned long s3c244x_fclk_n_recalc_rate' "${clk_file}" ||
        die "kernel source lost the restored S3C244x fclk_n clock"
    grep -Fq 'clk_hw_register_clkdev(&s3c244x_fclk_n_hw, "clk_uart_baud3"' "${clk_file}" ||
        die "kernel source lost the clk_uart_baud3 alias"
    grep -Fq 'platform_get_irq_optional(platdev, 1)' "${serial_file}" ||
        die "Samsung UART optional TX IRQ handling is missing"
    grep -Fq 'RX1950 UART%d: entering uart_add_one_port' "${serial_file}" ||
        die "RX1950 UART boot trace markers are missing"
}

build_rootfs() {
    require make
    chmod +x "${ROOT_DIR}/buildroot/external/rx1950/board/hp_rx1950/post-build.sh"
    local source
    # Fetch and authenticate small external payloads before the expensive
    # Buildroot compilation so a transient mirror response fails immediately.
    prepare_acx_firmware
    source="$(prepare_buildroot)"
    local out="${BUILD_DIR}/buildroot-output"
    mkdir -p "${out}"
    make -C "${source}" O="${out}" BR2_EXTERNAL="${ROOT_DIR}/buildroot/external/rx1950" rx1950_defconfig

    # Local packages are intentionally absent from the expensive Buildroot
    # state key. Rebuild them on every invocation so source-only UI changes
    # take seconds and can never be hidden by an otherwise valid cache hit.
    make -C "${source}" O="${out}" \
        gpe-conf-rx1950-dirclean rx1950-shell-dirclean

    make -C "${source}" O="${out}" -j"$(nproc)"
    cp "${out}/images/rootfs.ext2" "${OUTPUT_DIR}/rootfs.ext2"
    cp "${out}/.config" "${OUTPUT_DIR}/buildroot.config"
    # The external-tree Git description is diagnostic metadata, not a build
    # input. Normalize the exported config so identical source trees compare
    # byte-for-byte even when GitHub represents them with different commits.
    sed -i -E 's/^BR2_EXTERNAL_RX1950_VERSION=.*/BR2_EXTERNAL_RX1950_VERSION=""/' "${OUTPUT_DIR}/buildroot.config"
    "${ROOT_DIR}/scripts/build-recovery.sh" "${out}/target" "${OUTPUT_DIR}/recovery.cpio.gz"
}

validate_kernel_config() {
    local config="$1" requirement
    local -a requirements=(
        'CONFIG_ARCH_MULTI_V4T=y'
        '# CONFIG_ARCH_MULTI_V7 is not set'
        'CONFIG_ARCH_S3C24XX=y'
        'CONFIG_CPU_ARM920T=y'
        'CONFIG_CPU_S3C2442=y'
        'CONFIG_MACH_RX1950=y'
        'CONFIG_ATAGS=y'
        'CONFIG_UNUSED_BOARD_FILES=y'
        'CONFIG_BLK_DEV_INITRD=y'
        'CONFIG_RD_GZIP=y'
        'CONFIG_BINFMT_ELF=y'
        'CONFIG_BINFMT_SCRIPT=y'
        'CONFIG_MODULES=y'
        'CONFIG_FW_LOADER=y'
        'CONFIG_EXTRA_FIRMWARE="regulatory.db regulatory.db.p7s"'
        'CONFIG_EXTRA_FIRMWARE_DIR="firmware"'
        'CONFIG_WIRELESS=y'
        'CONFIG_CFG80211=y'
        'CONFIG_MAC80211=y'
        'CONFIG_LEDS_TRIGGER_NETDEV=y'
        'CONFIG_DMADEVICES=y'
        'CONFIG_S3C24XX_DMAC=y'
        'CONFIG_SWAP=y'
        'CONFIG_ZRAM=y'
        'CONFIG_CRYPTO_LZO=y'
        'CONFIG_ZRAM_DEF_COMP_LZORLE=y'
        'CONFIG_MMC_S3C=y'
        'CONFIG_FB_S3C2410=y'
        '# CONFIG_MTD_BLOCK is not set'
        '# CONFIG_SERIAL_SAMSUNG_CONSOLE is not set'
        'CONFIG_CMDLINE="root=/dev/mmcblk0p2 rootwait rw console=tty0 loglevel=4 consoleblank=0"'
        'CONFIG_CMDLINE_FROM_BOOTLOADER=y'
        '# CONFIG_CMDLINE_FORCE is not set'
    )

    for requirement in "${requirements[@]}"; do
        grep -Fqx "${requirement}" "${config}" ||
            die "kernel configuration lost RX1950 requirement: ${requirement}"
    done
}

validate_kernel_binary() {
    local vmlinux="$1" symbols="$2"
    require "${CROSS_COMPILE}readelf"
    require "${CROSS_COMPILE}nm"

    "${CROSS_COMPILE}readelf" -h "${vmlinux}" | grep -Eq 'Machine:[[:space:]]+ARM' ||
        die "linked kernel is not an ARM ELF"
    "${CROSS_COMPILE}nm" "${vmlinux}" > "${symbols}"
    grep -Eq '[[:space:]]__mach_desc_RX1950$' "${symbols}" ||
        die "linked kernel does not contain the RX1950 machine descriptor"
    grep -aFq 'HP iPAQ RX1950' "${vmlinux}" ||
        die "linked kernel does not contain the RX1950 machine identity"
    grep -aFq 'RX1950 UART%d: entering uart_add_one_port' "${vmlinux}" ||
        die "linked kernel does not contain the RX1950 UART trace markers"
}

build_wlan_modules() {
    local kernel_source="$1" kernel_out="$2"
    local acx_source module_source module_root kernel_release acx_log glue_log

    test -s "${kernel_out}/Module.symvers" ||
        die "kernel Module.symvers is missing; refusing to build unloadable WLAN modules"

    acx_source="$(prepare_acx)"
    module_source="${ROOT_DIR}/kernel/modules/rx1950-acx"
    acx_log="${kernel_out}/acx-module-build.log"
    glue_log="${kernel_out}/rx1950-acx-module-build.log"

    # Use the ACX project's own wrapper so its CONFIG_ACX_* command-line
    # symbols are also emitted as preprocessor defines. Only the slave-memory
    # backend is built; PCI and USB ACX transports are deliberately excluded.
    make -C "${acx_source}" \
        KERNELDIR="${kernel_out}" \
        ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" \
        ACX_GIT_VERSION="${ACX_COMMIT}" \
        EXTRA_KCONFIG='CONFIG_ACX_MAC80211=m CONFIG_ACX_MAC80211_MEM=m CONFIG_ACX_MAC80211_PCI=n CONFIG_ACX_MAC80211_USB=n' \
        -j"$(nproc)" 2>&1 | tee "${acx_log}"

    if grep -Eq 'Module\.symvers is missing|modpost: .* undefined!' "${acx_log}"; then
        die "ACX100 module build contains unresolved kernel symbols"
    fi

    make -C "${kernel_source}" O="${kernel_out}" \
        ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" \
        M="${module_source}" -j"$(nproc)" modules 2>&1 | tee "${glue_log}"

    if grep -Eq 'Module\.symvers is missing|modpost: .* undefined!' "${glue_log}"; then
        die "RX1950 WLAN glue build contains unresolved kernel symbols"
    fi

    test -s "${acx_source}/acx-mac80211.ko" || die "ACX100 slave-memory module was not built"
    test -s "${module_source}/rx1950_acx.ko" || die "RX1950 ACX platform module was not built"
    "${CROSS_COMPILE}readelf" -h "${acx_source}/acx-mac80211.ko" | grep -Eq 'Machine:[[:space:]]+ARM' ||
        die "ACX100 module is not ARM ELF"
    "${CROSS_COMPILE}readelf" -h "${module_source}/rx1950_acx.ko" | grep -Eq 'Machine:[[:space:]]+ARM' ||
        die "RX1950 ACX module is not ARM ELF"

    kernel_release="$(make -s -C "${kernel_source}" O="${kernel_out}" ARCH=arm kernelrelease)"
    module_root="${BUILD_DIR}/rx1950-module-root"
    rm -rf "${module_root}"
    mkdir -p "${module_root}/lib/modules/${kernel_release}/extra"
    cp "${acx_source}/acx-mac80211.ko" "${module_root}/lib/modules/${kernel_release}/extra/"
    cp "${module_source}/rx1950_acx.ko" "${module_root}/lib/modules/${kernel_release}/extra/"
    find "${module_root}" -exec touch -h -d "@${SOURCE_DATE_EPOCH}" {} +
    tar --sort=name --mtime="@${SOURCE_DATE_EPOCH}" --owner=0 --group=0 --numeric-owner \
        --format=gnu -C "${module_root}" -cf "${OUTPUT_DIR}/kernel-modules.tar" .
}

build_kernel() {
    require make
    require grep
    require tar
    require git
    require tee
    require "${CROSS_COMPILE}gcc"
    local source
    source="$(prepare_kernel)"
    apply_kernel_patches "${source}"
    validate_kernel_source "${source}"
    # cfg80211 is built in and initializes before the SD root filesystem is
    # mounted. Embed the authenticated database so its first request succeeds.
    install_kernel_regdb "${source}"
    local out="${BUILD_DIR}/kernel-output"
    rm -rf "${out}"
    mkdir -p "${out}"
    cp "${ROOT_DIR}/kernel/rx1950_defconfig" "${out}/.config"
    sed -i \
        -e 's|^CONFIG_CMDLINE=.*|CONFIG_CMDLINE="root=/dev/mmcblk0p2 rootwait rw console=tty0 loglevel=4 consoleblank=0"|' \
        -e '/^CONFIG_CMDLINE_FROM_BOOTLOADER=/d' \
        -e '/^CONFIG_CMDLINE_EXTEND=/d' \
        -e '/^CONFIG_CMDLINE_FORCE=/d' \
        "${out}/.config"
    printf '%s\n' 'CONFIG_CMDLINE_FROM_BOOTLOADER=y' >> "${out}/.config"
    make -C "${source}" O="${out}" ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" olddefconfig
    validate_kernel_config "${out}/.config"

    # A real modules pass is mandatory here. modules_prepare is insufficient:
    # it does not create Module.symvers, so external ACX modules can appear to
    # build while retaining unresolved kernel symbols and then fail at insmod.
    make -C "${source}" O="${out}" ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" -j"$(nproc)" zImage modules
    test -s "${out}/Module.symvers" ||
        die "kernel export table was not generated by the modules build"

    validate_kernel_binary "${out}/vmlinux" "${out}/vmlinux.nm"
    build_wlan_modules "${source}" "${out}"
    cp "${out}/arch/arm/boot/zImage" "${OUTPUT_DIR}/zImage"
    cp "${out}/.config" "${OUTPUT_DIR}/kernel.config"
}

prepare_haret() {
    # This RX1950-specific binary is the historically deployed loader for
    # the device. It reaches the target from locked stock WM 6.1 systems,
    # unlike binaries built with contemporary Windows CE toolchains.
    local binary="${DOWNLOAD_DIR}/haret-${HARET_VERSION}.exe"
    download "https://downloads.tuxfamily.org/linuxrx1950/bootloader/haret-7jun2011.exe" \
        "${binary}" "${HARET_SHA256}"
    printf '%s\n' "${binary}"
}

validate_zimage_placement() {
    # HaRET places zImage at RAMADDR + KERNEL_OFFSET + 0x8000. The ARM
    # decompressor writes the inflated Image from RAMADDR + 0x8000 upwards.
    # The historical 5 MiB RX1950 offset was adequate for 2.6-era kernels,
    # but a current kernel can overwrite unread compressed input before the
    # first board callback runs. Check the actual payload instead of relying
    # on a version-specific estimate.
    require grep; require gzip; require tail; require wc
    local image="$1" gzip_offset inflated_size available
    gzip_offset="$(LC_ALL=C grep --text --byte-offset --only-matching $'\x1f\x8b\x08' "${image}" | head --lines=1 | cut --delimiter=: --fields=1)"
    [[ "${gzip_offset}" =~ ^[0-9]+$ ]] || die "cannot locate gzip payload in ${image}"
    inflated_size="$(
        set +o pipefail
        tail --bytes="+$((gzip_offset + 1))" "${image}" | gzip --decompress --stdout 2>/dev/null | wc --bytes
    )"
    available=$((KERNEL_OFFSET - KERNEL_ZRELADDR))
    (( inflated_size > 0 )) || die "cannot read compressed kernel payload"
    (( inflated_size < available )) || die "zImage expands to ${inflated_size} bytes, exceeding the ${available}-byte safe decompression window"
}

assemble_image() {
    require dd; require parted; require mkfs.vfat; require mcopy; require e2fsck; require sha256sum; require xz
    [[ -f "${OUTPUT_DIR}/zImage" ]] || die "kernel artifact is not available"
    [[ -f "${OUTPUT_DIR}/kernel-modules.tar" ]] || die "kernel module bundle is not available"
    [[ -f "${OUTPUT_DIR}/rootfs.ext2" ]] || die "root filesystem artifact is not available"
    [[ -f "${OUTPUT_DIR}/recovery.cpio.gz" ]] || die "cable-update recovery is not available"
    validate_zimage_placement "${OUTPUT_DIR}/zImage"

    local haret bootfs image root_start rootfs_size image_size haret_log_trigger
    haret="$(prepare_haret)"
    bootfs="${OUTPUT_DIR}/boot.fat"
    image="${OUTPUT_DIR}/${IMAGE_NAME}.img"
    haret_log_trigger="${OUTPUT_DIR}/earlyharetlog.txt"
    root_start=34816

    rm -f "${bootfs}" "${image}" "${image}.xz"
    : > "${haret_log_trigger}"
    truncate --size 16M "${bootfs}"
    mkfs.vfat --invariant -F 16 -n RX1950BOOT "${bootfs}"
    mcopy -i "${bootfs}" "${haret}" ::haret.exe
    mcopy -i "${bootfs}" "${haret_log_trigger}" ::earlyharetlog.txt
    mcopy -i "${bootfs}" "${ROOT_DIR}/board/hp_rx1950/startup.txt" ::startup.txt
    mcopy -i "${bootfs}" "${OUTPUT_DIR}/zImage" ::zImage
    mcopy -i "${bootfs}" "${OUTPUT_DIR}/kernel-modules.tar" ::kernel-modules.tar
    mcopy -i "${bootfs}" "${OUTPUT_DIR}/recovery.cpio.gz" ::recovery.cpio.gz
    mcopy -i "${bootfs}" "${ROOT_DIR}/board/hp_rx1950/README.txt" ::README.txt

    # Verify without changing last-check timestamps or other ext4 metadata.
    e2fsck -fn "${OUTPUT_DIR}/rootfs.ext2"

    rootfs_size="$(stat --format='%s' "${OUTPUT_DIR}/rootfs.ext2")"
    test $((rootfs_size % 512)) -eq 0 || die "root filesystem is not sector-aligned"
    image_size=$((root_start * 512 + rootfs_size))
    truncate --size "${image_size}" "${image}"
    parted --script "${image}" mklabel msdos mkpart primary fat16 1MiB 17MiB mkpart primary ext4 17MiB 100% set 1 boot on
    # GNU parted assigns a random MBR disk signature. Give the board image a
    # stable project-specific signature before copying partition payloads.
    printf '\x50\x19\x50\x19' | dd of="${image}" bs=1 seek=440 conv=notrunc status=none
    dd if="${bootfs}" of="${image}" bs=512 seek=2048 conv=notrunc status=none
    dd if="${OUTPUT_DIR}/rootfs.ext2" of="${image}" bs=512 seek="${root_start}" conv=notrunc status=none
    # A fixed single-threaded XZ stream avoids host-CPU-dependent block layout.
    xz --keep --force --threads=1 --check=crc32 "${image}"
    (
        cd "${OUTPUT_DIR}"
        sha256sum "${IMAGE_NAME}.img" "${IMAGE_NAME}.img.xz" zImage recovery.cpio.gz > SHA256SUMS
    )
    {
        printf 'build=%s\n' "${BUILD_ID:-local}"
        printf 'source-date-epoch=%s\n' "${SOURCE_DATE_EPOCH}"
        printf 'buildroot=%s\n' "${BUILDROOT_VERSION}"
        printf 'kernel=%s\n' "${KERNEL_VERSION}"
        printf 'acx-source=%s@%s\n' "${ACX_REPOSITORY}" "${ACX_COMMIT}"
        printf 'acx-firmware=bundled:yes,verified-sha256\n'
        printf 'haret-version=%s\n' "${HARET_VERSION}"
        printf 'haret-sha256=%s\n' "${HARET_SHA256}"
        printf 'image=%s\n' "${IMAGE_NAME}.img"
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
