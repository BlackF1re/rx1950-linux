#!/bin/sh
set -eu

mkdir -p output

# Build pipeline entry point.
# Buildroot integration will generate the final SD image here.

printf 'Preparing rx1950-linux build environment\n'
