#!/usr/bin/env bash
# Build an rx1950-native opkg feed from the exact Buildroot toolchain/state used
# by the system image. The package job restores the verified base Buildroot
# cache, then this script builds only the optional package delta and packages
# that delta into .ipk files.
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly OUTPUT_DIR="${ROOT_DIR}/output/packages"
readonly DOWNLOAD_DIR="${ROOT_DIR}/dl"
readonly BUILD_DIR="${ROOT_DIR}/.build"
readonly BUILDROOT_VERSION="2025.02.2"
readonly BUILDROOT_SHA256="4a74e9a6f82ef8660ae2ef865d0ad61a4e9ccd67e2aeef885cae1165581ed5ac"
readonly EXTERNAL_DIR="${ROOT_DIR}/buildroot/external/rx1950"
readonly BASE_DEFCONFIG="${EXTERNAL_DIR}/configs/rx1950_defconfig"
readonly PACKAGE_FRAGMENT="${EXTERNAL_DIR}/configs/rx1950_packages.fragment"
readonly BUILDROOT_OUTPUT="${BUILD_DIR}/buildroot-output"

mkdir -p "${OUTPUT_DIR}" "${DOWNLOAD_DIR}" "${BUILD_DIR}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
require() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }
sha256_ok() { printf '%s  %s\n' "$2" "$1" | sha256sum --check --status; }

prepare_buildroot() {
    local archive="${DOWNLOAD_DIR}/buildroot-${BUILDROOT_VERSION}.tar.xz"
    local source="${BUILD_DIR}/buildroot-${BUILDROOT_VERSION}"

    if [[ ! -f "${archive}" ]] || ! sha256_ok "${archive}" "${BUILDROOT_SHA256}"; then
        rm -f "${archive}"
        curl --fail --location --retry 3 --proto '=https' --tlsv1.2 \
            "https://buildroot.org/downloads/buildroot-${BUILDROOT_VERSION}.tar.xz" \
            --output "${archive}"
    fi
    sha256_ok "${archive}" "${BUILDROOT_SHA256}" || die "Buildroot checksum mismatch"

    if [[ ! -d "${source}" ]]; then
        tar --extract --file "${archive}" --directory "${BUILD_DIR}"
    fi
    printf '%s\n' "${source}"
}

make_br() {
    make --no-print-directory -C "$1" O="${BUILDROOT_OUTPUT}" \
        BR2_EXTERNAL="${EXTERNAL_DIR}" "${@:2}"
}

snapshot_base_files() {
    local destination="$1"
    : > "${destination}"
    while IFS= read -r -d '' listing; do
        sed -n 's/^[^,]*,//p' "${listing}"
    done < <(find "${BUILDROOT_OUTPUT}/build" -mindepth 2 -maxdepth 2 \
        -type f -name '.files-list.txt' -print0 | sort -z) \
        | sed -e 's#^\./##' -e 's#^/##' \
        | LC_ALL=C sort -u > "${destination}"
    [[ -s "${destination}" ]] || die "base Buildroot file ownership snapshot is empty"
}

apply_package_fragment() {
    local config="${BUILDROOT_OUTPUT}/.config"
    local setting symbol
    [[ -f "${PACKAGE_FRAGMENT}" ]] || die "missing ${PACKAGE_FRAGMENT}"
    while IFS= read -r setting; do
        [[ -n "${setting}" && "${setting}" != \#* ]] || continue
        [[ "${setting}" == *=* ]] || die "invalid package fragment line: ${setting}"
        symbol="${setting%%=*}"
        sed -i -e "/^${symbol}=/d" -e "/^# ${symbol} is not set$/d" "${config}"
        printf '%s\n' "${setting}" >> "${config}"
    done < "${PACKAGE_FRAGMENT}"
}

validate_target_abi() {
    local config="${BUILDROOT_OUTPUT}/.config"
    local requirement
    for requirement in \
        BR2_arm=y \
        BR2_arm920t=y \
        BR2_ARM_EABI=y \
        BR2_SOFT_FLOAT=y \
        BR2_ARM_INSTRUCTIONS_ARM=y \
        BR2_TOOLCHAIN_BUILDROOT_MUSL=y; do
        grep -Fqx "${requirement}" "${config}" || die "package feed ABI mismatch: ${requirement}"
    done
}

main() {
    require make
    require curl
    require tar
    require sha256sum
    require python3
    require ar
    require find
    require sed

    local source
    source="$(prepare_buildroot)"
    mkdir -p "${BUILDROOT_OUTPUT}"

    # First materialize the exact base configuration. On CI this reuses the
    # rootfs cache produced/verified by the preceding rootfs job and therefore
    # takes seconds rather than rebuilding the toolchain.
    make_br "${source}" rx1950_defconfig
    make_br "${source}" -j"$(nproc)"
    validate_target_abi

    make_br "${source}" -s show-info > "${OUTPUT_DIR}/base-show-info.json"
    snapshot_base_files "${OUTPUT_DIR}/base-files.txt"

    # Enable only the optional feed payload. Buildroot keeps all previously
    # built base packages and compiles the delta plus its exact dependencies.
    apply_package_fragment
    make_br "${source}" olddefconfig
    validate_target_abi

    while IFS= read -r setting; do
        [[ -n "${setting}" && "${setting}" != \#* ]] || continue
        grep -Fqx "${setting}" "${BUILDROOT_OUTPUT}/.config" || \
            die "Buildroot rejected requested feed option: ${setting}"
    done < "${PACKAGE_FRAGMENT}"

    make_br "${source}" -j"$(nproc)"
    make_br "${source}" -s show-info > "${OUTPUT_DIR}/feed-show-info.json"

    SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}" \
        python3 "${ROOT_DIR}/scripts/make-opkg-feed.py" \
            --base-info "${OUTPUT_DIR}/base-show-info.json" \
            --feed-info "${OUTPUT_DIR}/feed-show-info.json" \
            --base-files "${OUTPUT_DIR}/base-files.txt" \
            --build-dir "${BUILDROOT_OUTPUT}/build" \
            --target "${BUILDROOT_OUTPUT}/target" \
            --output "${OUTPUT_DIR}"

    # Build metadata is useful while debugging CI but must not be published as
    # repository content; keep only the feed payload after packaging succeeds.
    rm -f "${OUTPUT_DIR}/base-show-info.json" \
          "${OUTPUT_DIR}/feed-show-info.json" \
          "${OUTPUT_DIR}/base-files.txt"
}

main "$@"
