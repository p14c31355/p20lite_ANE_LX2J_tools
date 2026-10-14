#!/bin/bash
# v110: launchd instrumented (v109 keypoint fix + v106 markers).
# Read fast - the launchd-featured bin died ~2.5 min in on v105c/v106.
set -u
cd ~/dev/p20-root
SER="SCV7N18927000473"
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

echo "=== v110 flash ==="
bash flash_cycle.sh artifacts/fullerene-ane-v110-launchd-stock.img
sleep 30

echo "=== read (main) ==="
timeout 300 $UV olog_main_read.py > /tmp/rd110.log 2>&1
echo "rc=$?"
grep -i "launchd\|staging\|bkp\|panic\|probe_done" /tmp/olog_main.txt | head -12
cp -f /tmp/olog_main.txt logs/olog_v110_main.txt

if ! grep -qi "launchd" /tmp/olog_main.txt; then
  echo "=== no launchd lines in main; raw read ==="
  timeout 600 $UV olog_raw_read.py > /tmp/rd110raw.log 2>&1
  grep -i "launchd\|staging" /tmp/olog_raw.txt | head -12
  cp -f /tmp/olog_raw.txt logs/olog_v110_raw.txt
fi
echo "=== state ==="
lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct
date
