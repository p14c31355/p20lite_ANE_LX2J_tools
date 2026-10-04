#!/bin/bash
# Restore the original frp partition (recovery path).
#
# We wrote a patched frp image (flag field 0x24 set to 1, digest recomputed) and the
# device has not come back on adb or fastboot since. This puts the untouched image
# back as soon as we can reach it, returning the device to a known state.
set -u
cd /home/placeless/dev/p20-root

echo "############ device state"
timeout 15 fastboot devices 2>&1 | head -2
timeout 15 adb devices 2>&1 | tail -2

if timeout 15 adb devices 2>/dev/null | grep -q "device$"; then
  echo "  adb is up - restoring through the root shell"
  timeout 60 adb push firmware/partitions/frp.bin /data/local/tmp/frp_orig.bin 2>&1 | tail -1
  cat > /tmp/rfrp.sh <<'INNER'
id
chmod 666 /data/local/tmp/frp_orig.bin
dd if=/data/local/tmp/frp_orig.bin of=/dev/block/bootdevice/by-name/frp bs=4096
sync
echo "=== restored ==="
od -A x -t x1 -N 48 /dev/block/bootdevice/by-name/frp
echo "=== done ==="
exit
INNER
  for attempt in 1 2 3 4 5; do
    OUT=$(timeout 200 adb shell /data/local/tmp/cve-2019-2215 < /tmp/rfrp.sh 2>&1 | tr -d '\000')
    echo "$OUT" | grep -aq "=== done ===" && { echo "$OUT" | grep -aE "records|^0000|^0010|restored|done" | head -8; exit 0; }
    echo "  [attempt $attempt: no root shell yet]"
  done
  echo "  could not get root this round"
else
  echo "  adb not available yet - nothing to do from here"
  echo "  (when the device is back: run this script again, or hold volume-down +"
  echo "   power to reach fastboot, then 'fastboot reboot' to Android)"
fi
