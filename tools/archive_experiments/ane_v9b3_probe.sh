#!/bin/bash
# v9b: the USB bring-up (the l1d3 sequence) plus the console renderer (the v8
# probe), one image. The bring-up writes its step/readback traces into the
# L1D_TRACE_BASE window, then the renderer draws them on the screen - all in
# the same boot, then holds. Cross-boot handoff is impossible on this device
# (the loader re-initialises DRAM every boot; measured six times), which is
# why the writer and the renderer must live in one payload.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_v9b.XXXXXX)
mkdir -p artifacts

echo "== assemble (device)"
aarch64-linux-gnu-as \
  --defsym RCH_VG0_BASE=0xE8620000 --defsym RCH_VG1_BASE=0xE8628000 \
  --defsym RCH_G0_BASE=0xE8638000  --defsym RCH_G1_BASE=0xE8640000 \
  --defsym RCH_D0_BASE=0xE8650000  --defsym RCH_D1_BASE=0xE8651000 \
  --defsym RCH_D2_BASE=0xE8652000  --defsym RCH_D3_BASE=0xE8653000 \
  --defsym RCH_WCH0_BASE=0xE865A000 --defsym RCH_WCH1_BASE=0xE865C000 \
  --defsym MARKS_BASE=0x348DF000 \
  --defsym CORE_BASE=0xff100000 --defsym CRG_BASE=0xfff35000 \
  --defsym PCTRL_BASE=0xe8a09000 --defsym AHBIF_BASE=0xff200000 \
  --defsym WITH_ABB=1 --defsym PMIC_BASE=0xfff34000 --defsym SCTRL_BASE=0xfff0a000 \
  --defsym WITH_CORE=1 --defsym PHY_BASE=0xfe000000 \
  --defsym WITH_TRACE=1 --defsym WITH_SMC=0 \
  --defsym SPIN_US=0x8000 --defsym SPIN_MS=0x80000 \
  --defsym TRACE_BASE=0x348DF100 --defsym L1D_TRACE_BASE=0x348DF100 \
  --defsym PMSG_BASE=0x348E0000 \
  --defsym FTLX_BASE=0x348D0000 \
  --defsym TEXT_Y=110 \
  --defsym USB_CORE=0xFF100000 --defsym USB_AHB=0xFF200000 \
  --defsym FALLBACK_BASE=0x31000000 \
  --defsym TEXT_BUF=0x1AE2000 --defsym BITMAP=0x1AE3000 \
  --defsym BITMAP_LEN=0x210000 --defsym RENDER_LEN=0x210000 \
  --defsym P_LO=0x1AE0000 --defsym P_HI=0x1B10000 \
  --defsym GATE_HI=0xC0000000 --defsym SKIP_P=1 \
  --defsym RAMO_WIN_START=0x34800000 --defsym RAMO_WIN_END=0x34900000 \
  --defsym SPIN_HOLD=0x60000000 --defsym HOLD_REPEATS=18 \
  --defsym WITH_SEED=0 \
  -o "$WORK/device.o" ane_v9b_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/device.elf" "$WORK/device.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/device.elf" "$WORK/device.payload"
echo "  device payload: $(stat -c %s "$WORK/device.payload") bytes"

echo
echo "== build the Linux arm64 Image (64-byte header, as Fullerene's)"
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
python3 mkane_stock_embed.py "$WORK/device.Image" artifacts/fullerene-ane-v9b3-stock.img | tail -2
ls -la artifacts/fullerene-ane-v9b3-stock.img
