#!/bin/bash
# Full hands-free flash cycle for the ANE.
#
#   1. arm the LK-window catcher (product "Fastboot2.0" + serial match)
#   2. fire reboot-bootloader twice over pyusb - the EP1 OUT dispatch can
#      lag one transfer, so the second write releases the first command
#   3. wait for the catcher's FLASH OK (or its exit)
#   4. fastboot reboot, wait for the kernel's "ANE fastboot" product
#
# Usage: bash flash_cycle.sh artifacts/fullerene-ane-vNN-stock.img
set -u
ART="${1:?usage: flash_cycle.sh <artifact>}"
cd "$(dirname "$0")"
UV=/home/placeless/.hermes/bin/uv
SER=SCV7N18927000473

rm -f /tmp/catcher_out.txt /tmp/fb_send2_out.txt
(bash ane_catcher.sh "$ART" > /tmp/catcher_out.txt 2>&1) &
CAT=$!
sleep 1
"$UV" run --no-project --with pyusb python3 fb_send2.py reboot-bootloader > /tmp/fb_send2_out.txt 2>&1

for _ in $(seq 1 150); do
    if grep -q "FLASH OK" /tmp/catcher_out.txt 2>/dev/null; then break; fi
    if ! kill -0 "$CAT" 2>/dev/null; then break; fi
    sleep 1
done
kill "$CAT" 2>/dev/null

echo "--- catcher ---"
cat /tmp/catcher_out.txt
if ! grep -q "FLASH OK" /tmp/catcher_out.txt; then
    echo "FLASH FAILED"
    exit 1
fi

sleep 2
timeout 20 fastboot -s "$SER" reboot > /dev/null 2>&1
echo "--- waiting for the kernel ---"
for i in $(seq 1 45); do
    p=$(cat /sys/bus/usb/devices/1-1/product 2>/dev/null)
    if [ "$p" = "ANE fastboot" ]; then
        echo "kernel up after ${i}s"
        exit 0
    fi
    sleep 1
done
echo "kernel not seen"
exit 2
