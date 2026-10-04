#!/bin/bash
# Collect the hardware facts the ANE port needs, straight from the running system:
#   /proc/iomem        - physical memory map as the kernel sees it
#   /proc/device-tree  - the device tree the LK handed over (as a filesystem)
#   /sys/firmware/fdt  - the same thing flattened, if this kernel exposes it
#   /proc/cmdline      - boot arguments
set -u
cd /home/placeless/dev/p20-root
OUT=firmware/ane_dtb
mkdir -p "$OUT"

echo "############ physical memory map"
timeout 40 adb shell 'cat /proc/iomem 2>&1 | head -40' 2>&1 | head -42

echo
echo "############ cmdline"
timeout 30 adb shell 'cat /proc/cmdline' 2>&1 | head -3

echo
echo "############ is /sys/firmware/fdt there?"
timeout 30 adb shell 'ls -la /sys/firmware/fdt 2>&1' 2>&1 | head -3
if timeout 30 adb shell '[ -f /sys/firmware/fdt ]' 2>/dev/null; then
  timeout 60 adb pull /sys/firmware/fdt "$OUT/fdt.dtb" 2>&1 | tail -1
  python3 - "$OUT/fdt.dtb" <<'PY'
import struct, sys, os
p = sys.argv[1]
if os.path.exists(p):
    d = open(p, "rb").read()
    print(f"  fdt.dtb: {len(d):,} bytes, magic={d[:4]!r}")
    if d[:4] == b"\xd0\x0d\xfe\xed":
        tot, = struct.unpack_from(">I", d, 4)
        print(f"  totalsize={tot:,}")
        for w in (b"hisi", b"kirin", b"uart", b"dwc3", b"dsi", b"memory@"):
            print(f"    {w.decode():12} {d.count(w)}")
PY
else
  echo "  not exposed; falling back to /proc/device-tree"
fi

echo
echo "############ device-tree as a filesystem"
timeout 40 adb shell 'ls /proc/device-tree/ 2>&1 | head -25' 2>&1 | head -27
echo "--- memory sizes (reg cells):"
timeout 40 adb shell 'for d in /proc/device-tree/memory*/; do echo "== $d"; ls "$d"; od -A x -t x4 "$d/reg" 2>/dev/null | head -3; done' 2>&1 | head -14

echo
echo "############ archive the whole device-tree filesystem"
timeout 120 adb shell 'cd /proc && tar cf /data/local/tmp/device-tree.tar device-tree 2>/dev/null; ls -la /data/local/tmp/device-tree.tar' 2>&1 | tail -2
timeout 120 adb pull /data/local/tmp/device-tree.tar "$OUT/device-tree.tar" 2>&1 | tail -1
cd "$OUT" && tar xf device-tree.tar 2>/dev/null && du -sh device-tree 2>/dev/null && ls device-tree | head -20
