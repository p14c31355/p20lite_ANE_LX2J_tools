#!/bin/bash
# v89b: (T1) watch what the USB becomes after a version sacrifice;
#       (T2) single-send partition-size (no double) on the live kernel.
set -u
cd ~/dev/p20-root
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

echo "=== T1: sacrifice pattern, then watch USB for ~9s ==="
timeout 60 $UV fb_send2.py "getvar:version"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  sleep 0.75
  P=$(lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct | awk '{print $2, $3}')
  echo "t+$i: ${P:-GONE}"
done

echo "=== T2: single-send partition-size ==="
timeout 60 $UV fb_once.py "getvar:partition-size:kernel"
for i in 1 2 3 4 5 6 7 8; do
  sleep 0.75
  P=$(lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct | awk '{print $2, $3}')
  echo "t+$i: ${P:-GONE}"
done

if lsusb -v -d 18d1:d00d 2>/dev/null | grep -q "Fastboot2.0"; then
  echo "### LK up - reboot to kernel"
  timeout 60 fastboot -s SCV7N18927000473 reboot
  sleep 25
fi
echo "=== final USB ==="
lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct
date
