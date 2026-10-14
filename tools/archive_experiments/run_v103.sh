#!/bin/bash
# v103: boot-time mount removed, oem udmount added. Verify the boot is
# healthy (the on-demand design means this boot cannot remount).
set -u
cd ~/dev/p20-root
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

bash flash_cycle.sh artifacts/fullerene-ane-v103-stock.img
sleep 150

echo "=== log read ==="
timeout 300 $UV olog_main_read.py > /tmp/rd103.log 2>&1
echo "rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v103_main.txt
grep -i "ud_\|panic\|probe_done" logs/olog_v103_main.txt | head -12
date
