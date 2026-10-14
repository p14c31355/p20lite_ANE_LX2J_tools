#!/bin/bash
# Build the single-candidate marks probe (WCH0 + fallback) and verify it.
#
# Same band machinery as ane_marks_probe.S; the candidate list is frozen to
# WCH0 (the channel whose DATA_ADDR0 target is the live scan buffer, per the
# rch-probe2 fill + the old paint probe's negative result on the read
# channels). A single painter cannot interleave with itself, so the visible
# pattern is readable.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_marks_wch0.XXXXXX)
mkdir -p artifacts

echo "== assemble (device only; the logic is a subset of the QEMU-proven full build)"
aarch64-linux-gnu-as \
  --defsym RCH_WCH0_BASE=0xE865A000 \
  --defsym FALLBACK_BASE=0x31000000 --defsym MARKS_BASE=0x348DF000 \
  --defsym FILL_LEN=0x800000 --defsym BAND=0x80000 \
  --defsym RAMO_WIN_START=0x34800000 --defsym RAMO_WIN_END=0x34900000 \
  --defsym SPIN_HOLD=0x60000000 --defsym HOLD_REPEATS=18 \
  -o "$WORK/device.o" ane_marks_probe_wch0.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/device.elf" "$WORK/device.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/device.elf" "$WORK/device.payload"
echo "  device payload: $(stat -c %s "$WORK/device.payload") bytes"

echo
echo "== static proof: the single channel base, from the device build"
python3 tools/verify_base_loads.py "$WORK/device.elf" w19 0xE865A000 || exit 1

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
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-marks-probe-wch0.img --gzip | head -3
python3 mkane_stock_embed.py "$WORK/device.Image" artifacts/fullerene-ane-marks-probe-wch0-stock.img

echo
echo "== results"
ls -la artifacts/fullerene-ane-marks-probe-wch0*.img
echo "device readout: band 0 white + one band per step mark;"
echo "  band k colour = PAL[k%8] = white green blue yellow cyan magenta red orange"
echo "  8 clean bands = the kill build's record 123456F (7 marks)"
