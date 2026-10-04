#!/bin/bash
# One command from source to a verified, flashable ANE-LX2J image.
#
# Builds the `ane` platform with flasks, packages the three payload variants and
# runs the mechanical validator. Every step prints what it checked; the exit code
# is nonzero if any check failed, so a morning device session can trust that what
# it is about to flash passed the host-side gates.
set -eu
FULLERENE=/home/placeless/dev/fullerene
HERE=$(cd "$(dirname "$0")" && pwd)

echo "== build (flasks, platform ane)"
cd "$FULLERENE"
OUT=$(cargo run -q -p flasks -- build --arch aarch64 --platform ane 2>&1)
echo "$OUT" | tail -4

IMAGE=$(printf '%s\n' "$OUT" | sed -n 's/^AArch64 Image built at //p' | tail -1)
if [ -z "$IMAGE" ] || [ ! -f "$IMAGE" ]; then
  echo "FAIL: could not locate the built Image"
  exit 1
fi
ELF=${IMAGE%.Image}

echo
echo "== package"
cd "$HERE"
bash ane_pack.sh "$IMAGE"

echo
echo "== validate"
python3 validate_ane_image.py "$ELF" artifacts/fullerene-ane.img "$IMAGE"

echo
echo "== flashable artefacts in $HERE/artifacts"
ls -la artifacts/fullerene-ane.img artifacts/fullerene-ane-raw.img artifacts/fullerene-ane-lz4.img 2>/dev/null
