#!/bin/bash
# Catch the LK fastboot window by iProduct string (robust to the sysfs
# path changing) and flash v92. Then wait for the kernel to come up.
set -u
cd ~/dev/p20-root
ART="artifacts/fullerene-ane-v92-stock.img"
SER="SCV7N18927000473"
for i in $(seq 1 28800); do
    if lsusb -v -d 18d1:d00d 2>/dev/null | grep -q "Fastboot2.0"; then
        echo "[$(date +%H:%M:%S)] loader fastboot found - flashing $ART"
        out=$(timeout 60 fastboot -s "$SER" flash kernel "$ART" 2>&1)
        echo "$out" | tail -3
        if echo "$out" | grep -q "Finished"; then
            echo "[$(date +%H:%M:%S)] FLASH OK"
            for j in $(seq 1 40); do
                if lsusb -v -d 18d1:d00d 2>/dev/null | grep -q "ANE fastboot"; then
                    echo "[$(date +%H:%M:%S)] kernel up (ANE fastboot)"
                    exit 0
                fi
                sleep 2
            done
            echo "kernel did not come up"
            exit 1
        fi
        echo "[$(date +%H:%M:%S)] flash did not finish; keep waiting"
    fi
    sleep 2
done
echo "timeout"
exit 1
