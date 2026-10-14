#!/bin/bash
# v105: first launchd-featured full-bin boot on ANE (OS user-task arc).
set -u
cd ~/dev/p20-root
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

bash flash_cycle.sh artifacts/fullerene-ane-v105-launchd-stock.img
sleep 150

echo "=== log read ==="
timeout 260 $UV olog_main_read.py > /tmp/rd105.log 2>&1
echo "rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v105_main.txt
grep -i "launchd\|user\|panic\|PROBE_DONE\|mount" logs/olog_v105_main.txt | head -20
date
