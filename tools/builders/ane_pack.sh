#!/bin/bash
# Package a built Fullerene aarch64 Image for the ANE-LX2J.
#
# Two payload variants are produced because the loader's decompression contract
# is an experiment: the stock kernel's payload is gzip, so gzip is the first
# candidate, and the raw Image is the control for "does the loader accept an
# uncompressed payload at all".
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
IMAGE=${1:?usage: ane_pack.sh <fullerene-kernel-aarch64.Image> [outdir]}
OUTDIR=${2:-$HERE/artifacts}
mkdir -p "$OUTDIR"

echo "== source image"
ls -la "$IMAGE"
python3 - "$IMAGE" <<'PY'
import struct, sys
d = open(sys.argv[1], "rb").read()
print(f"  size       : {len(d):,}")
print(f"  magic@0x38 : {d[0x38:0x3c]!r}")
code0, = struct.unpack_from("<I", d, 0)
print(f"  code0      : {code0:#010x}  (entry stub branches +0x40)")
PY

echo
echo "== gzip payload (matches the stock kernel's format)"
python3 "$HERE/mkane_bootimg.py" "$IMAGE" "$OUTDIR/fullerene-ane.img" --gzip

echo
echo "== raw payload (control)"
python3 "$HERE/mkane_bootimg.py" "$IMAGE" "$OUTDIR/fullerene-ane-raw.img"

echo
echo "== lz4 payload (second control; the Bramble flow uses lz4)"
LZ4=${IMAGE%.Image}.Image.lz4
if [ -f "$LZ4" ]; then
  python3 "$HERE/mkane_bootimg.py" "$LZ4" "$OUTDIR/fullerene-ane-lz4.img"
else
  echo "  (no $LZ4; skipped)"
fi

echo
echo "== results"
ls -la "$OUTDIR"/fullerene-ane*.img
