#!/bin/bash
# Build the L1d USB probe and prove its register sequence in QEMU first.
#
# l1d = l1c + a device-side trace (l1c ran with tracing off, so its on-device
# run left no record beyond "no attach on the host"), the AP PPLL0 enable, and
# post-attach readbacks. The device trace target 0x348c0000 sits inside the
# reserved pstore window - the same region the earlier pstore mark probes
# proved survives a reset - so a follow-up probe (or the visual channel, once
# the RCH track lands) can read it.
#
# The emulated variant retargets every base into QEMU RAM and turns on the
# trace, so the dump is a complete mechanical proof of the writes the device
# build will perform. On the device the read-modify-write steps read real
# register values, so only the OR-ed bits are identical - that is why the
# QEMU check pins the emulated starting values (zeroed RAM) and the device run
# is judged by the host seeing an attach.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
WORK=$(mktemp -d /tmp/ane_usb_l1.XXXXXX)
mkdir -p artifacts

echo "== assemble"
# device build: the real bases, no trace, hang (no SMC) so the attach is stable
aarch64-linux-gnu-as \
  --defsym CORE_BASE=0xff100000 --defsym CRG_BASE=0xfff35000 \
  --defsym PCTRL_BASE=0xe8a09000 --defsym AHBIF_BASE=0xff200000 \
  --defsym WITH_ABB=1 --defsym PMIC_BASE=0xfff34000 --defsym SCTRL_BASE=0xfff0a000 \
  --defsym WITH_CORE=1 --defsym PHY_BASE=0xfe000000 \
  --defsym TRACE_BASE=0x348DF100 --defsym WITH_TRACE=1 --defsym WITH_SMC=0 --defsym WDOG_BASE=0xe8a06000 \
  --defsym SPIN_US=0x8000 --defsym SPIN_MS=0x80000 --defsym SPIN_LONG=0x20000000 \
  -o "$WORK/device.o" ane_usb_livefeed_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/device.elf" "$WORK/device.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/device.elf" "$WORK/device.payload"
echo "  device payload: $(stat -c %s "$WORK/device.payload") bytes"
# also build the SMC-loop variant for when a live loop is wanted
aarch64-linux-gnu-as \
  --defsym CORE_BASE=0xff100000 --defsym CRG_BASE=0xfff35000 \
  --defsym PCTRL_BASE=0xe8a09000 --defsym AHBIF_BASE=0xff200000 \
  --defsym WITH_ABB=1 --defsym PMIC_BASE=0xfff34000 --defsym SCTRL_BASE=0xfff0a000 \
  --defsym WITH_CORE=1 --defsym PHY_BASE=0xfe000000 \
  --defsym TRACE_BASE=0x348DF100 --defsym WITH_TRACE=1 --defsym WITH_SMC=1 --defsym WDOG_BASE=0xe8a06000 \
  --defsym SPIN_US=0x8000 --defsym SPIN_MS=0x80000 --defsym SPIN_LONG=0x60000000 \
  -o "$WORK/loop.o" ane_usb_livefeed_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/loop.elf" "$WORK/loop.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/loop.elf" "$WORK/loop.payload"
echo "  loop   payload: $(stat -c %s "$WORK/loop.payload") bytes"

# qemu build: every base into its own RAM page, tracing on, short delays
aarch64-linux-gnu-as \
  --defsym CORE_BASE=0x42000000 --defsym CRG_BASE=0x42003000 \
  --defsym PCTRL_BASE=0x42004000 --defsym AHBIF_BASE=0x42005000 \
  --defsym WITH_ABB=1 --defsym PMIC_BASE=0x42006000 --defsym SCTRL_BASE=0x42007000 \
  --defsym PHY_BASE=0x42008000 \
  --defsym WITH_CORE=1 \
  --defsym TRACE_BASE=0x42001000 --defsym WITH_TRACE=1 --defsym WITH_SMC=0 \
  --defsym SPIN_US=0x10000 --defsym SPIN_MS=0x10000 --defsym SPIN_LONG=0x10000 \
  -o "$WORK/qemu.o" ane_usb_livefeed_probe.S
aarch64-linux-gnu-ld -Ttext=0 -e _start -o "$WORK/qemu.elf" "$WORK/qemu.o"
aarch64-linux-gnu-objcopy -O binary --only-section=.text "$WORK/qemu.elf" "$WORK/qemu.payload"
echo "  qemu   payload: $(stat -c %s "$WORK/qemu.payload") bytes"

echo
echo "== disassembly (device build): spot-check the five key writes"
aarch64-linux-gnu-objdump -d "$WORK/device.elf" | grep -E "str\s+w10, \[x1[23]" | head -12

echo
echo "== build the Linux arm64 Images (64-byte header, as Fullerene's)"
python3 - "$WORK" <<'PY'
import struct, sys, pathlib
work = pathlib.Path(sys.argv[1])
for variant in ("device", "loop", "qemu"):
    payload = (work / f"{variant}.payload").read_bytes()
    header = bytearray(64)
    struct.pack_into("<II", header, 0, 0x14000010, 0xD503201F)
    struct.pack_into("<Q", header, 8, 0x80000)
    struct.pack_into("<Q", header, 16, 0x400000)
    struct.pack_into("<Q", header, 24, 0x2)
    header[0x38:0x3C] = b"ARM\x64"
    (work / f"{variant}.Image").write_bytes(bytes(header) + payload)
    print(f"  {variant}.Image: {len(header) + len(payload)} bytes")
PY

echo
echo "== package the device images (gzip)"
python3 mkane_bootimg.py "$WORK/device.Image" artifacts/fullerene-ane-usb-livefeed.img --gzip | head -3
python3 mkane_bootimg.py "$WORK/loop.Image" artifacts/fullerene-ane-usb-livefeed-loop.img --gzip | head -3

# stock-size variant: the LK appears to require a full-size kernel slot
# (the 4KB probes never ran; the 11.6MB stock-embedded ones always do).
python3 mkane_stock_embed.py "$WORK/device.Image" artifacts/fullerene-ane-usb-livefeed-stock.img | tail -2

echo
echo "== marker check (device build): the LIFE constant must be in the payload"
aarch64-linux-gnu-objdump -d "$WORK/device.elf" | grep -E "movz..x10, #0x494c|movk..x10, #0x4546, lsl #16" | head -4
grep -c "4c494645" <(xxd -p "$WORK/device.payload") >/dev/null 2>&1
echo "LIVE_BUILD_EXIT=0"
