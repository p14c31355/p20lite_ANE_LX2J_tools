#!/bin/bash
# Read back what the last Fullerene boot left in the ANE-LX2J's pstore window.
#
# The window is the device tree's `/ramoops` node over `pstore-mem`
# (0x34800000, 1 MiB): three dmesg record slots, a console zone at 0x60000 and
# the pmsg zone at 0xE0000, which is where the durable text log is appended.
#
# Two measured facts shaped this script:
#   * the pstore files are root-only, so it runs through the exploit that
#     unlocked the device;
#   * Android's `head` has no `-c`, and binary through an `adb shell` pipe can
#     be mangled - so the files are copied on the device and pulled whole.
set -u
cd "$(dirname "$0")" || exit 1
OUT=firmware/ane_pstore_readback
mkdir -p "$OUT"
STAMP=$(date +%m%d_%H%M%S)
DUMP="$OUT/pstore_$STAMP.txt"

if ! timeout 15 adb devices 2>/dev/null | awk 'NR==2{print $2}' | grep -q device; then
  echo "device is not on adb - nothing to read"
  exit 1
fi

cat > /tmp/anerd.sh <<'INNER'
echo "=== pstore listing ==="
ls -la /sys/fs/pstore/ 2>&1
echo "=== copying out (root) ==="
cat /sys/fs/pstore/pmsg-ramoops-0 > /data/local/tmp/pmsg.bin 2>/dev/null
echo "pmsg: $(stat -c %s /data/local/tmp/pmsg.bin 2>/dev/null) bytes"
cat /sys/fs/pstore/console-ramoops-0 > /data/local/tmp/console.bin 2>/dev/null
echo "console: $(stat -c %s /data/local/tmp/console.bin 2>/dev/null) bytes"
for f in /sys/fs/pstore/dmesg-ramoops-*; do
  [ -f "$f" ] || continue
  n=$(basename "$f")
  cat "$f" > "/data/local/tmp/$n.bin" 2>/dev/null
  echo "$n: $(stat -c %s /data/local/tmp/$n.bin 2>/dev/null) bytes"
done
chmod 666 /data/local/tmp/pmsg.bin /data/local/tmp/console.bin /data/local/tmp/dmesg-ramoops-*.bin 2>/dev/null
echo "=== done ==="
exit
INNER

for attempt in 1 2 3 4 5 6; do
  OUTTXT=$(timeout 240 adb shell /data/local/tmp/cve-2019-2215 < /tmp/anerd.sh 2>&1 | tr -d '\000')
  if echo "$OUTTXT" | grep -q "=== done ==="; then
    printf '%s\n' "$OUTTXT" > "$DUMP"
    echo "saved $DUMP"
    echo
    sed -n '/=== pstore listing ===/,/=== done ===/p' "$DUMP"
    break
  fi
  echo "  [attempt $attempt: no root shell]"
  sleep 5
done

echo
echo "== pull the copies"
for f in pmsg console; do
  timeout 120 adb pull /data/local/tmp/$f.bin "$OUT/$f.bin" 2>&1 | tail -1
done
timeout 60 adb shell 'ls /data/local/tmp/dmesg-ramoops-*.bin' 2>/dev/null | tr -d '\r' | while read -r f; do
  [ -n "$f" ] && timeout 120 adb pull "$f" "$OUT/$(basename "$f")" 2>&1 | tail -1
done

echo
echo "== pmsg content (the durable log)"
python3 - "$OUT/pmsg.bin" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1])
if not p.exists():
    print("  (no pmsg.bin)")
    sys.exit(0)
d = p.read_bytes()
print(f"  {len(d)} bytes: {d[:64].hex(' ')}")
text = d[12:] if len(d) > 12 and d[:4] == b"DBGC" else d
print(f"  as text: {text[:120]!r}")
PY

echo
echo "== probe/durable markers in every channel"
python3 - "$OUT" <<'PY'
import pathlib, sys
out = pathlib.Path(sys.argv[1])
markers = {
    b"FULLERENE-ANE-PROBE-DMESG": "dmesg  slot 0",
    b"FULLERENE-ANE-PROBE-CONSOLE": "console zone",
}
found_any = False
for name in ("dmesg-ramoops-0.bin", "console.bin", "pmsg.bin"):
    p = out / name
    if not p.exists() or p.stat().st_size == 0:
        print(f"  {name:24} absent or empty")
        continue
    d = p.read_bytes()
    hits = [label for m, label in markers.items() if m in d]
    print(f"  {name:24} {len(d):>7} bytes  markers: {', '.join(hits) if hits else '-'}")
    if b"\n001:E" in d:
        print("      -> contains \\n001:E (the pmsg record)")
    if hits:
        found_any = True
        # show the region around the marker for the record
        for m, label in markers.items():
            i = d.find(m)
            if i >= 0:
                start = max(0, i - 32)
                print(f"      {label}: ...{d[start:i+len(m)+8]!r}")
if found_any:
    print("  => the probe's record survived to a reader (the loader entered our code)")
else:
    print("  => no probe marker in any surviving channel")
PY

echo
echo "== durable log candidates (segment markers + record letters)"
for f in "$OUT"/dmesg-ramoops-0.bin "$OUT"/console.bin "$OUT"/pmsg.bin; do
  [ -f "$f" ] || continue
  echo "--- $(basename "$f")"
  grep -aoE '[0-9]{3}:[brE0-9RFCHz]+' "$f" 2>/dev/null | head -3
done
