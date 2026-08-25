#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/output"

mkdir -p "$OUTPUT_DIR"

echo "Preparing rx1950-linux build environment"

echo "Build stages will be added as kernel and root filesystem integration progresses"
