#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

case "${1:-all}" in
  all)
    "${ROOT_DIR}/scripts/build.sh" rootfs
    "${ROOT_DIR}/scripts/build.sh" kernel
    "${ROOT_DIR}/scripts/build.sh" image
    ;;
  *)
    echo "delegating stage: $1"
    ;;
esac
