#!/bin/bash
# Back the lock-relevant partitions up to the host BEFORE the unlock wipes /data.
#
# nvme is already saved. What is missing:
#   frp      (ro.frp.pst - the persistent store the OEM-unlock toggle writes to)
#   oeminfo  (device identity, and on Huawei often part of the lock story)
#   misc     (bootloader control block)
# And they are read with the root shell, so this needs the race won each time.
set -u
cd /home/placeless/dev/p20-root
OUT=firmware/partitions
mkdir -p "$OUT"

cat > /tmp/dump_parts.sh <<'INNER'
id
echo "=== dumping ==="
for P in frp oeminfo misc; do
  dd if=/dev/block/bootdevice/by-name/$P of=/data/local/tmp/$P.bin bs=4096 2>&1 | tail -1
  ls -la /data/local/tmp/$P.bin
done
echo "=== frp first 64 bytes ==="
od -A x -t x1 -N 64 /data/local/tmp/frp.bin
echo "=== frp strings ==="
strings /data/local/tmp/frp.bin | head -10
echo "=== oeminfo strings ==="
strings /data/local/tmp/oeminfo.bin | head -10
echo "=== misc strings ==="
strings /data/local/tmp/misc.bin | head -10
echo "=== done ==="
exit
INNER

run_root() {
  local attempt out
  for attempt in 1 2 3 4 5 6; do
    out=$(timeout 240 adb shell /data/local/tmp/cve-2019-2215 < /tmp/dump_parts.sh 2>&1 | tr -d '\000')
    if echo "$out" | grep -aq "=== done ==="; then echo "$out"; return 0; fi
    echo "  [attempt $attempt lost the race]" >&2
    sleep 15
  done
  echo "$out"; return 1
}

echo "############ dump"
run_root | grep -aE "=== |\.bin|^0000|^0010|^0020|^0030|uid=0" | head -40

echo
echo "############ pull them to the host"
for P in frp oeminfo misc; do
  timeout 120 adb pull /data/local/tmp/$P.bin "$OUT/$P.bin" 2>&1 | tail -1
done
ls -la "$OUT/"
md5sum "$OUT"/*.bin 2>/dev/null
