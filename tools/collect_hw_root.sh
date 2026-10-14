#!/bin/bash
# Read the hardware facts as root. The shell user cannot open /proc/iomem,
# /proc/cmdline, /sys/firmware/fdt or the device-tree contents at all, but root
# can - and the exploit we already have on the device provides it.
set -u
cd /home/placeless/dev/p20-root
OUT=firmware/ane_dtb
mkdir -p "$OUT"

cat > /tmp/hw.sh <<'INNER'
id
echo "=== Memory map ==="
cat /proc/iomem
echo "=== cmdline ==="
cat /proc/cmdline
echo "=== fdt present? ==="
ls -la /sys/firmware/fdt
echo "=== device-tree tar ==="
cd /proc
tar cf /data/local/tmp/device-tree.tar device-tree
chmod 666 /data/local/tmp/device-tree.tar
ls -la /data/local/tmp/device-tree.tar
echo "=== fdt copy ==="
dd if=/sys/firmware/fdt of=/data/local/tmp/fdt.dtb 2>/dev/null
chmod 666 /data/local/tmp/fdt.dtb 2>/dev/null
ls -la /data/local/tmp/fdt.dtb 2>/dev/null
echo "=== done ==="
exit
INNER

for attempt in 1 2 3 4 5 6; do
  OUTTXT=$(timeout 240 adb shell /data/local/tmp/cve-2019-2215 < /tmp/hw.sh 2>&1 | tr -d '\000')
  if echo "$OUTTXT" | grep -aq "=== done ==="; then
    echo "$OUTTXT" | sed -n '/=== Memory map ===/,/=== done ===/p' | head -70
    break
  fi
  echo "  [attempt $attempt: no root shell]"
done

echo
echo "############ pull the artefacts"
for F in device-tree.tar fdt.dtb; do
  timeout 120 adb pull /data/local/tmp/$F "$OUT/$F" 2>&1 | tail -1
done
ls -la "$OUT/"
[ -f "$OUT/device-tree.tar" ] && { cd "$OUT" && rm -rf device-tree && tar xf device-tree.tar && du -sh device-tree && ls device-tree | head -25; }
[ -f "$OUT/fdt.dtb" ] && python3 - "$OUT/fdt.dtb" <<'PY'
import struct, sys, os
p = sys.argv[1]
d = open(p, "rb").read()
print(f"  fdt.dtb: {len(d):,} bytes, magic={d[:4]!r}")
if d[:4] == b"\xd0\x0d\xfe\xed":
    tot, = struct.unpack_from(">I", d, 4)
    print(f"  totalsize={tot:,}")
    for w in (b"hisi", b"kirin", b"uart", b"dwc3", b"dsi", b"memory@"):
        print(f"    {w.decode():12} {d.count(w)}")
PY
