#!/bin/bash
# Safety net for one risky cycle: catch a loader-fastboot window within a
# 15-minute span (a crash reset lands there), restore the given artifact,
# then reboot so the kernel actually boots (the loader sits in fastboot
# after a combo entry - the "kernel did not come up" trap).
set -u
cd ~/dev/p20-root
ART="${1:-artifacts/fullerene-ane-v101-stock.img}"
SER="SCV7N18927000473"
for i in $(seq 1 900); do
    if lsusb -v -d 18d1:d00d 2>/dev/null | grep -q "Fastboot2.0"; then
        echo "[$(date +%H:%M:%S)] safety: loader fastboot found - restoring $ART"
        out=$(timeout 60 fastboot -s "$SER" flash kernel "$ART" 2>&1)
        echo "$out" | tail -2
        if echo "$out" | grep -q "Finished"; then
            echo "[$(date +%H:%M:%S)] safety: FLASH OK - rebooting"
            timeout 30 fastboot -s "$SER" reboot 2>&1 | tail -1
            for j in $(seq 1 45); do
                if lsusb -v -d 18d1:d00d 2>/dev/null | grep -q "ANE fastboot"; then
                    echo "[$(date +%H:%M:%S)] safety: kernel up"
                    exit 0
                fi
                sleep 2
            done
            echo "safety: kernel did not come up"
            exit 1
        fi
        echo "safety: flash did not finish"
    fi
    sleep 1
done
echo "safety: 15 min window elapsed"
exit 2
