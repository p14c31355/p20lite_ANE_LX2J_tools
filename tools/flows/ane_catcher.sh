#!/bin/bash
# Catch the loader's fastboot window and flash the given artifact.
# The loader presents iProduct "Fastboot2.0"; the kernel's responder is
# "ANE fastboot" (and a wedged kernel can show garbage). Only a flash
# that reports "Finished" counts; everything else keeps waiting.
cd "$(dirname "$0")"
ART="${1:-artifacts/fullerene-ane-v50-stock.img}"
SER="SCV7N18927000473"
for i in $(seq 1 28800); do
    if lsusb -d 18d1:d00d 2>/dev/null | grep -q d00d; then
        prod=$(cat /sys/bus/usb/devices/1-1/product 2>/dev/null)
        ser=$(cat /sys/bus/usb/devices/1-1/serial 2>/dev/null)
        if [ "$ser" = "$SER" ] && [ "$prod" = "Fastboot2.0" ]; then
            echo "[$(date +%H:%M:%S)] loader fastboot (serial match) - flashing $ART"
            out=$(timeout 45 fastboot -s "$SER" flash kernel "$ART" 2>&1)
            echo "$out" | tail -3
            if echo "$out" | grep -q "Finished"; then
                echo "[$(date +%H:%M:%S)] FLASH OK"
                exit 0
            fi
            echo "[$(date +%H:%M:%S)] flash did not finish; keep waiting"
        fi
    fi
    sleep 1
done
echo "timeout"
exit 1
