#!/bin/bash
# v109: bootup-keypoint fix + 5x crash-cycle escalation test.
# Each crash = panic -> PMIC reset -> loader fastboot; the loader reads the
# keypoint we stamped (250) and must NOT escalate to eRecovery.
set -u
cd ~/dev/p20-root
SER="SCV7N18927000473"
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

echo "=== v109 flash ==="
bash flash_cycle.sh artifacts/fullerene-ane-v109-stock.img
sleep 60

echo "=== bkp verify (read) ==="
timeout 240 $UV olog_main_read.py > /tmp/rd109.log 2>&1
echo "read rc=$?"
grep -i "bkp\|probe_done\|launchd" /tmp/olog_main.txt | head -6
cp -f /tmp/olog_main.txt logs/olog_v109_main.txt

echo "=== CRASH TEST: 5 cycles ==="
for i in 1 2 3 4 5; do
  echo "--- cycle $i: crash ---"
  timeout 15 fastboot -s "$SER" oem crash 2>&1 | tail -1
  sleep 20
  echo -n "cycle $i usb after crash: "; lsusb | grep -i "12d1\|18d1" | head -1
  echo "--- cycle $i: recover ---"
  bash flash_cycle.sh artifacts/fullerene-ane-v109-stock.img
  sleep 40
done

echo "=== final state ==="
lsusb | grep -i "12d1\|18d1"
timeout 10 fastboot -s "$SER" getvar serialno 2>&1 | tail -1
date
