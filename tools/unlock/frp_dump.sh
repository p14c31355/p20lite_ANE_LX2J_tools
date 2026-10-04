#!/bin/bash
# Diagnostics before asking for the one UI step:
#  - the AOSP unlock-ability verb, if this bootloader knows it
#  - the frp partition contents (it is ro.frp.pst, i.e. the persistent store the
#    OEM-unlock toggle writes to on AOSP-derived builds)
set -u
cd /home/placeless/dev/p20-root

echo "############ fastboot: does it report the unlock ability?"
timeout 30 fastboot devices 2>&1 | head -2
for V in "flashing get_unlock_ability" "getvar oem-unlock-allowed" "getvar unlock_ability" "oem get-security-info"; do
  printf '%-34s : ' "$V"
  timeout 30 fastboot $V 2>&1 | head -2 | tr '\n' ' '
  echo
done

echo
echo "############ back to Android for the frp dump"
timeout 60 fastboot reboot 2>&1 | head -1
sleep 30
for i in $(seq 1 30); do
  ST=$(timeout 20 adb devices 2>/dev/null | awk 'NR==2{print $2}')
  [ "$ST" = "device" ] && { echo "  adb: device"; break; }
  sleep 10
done

cat > /tmp/frp_read.sh <<'INNER'
id
echo "=== frp dump ==="
dd if=/dev/block/bootdevice/by-name/frp of=/data/local/tmp/frp.bin bs=4096
od -A x -t x1z -N 192 /data/local/tmp/frp.bin
echo "=== frp tail (last 64 bytes) ==="
SZ=$(stat -c%s /data/local/tmp/frp.bin)
od -A x -t x1z -j $((SZ-64)) /data/local/tmp/frp.bin | head -6
echo "=== non-zero byte count ==="
od -A d -t x1 /data/local/tmp/frp.bin | grep -v "^[0-9]* 00 00" | wc -l
exit
INNER
for attempt in 1 2 3 4 5; do
  OUT=$(timeout 200 adb shell /data/local/tmp/cve-2019-2215 < /tmp/frp_read.sh 2>&1 | tr -d '\000')
  echo "$OUT" | grep -aq "uid=0(root)" && { echo "$OUT" | tail -30; break; }
  echo "  [attempt $attempt lost the race]"; sleep 20
done
