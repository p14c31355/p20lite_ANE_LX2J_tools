#!/bin/bash
# BFM escalation test: crash the kernel 6x; each panic resets into the
# loader, which reads the keypoint (250) and must stay in fastboot instead
# of escalating to eRecovery. Watch for 12d1:107e (eRecovery) - must never
# appear.
set -u
cd ~/dev/p20-root
SER="SCV7N18927000473"
for i in 1 2 3 4 5 6; do
  echo "=== cycle $i $(date +%H:%M:%S) ==="
  timeout 15 fastboot -s "$SER" oem crash 2>&1 | tail -1
  sleep 22
  echo -n "  after crash usb: "; lsusb | grep -iE "12d1|18d1" | head -1
  echo -n "  after crash prod: "; lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct | head -1
  timeout 15 fastboot -s "$SER" reboot 2>&1 | tail -1
  sleep 35
  echo -n "  kernel prod: "; lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct | head -1
done
echo "=== final state ==="
lsusb | grep -iE "12d1|18d1"
date
