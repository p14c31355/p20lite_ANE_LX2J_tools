#!/bin/bash
# 1. Re-dump the partitions with the permissions adb can read, then pull them.
# 2. Investigate what implements the greyed-out OEM-unlock toggle: the oemlock HAL
#    tells us which store the bootloader and the OS agree on.
set -u
cd /home/placeless/dev/p20-root
OUT=firmware/partitions
mkdir -p "$OUT"

cat > /tmp/dump2.sh <<'INNER'
id
for P in frp oeminfo misc; do
  dd if=/dev/block/bootdevice/by-name/$P of=/data/local/tmp/$P.bin bs=4096 2>&1 | tail -1
done
chmod 666 /data/local/tmp/frp.bin /data/local/tmp/oeminfo.bin /data/local/tmp/misc.bin
ls -la /data/local/tmp/frp.bin /data/local/tmp/oeminfo.bin /data/local/tmp/misc.bin
echo "=== done ==="
exit
INNER

run_root() {
  local attempt out
  for attempt in 1 2 3 4 5 6; do
    out=$(timeout 240 adb shell /data/local/tmp/cve-2019-2215 < /tmp/dump2.sh 2>&1 | tr -d '\000')
    if echo "$out" | grep -aq "=== done ==="; then echo "$out"; return 0; fi
    echo "  [attempt $attempt lost the race]" >&2
    sleep 15
  done
  echo "$out"; return 1
}

echo "############ dump with readable permissions"
run_root | grep -aE "records|rw-|done" | tail -8

echo
echo "############ pull"
for P in frp oeminfo misc; do
  timeout 120 adb pull /data/local/tmp/$P.bin "$OUT/$P.bin" 2>&1 | tail -1
done
ls -la "$OUT/"

echo
echo "############ which HAL implements the OEM-unlock toggle?"
timeout 60 adb shell 'ls /vendor/lib64/hw/ 2>/dev/null | head -30' 2>&1
echo "--- oemlock-related libraries and services:"
timeout 60 adb shell 'ls -la /vendor/lib64/hw/*oem* /vendor/lib64/*oem* /vendor/bin/hw/*oem* 2>/dev/null' 2>&1 | head -10
echo "--- what does it reference?"
timeout 60 adb shell 'for f in /vendor/lib64/hw/*oemlock* /vendor/lib64/hw/android.hardware.oemlock*; do echo "== $f"; strings "$f" 2>/dev/null | grep -iE "persist|misc|frp|oeminfo|unlock|nvme|block" | head -12; done' 2>&1 | head -40
