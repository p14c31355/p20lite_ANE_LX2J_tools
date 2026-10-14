#!/bin/bash
# Recovery + readback after a Fullerene/probe boot has left the device halted.
#
# The loader refuses `fastboot boot` on this device, so every experiment leaves
# the probe/kernel flashed in the kernel partition and the device halted (a
# `wfe` loop with the loader's USB torn down). Getting from there back to a
# readable state needs the power/volume buttons once:
#
#   Volume Down + Power  ->  fastboot mode
#
# After that this script restores the stock kernel, boots Android and pulls the
# pstore window back, which is where the probe's record (or Fullerene's durable
# log) is read from.
set -u
cd "$(dirname "$0")" || exit 1

echo "== waiting for fastboot (hold Volume Down + Power on the device)"
for _ in $(seq 1 600); do
  if timeout 6 fastboot devices 2>/dev/null | grep -q .; then
    break
  fi
  sleep 3
done
if ! timeout 10 fastboot devices 2>/dev/null | grep -q .; then
  echo "no fastboot device appeared; nothing was changed"
  exit 1
fi
echo "fastboot is up: $(timeout 10 fastboot devices 2>/dev/null | head -1)"

echo
echo "== restoring the stock kernel"
timeout 300 fastboot flash kernel firmware/kernel_stock.bin 2>&1 | tail -3
timeout 60 fastboot reboot 2>&1 | head -1

echo
echo "== waiting for Android"
for _ in $(seq 1 72); do
  ST=$(timeout 8 adb devices 2>/dev/null | awk 'NR==2{print $2}')
  if [ "$ST" = "device" ]; then
    echo "android is back"
    break
  fi
  sleep 5
done

echo
echo "== reading the pstore window"
bash ane_read_pstore.sh
