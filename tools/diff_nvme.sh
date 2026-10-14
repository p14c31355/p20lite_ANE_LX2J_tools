#!/bin/bash
# Dump the whole nvme partition and compare it with the backup taken before we wrote
# anything. That shows exactly what has changed since - including what happened to
# USRKEY when the OEM-unlock toggle was enabled.
set -u
cd /home/placeless/dev/p20-root

cat > /tmp/dnvme.sh <<'INNER'
id
dd if=/dev/block/bootdevice/by-name/nvme of=/data/local/tmp/nvme_now.bin bs=4096
chmod 666 /data/local/tmp/nvme_now.bin
ls -la /data/local/tmp/nvme_now.bin
echo "=== done ==="
exit
INNER

for attempt in 1 2 3 4 5 6; do
  OUT=$(timeout 240 adb shell /data/local/tmp/cve-2019-2215 < /tmp/dnvme.sh 2>&1 | tr -d '\000')
  echo "$OUT" | grep -aq "=== done ===" && { echo "$OUT" | grep -aE "records|nvme_now|done" | head -4; break; }
  echo "  [attempt $attempt: no root shell]"
done

echo
timeout 120 adb pull /data/local/tmp/nvme_now.bin firmware/nvme_now.bin 2>&1 | tail -1
ls -la firmware/nvme_now.bin firmware/nvme_backup_*.bin 2>/dev/null

echo
echo "############ diff against the backup"
python3 - <<'PY'
import glob, os
now = "firmware/nvme_now.bin"
bk = sorted(glob.glob("firmware/nvme_backup_*.bin"))
if not bk:
    print("no backup found"); raise SystemExit
bk = bk[-1]
a = open(bk, "rb").read()
b = open(now, "rb").read()
print(f"backup : {bk} ({len(a):,} bytes)")
print(f"now    : {now} ({len(b):,} bytes)")
n = min(len(a), len(b))
diffs = [i for i in range(n) if a[i] != b[i]]
print(f"differing bytes: {len(diffs)}")
if diffs:
    # group into ranges
    runs, s, p = [], diffs[0], diffs[0]
    for i in diffs[1:]:
        if i - p > 8:
            runs.append((s, p)); s = i
        p = i
    runs.append((s, p))
    for x, y in runs[:20]:
        ctx = max(0, x - 16)
        print(f"  0x{x:06x}..0x{y:06x} ({y-x+1} bytes)")
        print(f"    before: {a[ctx:x+16].hex()}")
        print(f"    after : {b[ctx:x+16].hex()}")
PY
