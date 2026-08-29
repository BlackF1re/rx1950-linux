#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-or-later
# Pinned remote inputs. This file is also the sole cache-key input for the
# verified download caches, so changes to build orchestration do not duplicate
# immutable source archives.

readonly BUILDROOT_VERSION="2025.02.2"
readonly BUILDROOT_SHA256="4a74e9a6f82ef8660ae2ef865d0ad61a4e9ccd67e2aeef885cae1165581ed5ac"
readonly KERNEL_VERSION="6.2"
readonly KERNEL_SHA256="74862fa8ab40edae85bb3385c0b71fe103288bce518526d63197800b3cbdecb1"
readonly WIRELESS_REGDB_VERSION="2025.02.20"
readonly WIRELESS_REGDB_SHA256="57f8e7721cf5a880c13ae0c202edbb21092a060d45f9e9c59bcd2a8272bfa456"
readonly ACX_REPOSITORY="https://github.com/piernov/acx-mac80211.git"
readonly ACX_COMMIT="a282ba2502ac3b10cb6dbf16a35f7ad54e759779"
readonly ACX_FIRMWARE_VERSION="1.4p6"
readonly ACX_FIRMWARE_SHA256="47719a4ecb0e2a486e376e40fae8c79e56233b3cd88150e8c55a92879b4819a8"
readonly HARET_VERSION="2011-06-07-rx1950"
readonly HARET_SHA256="5831d7cc8aba6ebd08709893101deca9da78e38ecde519a57adedfb164c86902"
readonly KERNEL_OFFSET=0x1000000
readonly KERNEL_ZRELADDR=0x8000
