#!/usr/bin/env bash
# Validate the rx1950 package-manager source contract, sealed rootfs config and
# generated opkg feed without executing target binaries on the CI host.
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly OPKG_CONF="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/opkg/opkg.conf"
readonly DISTFEEDS_CONF="${ROOT_DIR}/buildroot/external/rx1950/rootfs-overlay/etc/opkg/distfeeds.conf"
readonly DEFCONFIG="${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig"
readonly FRAGMENT="${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_packages.fragment"
readonly FEED_URL="https://github.com/BlackF1re/rx1950-linux/releases/latest/download"
readonly FEED_ARCH="rx1950_armv4t_musl_v1"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
require_line() { grep -Fqx "$1" "$2" || die "$3"; }

validate_source() {
    # Keep repository locations separate from the core opkg policy. Upstream
    # opkg 0.7.0 reads every /etc/opkg/*.conf file, so distfeeds.conf is the
    # conventional place for the source while opkg.conf owns destinations and
    # architecture policy.
    require_line "src/gz rx1950 ${FEED_URL}" "${DISTFEEDS_CONF}" "rx1950 opkg feed URL missing"
    if grep -Eq '^[[:space:]]*src(/gz)?[[:space:]]' "${OPKG_CONF}"; then
        die "opkg.conf must not mix repository definitions with core policy"
    fi
    require_line "arch all 1" "${OPKG_CONF}" "opkg all architecture missing"
    require_line "arch ${FEED_ARCH} 100" "${OPKG_CONF}" "rx1950 opkg ABI architecture missing"
    require_line "dest root /" "${OPKG_CONF}" "opkg root destination missing"
    require_line "lists_dir ext /var/lib/opkg/lists" "${OPKG_CONF}" "opkg list directory missing"

    # opkg 0.7.0 enables HTTPS through libcurl only when libcurl is selected;
    # OpenSSL provides TLS and CA certificates provide server authentication.
    for requirement in \
        BR2_PACKAGE_OPKG=y \
        BR2_PACKAGE_LIBCURL=y \
        BR2_PACKAGE_LIBCURL_CURL=y \
        BR2_PACKAGE_LIBCURL_OPENSSL=y \
        BR2_PACKAGE_OPENSSL=y \
        BR2_PACKAGE_CA_CERTIFICATES=y; do
        require_line "${requirement}" "${DEFCONFIG}" "package-manager transport requirement missing: ${requirement}"
    done

    for requirement in \
        BR2_arm=y BR2_arm920t=y BR2_ARM_EABI=y BR2_SOFT_FLOAT=y \
        BR2_ARM_INSTRUCTIONS_ARM=y BR2_TOOLCHAIN_BUILDROOT_MUSL=y; do
        require_line "${requirement}" "${DEFCONFIG}" "rx1950 package ABI requirement missing: ${requirement}"
    done

    for package in BASH NANO RSYNC TMUX; do
        require_line "BR2_PACKAGE_${package}=y" "${FRAGMENT}" "initial feed package missing: ${package}"
    done

    # The default Buildroot 2025.02.2 BusyBox configuration already installs
    # these commands in the base image. Publishing full replacements through
    # opkg would overwrite symlinks that are not owned by opkg, so uninstalling
    # such a package could remove the base command entirely.
    for package in LESS TREE; do
        if grep -Fqx "BR2_PACKAGE_${package}=y" "${FRAGMENT}"; then
            die "feed package ${package} collides with a base BusyBox command"
        fi
    done

    grep -Fq 'base-show-info.json' "${ROOT_DIR}/scripts/build-opkg-feed.sh" || die "feed builder does not compare against the base package set"
    grep -Fq 'would overwrite base-image file' "${ROOT_DIR}/scripts/make-opkg-feed.py" || die "feed builder lacks base-file collision protection"
    grep -Fq 'filter_final_target_owners' "${ROOT_DIR}/scripts/make-opkg-feed.py" || die "feed builder does not filter target-finalize removals"
    grep -Fq 'os.path.lexists(target / path)' "${ROOT_DIR}/scripts/make-opkg-feed.py" || die "feed builder would lose dangling package symlinks"
    grep -Fq 'SHELL_REGISTRATIONS' "${ROOT_DIR}/scripts/make-opkg-feed.py" || die "feed builder does not preserve Buildroot shell registration hooks"
    grep -Fq 'conffiles' "${ROOT_DIR}/scripts/make-opkg-feed.py" || die "feed builder does not mark package configuration files"
    grep -Fq 'rx1950_armv4t_musl_v1' "${ROOT_DIR}/scripts/make-opkg-feed.py" || die "feed builder ABI token mismatch"
}

extract_rootfs_file() {
    local rootfs="$1" path="$2" destination="$3"
    debugfs -R "dump ${path} ${destination}" "${rootfs}" >/dev/null 2>&1 || \
        die "sealed rootfs is missing ${path}"
}

validate_rootfs() {
    local rootfs="$1" opkg_extracted feeds_extracted
    command -v debugfs >/dev/null 2>&1 || die "debugfs is required"
    [[ -s "${rootfs}" ]] || die "rootfs image is missing: ${rootfs}"
    opkg_extracted="$(mktemp)"
    feeds_extracted="$(mktemp)"
    trap 'rm -f "${opkg_extracted}" "${feeds_extracted}"' RETURN

    extract_rootfs_file "${rootfs}" /etc/opkg/opkg.conf "${opkg_extracted}"
    extract_rootfs_file "${rootfs}" /etc/opkg/distfeeds.conf "${feeds_extracted}"

    require_line "src/gz rx1950 ${FEED_URL}" "${feeds_extracted}" "sealed rootfs lost rx1950 package feed"
    require_line "arch ${FEED_ARCH} 100" "${opkg_extracted}" "sealed rootfs lost package ABI architecture"
    require_line "lists_dir ext /var/lib/opkg/lists" "${opkg_extracted}" "sealed rootfs lost persistent opkg lists directory"
    if grep -Eq '^[[:space:]]*src(/gz)?[[:space:]]' "${opkg_extracted}"; then
        die "sealed opkg.conf unexpectedly contains a repository definition"
    fi

    rm -f "${opkg_extracted}" "${feeds_extracted}"
    trap - RETURN
}

validate_ipk_payload() {
    local package="$1" tmp name candidate header
    tmp="$(mktemp -d)"
    mkdir -p "${tmp}/control" "${tmp}/data"

    ar p "${package}" control.tar.gz | tar -xzf - -C "${tmp}/control"
    ar p "${package}" data.tar.gz | tar -xzf - -C "${tmp}/data"
    name="$(sed -n 's/^Package: //p' "${tmp}/control/control" | head -n 1)"
    [[ -n "${name}" ]] || { rm -rf "${tmp}"; die "$(basename "${package}") has no Package control field"; }

    case "${name}" in
        bash|tmux)
            [[ -x "${tmp}/control/postinst" ]] || { rm -rf "${tmp}"; die "${name} lacks executable postinst"; }
            [[ -x "${tmp}/control/prerm" ]] || { rm -rf "${tmp}"; die "${name} lacks executable prerm"; }
            grep -Fq '/etc/shells' "${tmp}/control/postinst" || { rm -rf "${tmp}"; die "${name} postinst does not register /etc/shells"; }
            grep -Fq 'opkg-shells' "${tmp}/control/prerm" || { rm -rf "${tmp}"; die "${name} prerm lacks ownership marker handling"; }
            ;;
        readline)
            [[ -f "${tmp}/control/conffiles" ]] || { rm -rf "${tmp}"; die "readline lacks conffiles metadata"; }
            require_line '/etc/inputrc' "${tmp}/control/conffiles" 'readline does not protect /etc/inputrc as configuration'
            ;;
    esac

    # The host readelf understands foreign ELF headers without executing them.
    # Every target ELF emitted by this feed must remain exactly ARM EABI5
    # soft-float; a hard-float or newer-architecture package is unusable on the
    # ARM920T and must never reach the repository.
    while IFS= read -r -d '' candidate; do
        header="${tmp}/elf-header"
        if readelf -h "${candidate}" > "${header}" 2>/dev/null; then
            grep -Eq 'Machine:[[:space:]]+ARM' "${header}" || {
                rm -rf "${tmp}"; die "${name} contains a non-ARM ELF: ${candidate#${tmp}/data/}";
            }
            grep -Eq 'Flags:.*EABI.*soft-float ABI' "${header}" || {
                rm -rf "${tmp}"; die "${name} contains an incompatible ARM ABI: ${candidate#${tmp}/data/}";
            }
        fi
    done < <(find "${tmp}/data" -type f -print0)

    rm -rf "${tmp}"
}

validate_feed() {
    local dir="$1" package count=0
    command -v ar >/dev/null 2>&1 || die "ar is required"
    command -v tar >/dev/null 2>&1 || die "tar is required"
    command -v readelf >/dev/null 2>&1 || die "readelf is required"
    [[ -s "${dir}/Packages" ]] || die "Packages index missing"
    [[ -s "${dir}/Packages.gz" ]] || die "Packages.gz missing"
    [[ -s "${dir}/feed.json" ]] || die "feed.json missing"
    [[ -s "${dir}/PACKAGES-SHA256SUMS" ]] || die "package checksums missing"
    gzip -t "${dir}/Packages.gz"
    (cd "${dir}" && sha256sum --check PACKAGES-SHA256SUMS)

    grep -Fq "Architecture: ${FEED_ARCH}" "${dir}/Packages" || die "feed architecture mismatch"
    grep -Fq '"epoch": 1' "${dir}/feed.json" || die "feed ABI epoch missing"

    for package in "${dir}"/*.ipk; do
        [[ -f "${package}" ]] || continue
        count=$((count + 1))
        mapfile -t members < <(ar t "${package}")
        [[ " ${members[*]} " == *' debian-binary '* ]] || die "$(basename "${package}") lacks debian-binary"
        [[ " ${members[*]} " == *' control.tar.gz '* ]] || die "$(basename "${package}") lacks control.tar.gz"
        [[ " ${members[*]} " == *' data.tar.gz '* ]] || die "$(basename "${package}") lacks data.tar.gz"
        validate_ipk_payload "${package}"
    done
    (( count > 0 )) || die "feed contains no ipk packages"

    python3 - "${dir}/Packages" <<'PY'
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
records = [r for r in text.strip().split("\n\n") if r.strip()]
names = set()
parsed = []
for record in records:
    fields = {}
    for line in record.splitlines():
        key, value = line.split(":", 1)
        fields[key] = value.strip()
    required = {"Package", "Version", "Architecture", "Filename", "SHA256sum"}
    missing = required - fields.keys()
    if missing:
        raise SystemExit(f"index record missing {sorted(missing)}")
    names.add(fields["Package"])
    parsed.append(fields)
for fields in parsed:
    for dep in filter(None, (v.strip() for v in fields.get("Depends", "").split(","))):
        dep = dep.split(" ", 1)[0]
        if dep not in names:
            raise SystemExit(f"{fields['Package']} has unresolved feed dependency {dep}")
PY
}

case "${1:-source}" in
    source) validate_source ;;
    rootfs)
        [[ "$#" -eq 2 ]] || die "usage: validate-opkg-feed.sh rootfs ROOTFS"
        validate_rootfs "$2"
        ;;
    feed)
        [[ "$#" -eq 2 ]] || die "usage: validate-opkg-feed.sh feed DIRECTORY"
        validate_feed "$2"
        ;;
    *) die "usage: validate-opkg-feed.sh {source|rootfs ROOTFS|feed DIRECTORY}" ;;
esac
