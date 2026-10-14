#!/bin/bash
# Build the G1-v2 marks probe (low-window gate) and verify.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_marks_g1b.XXXXXX)
mkdir -p artifacts

echo "== assemble (device only; logic subset of the QEMU-proven full build)"
aarch64-linux-gnu-as \
  --defsym RCH_G1_BASE=0xE8640000 \
  --defsym MARKS_BASE=0x348DF000 \
  --defsym FILL_LEN=0x800000 --defsym BAND=0x80000 \
  --defsym RAMO_WIN_START=0x34800000 --defsym RAMO_WIN_END=0x34900000 \
  --defsym SPIN_HOLD=0x60000000 --defsym HOLD_REPEATS=18 \
  -o "$WORK/device.o" ane_marks_probe_g1b.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/device.elf" "$WORK/device.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/device.elf" "$WORK/device.payload"
echo "  device payload: $(stat -c %s "$WORK/device.payload") bytes"

echo
echo "== static proof: the single channel base, from the device build"
python3 tools/verify_base_loads.py "$WORK/device.elf" w19 0xE8640000 || exit 1

echo
echo "== build the Linux arm64 Image and package (tiny + stock-embedded)"
python3 - "$WORK" <<'PY'
import struct, sys, pathlib
work = pathlib.Path(sys.argv[1])
payload = (work / "device.payload").read_bytes()
header = bytearray(64)
struct.pack_into("<II", header, 0, 0x14000010, 0xD503201F)
struct.pack_into("<Q", header, 8, 0x80000)
struct.pack_into("<Q", header, 16, 0x400000)
struct.pack_into("<Q", header, 24, 0x2)
header[0x38:0x3C] = b"ARM\x64"
(work / "device.Image").write_bytes(bytes(header) + payload)
print(f"  device.Image: {len(header) + len(payload)} bytes")
PY
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-marks-probe-g1b.img --gzip | head -3
python3 mkane_stock_embed.py "$WORK/device.Image" artifacts/fullerene-ane-marks-probe-g1b-stock.img

echo
echo "== results"
ls -la artifacts/fullerene-ane-marks-probe-g1b*.img
echo "device readout: band 0 white + one band per step mark;"
echo "  8 clean bands = the kill build's record 123456F (7 marks)"
