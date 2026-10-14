#!/bin/bash
# Catch the loader fastboot window (the device is cycling in eRecovery) and
# flash v99, the last known-good (the v100 userdata probe crashed the boot).
set -u
cd ~/dev/p20-root
ART="artifacts/fullerene-ane-v99-stock.img"
SER="SCV7N18927000473"
for i in $(seq 1 28800); do
    if lsusb -d 18d1:d00d 2>/dev/null | grep -q d00d; then
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
    fi
    sleep 1
done
echo "timeout"
exit 1
