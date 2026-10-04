#!/bin/bash
# Get the real device tree the LK hands to the kernel.
#
# The dts partition is a proprietary "HSDT" container, so the reliable source is the
# running system: /sys/firmware/fdt is the flattened tree the kernel received, and
# /proc/device-tree is the same thing as a filesystem.
set -u
cd /home/placeless/dev/p20-root
OUT=firmware/ane_dtb
mkdir -p "$OUT"

echo "############ is there a raw fdt?"
timeout 30 adb shell 'ls -la /sys/firmware/fdt 2>&1; ls /sys/firmware/ 2>&1' 2>&1 | head -8

echo
echo "############ pull it if it exists"
if timeout 30 adb shell '[ -f /sys/firmware/fdt ]' 2>/dev/null; then
  timeout 120 adb pull /sys/firmware/fdt "$OUT/fdt.dtb" 2>&1 | tail -1
  ls -la "$OUT/fdt.dtb" 2>/dev/null
  python3 - "$OUT/fdt.dtb" <<'PY'
import struct, sys, os
p = sys.argv[1]
if os.path.exists(p):
    d = open(p, "rb").read()
    print(f"  size: {len(d):,}")
    print(f"  magic: {d[:4]!r}  (should be b'\\xd0\\x0d\\xfe\\xed')")
    if d[:4] == b"\xd0\x0d\xfe\xed":
        tot, = struct.unpack_from(">I", d, 4)
        print(f"  totalsize field: {tot:,}")
        # count strings that name hardware
        for w in (b"hisi", b"kirin", b"hi6", b"uart", b"pl011", b"dwc3", b"usb", b"dsi", b"panel", b"memory"):
            print(f"    {w.decode():10} {d.count(w)}")
PY
else
  echo "  no /sys/firmware/fdt on this kernel"
fi

echo
echo "############ the device-tree filesystem, for the memory map and hardware nodes"
timeout 60 adb shell 'ls /proc/device-tree/ 2>&1 | head -30' 2>&1 | head -32
echo "--- memory nodes:"
timeout 60 adb shell 'for d in /proc/device-tree/memory*; do echo "== $d"; ls "$d"; hexdump -C "$d/reg" 2>/dev/null | head -2 || od -A x -t x1 "$d/reg" 2>/dev/null | head -2; done' 2>&1 | head -20
