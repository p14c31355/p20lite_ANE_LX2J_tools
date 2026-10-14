#!/bin/bash
# Standing safety net (8 h): catch any loader-fastboot window (a crash
# reset lands there) and restore the stable image + reboot. Used to keep
# the ANE out of eRecovery while the user is away.
set -u
cd ~/dev/p20-root
ART="${1:-artifacts/fullerene-ane-v104-stock.img}"
SER="SCV7N18927000473"
echo "[$(date +%H:%M:%S)] standing catcher armed (8 h): $ART"
for i in $(seq 1 28800); do
    if lsusb -v -d 18d1:d00d 2>/dev/null | grep -q "Fastboot2.0"; then
        echo "[$(date +%H:%M:%S)] standing: loader fastboot found - restoring $ART"
        out=$(timeout 60 fastboot -s "$SER" flash kernel "$ART" 2>&1)
        echo "$out" | tail -2
        if echo "$out" | grep -q "Finished"; then
            echo "[$(date +%H:%M:%S)] standing: FLASH OK - rebooting"
            timeout 30 fastboot -s "$SER" reboot 2>&1 | tail -1
            for j in $(seq 1 45); do
                if lsusb -v -d 18d1:d00d 2>/dev/null | grep -q "ANE fastboot"; then
                    echo "[$(date +%H:%M:%S)] standing: kernel up (continuing vigil)"
                    break
                fi
                sleep 2
            done
        else
            echo "standing: flash did not finish"
        fi
    fi
    sleep 1
done
echo "[$(date +%H:%M:%S)] standing catcher: 8 h window elapsed"
exit 0
