#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly WORKFLOW="${ROOT_DIR}/.github/workflows/build-release.yml"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
require_text() { grep -Fq -- "$1" "$2" || die "$3"; }

[[ -f "${ROOT_DIR}/scripts/sources.lock.sh" ]] || die 'pinned source lock is missing'
[[ -x "${ROOT_DIR}/scripts/cache-key.sh" ]] || die 'cache-key.sh is not executable'

rootfs_key="$("${ROOT_DIR}/scripts/cache-key.sh" rootfs)"
[[ "${rootfs_key}" =~ ^[0-9a-f]{64}$ ]] || die 'rootfs cache key is not a SHA-256 digest'

temporary="$(mktemp -d)"
trap 'rm -rf "${temporary}"' EXIT
mkdir -p "${temporary}/scripts" "${temporary}/buildroot/external/rx1950/configs"
cp "${ROOT_DIR}/scripts/sources.lock.sh" "${temporary}/scripts/"
cp "${ROOT_DIR}/buildroot/external/rx1950/Config.in" \
   "${ROOT_DIR}/buildroot/external/rx1950/external.mk" \
   "${temporary}/buildroot/external/rx1950/"
cp "${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig" \
   "${ROOT_DIR}/buildroot/external/rx1950/configs/busybox.fragment" \
   "${temporary}/buildroot/external/rx1950/configs/"
cp -R "${ROOT_DIR}/buildroot/external/rx1950/patches" \
   "${temporary}/buildroot/external/rx1950/"

printf '\n# cache-key comment probe\n' >> "${temporary}/buildroot/external/rx1950/configs/rx1950_defconfig"
printf '\n# cache-key comment probe\n' >> "${temporary}/buildroot/external/rx1950/external.mk"
comment_key="$(RX1950_CACHE_ROOT="${temporary}" "${ROOT_DIR}/scripts/cache-key.sh" rootfs)"
[[ "${comment_key}" == "${rootfs_key}" ]] || die 'comments unexpectedly invalidate rootfs state'
sed -i 's/^Subject: .*/Subject: [PATCH] cache metadata probe/' \
    "${temporary}/buildroot/external/rx1950/patches/xterm/0001-linux-musl-fix-pty-session-and-retry.patch"
metadata_key="$(RX1950_CACHE_ROOT="${temporary}" "${ROOT_DIR}/scripts/cache-key.sh" rootfs)"
[[ "${metadata_key}" == "${rootfs_key}" ]] || die 'patch mail metadata unexpectedly invalidates rootfs state'
sed -i 's/defined(__linux__)/defined(__FreeBSD__)/' \
    "${temporary}/buildroot/external/rx1950/patches/xterm/0001-linux-musl-fix-pty-session-and-retry.patch"
patch_key="$(RX1950_CACHE_ROOT="${temporary}" "${ROOT_DIR}/scripts/cache-key.sh" rootfs)"
[[ "${patch_key}" != "${rootfs_key}" ]] || die 'a package source patch does not invalidate rootfs state'
cp "${ROOT_DIR}/buildroot/external/rx1950/patches/xterm/0001-linux-musl-fix-pty-session-and-retry.patch" \
   "${temporary}/buildroot/external/rx1950/patches/xterm/"
sed -i 's/^BR2_CCACHE=y$/# BR2_CCACHE is not set/' \
    "${temporary}/buildroot/external/rx1950/configs/rx1950_defconfig"
config_key="$(RX1950_CACHE_ROOT="${temporary}" "${ROOT_DIR}/scripts/cache-key.sh" rootfs)"
[[ "${config_key}" != "${rootfs_key}" ]] || die 'a real Kconfig change does not invalidate rootfs state'

require_text 'rootfs_cache: ${{ steps.meta.outputs.rootfs_cache }}' "${WORKFLOW}" \
    'Plan does not export the semantic rootfs cache key'
require_text 'group: rx1950-rootfs-${{ needs.plan.outputs.rootfs_cache }}' "${WORKFLOW}" \
    'rootfs builds with the same state are not serialized'
require_text 'key: rx1950-buildroot-output-v7-${{ runner.os }}-${{ needs.plan.outputs.rootfs_cache }}' "${WORKFLOW}" \
    'Buildroot output does not use the semantic exact key'
require_text "hashFiles('scripts/sources.lock.sh')" "${WORKFLOW}" \
    'download caches are not keyed by the pinned source lock'
require_text 'key: rx1950-buildroot-ccache-v1-' "${WORKFLOW}" \
    'Buildroot compiler cache is missing'
require_text 'jwm-dirclean' \
    "${ROOT_DIR}/scripts/build.sh" \
    'local packages can be hidden by a restored Buildroot state'
require_text "steps.rootfs-validate.outcome == 'success'" "${WORKFLOW}" \
    'unvalidated Buildroot output could be saved'

if grep -Fq "hashFiles('scripts/build.sh')" "${WORKFLOW}"; then
    die 'download cache still depends on build orchestration'
fi
if grep -Eq '^  packages:' "${WORKFLOW}"; then
    die 'package feed must share the verified rootfs Buildroot state'
fi
[[ "$(grep -Fc 'bash scripts/build-opkg-feed.sh' "${WORKFLOW}")" -eq 1 ]] ||
    die 'package feed must be built exactly once'
if grep -Fq 'actions/cache@v4' "${WORKFLOW}" ||
   grep -Fq 'actions/cache/restore@v4' "${WORKFLOW}" ||
   grep -Fq 'actions/cache/save@v4' "${WORKFLOW}"; then
    die 'obsolete cache action version remains in the workflow'
fi

rootfs_restore="$(awk '
    /- name: Restore reusable Buildroot state/ { section=1 }
    section && /- name:/ && !/Restore reusable Buildroot state/ { exit }
    section { print }
' "${WORKFLOW}")"
[[ -n "${rootfs_restore}" ]] || die 'Buildroot restore step is missing'
if grep -Fq 'restore-keys:' <<<"${rootfs_restore}"; then
    die 'Buildroot output permits an inexact prefix restore'
fi

grep -Fxq 'BR2_CCACHE=y' "${ROOT_DIR}/buildroot/external/rx1950/configs/rx1950_defconfig" ||
    die 'Buildroot ccache is not enabled'

printf 'cache contract validation passed (rootfs key %s)\n' "${rootfs_key}"
