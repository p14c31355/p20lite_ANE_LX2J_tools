#!/bin/bash
# v105c: launchd-featured full bin (PIC/PIE, fresh target dir) - first ANE
# boot attempt of the OS user-task machinery.
set -u
cd ~/dev/p20-root
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

bash flash_cycle.sh artifacts/fullerene-ane-v105c-launchd-stock.img
sleep 150

echo "=== log read ==="
timeout 260 $UV olog_main_read.py > /tmp/rd105c.log 2>&1
echo "rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v105c_main.txt
grep -i "launchd\|user\|panic\|PROBE_DONE\|mount\|devices\|window" logs/olog_v105c_main.txt | head -25
date
