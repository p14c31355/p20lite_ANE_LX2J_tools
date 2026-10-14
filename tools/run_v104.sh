#!/bin/bash
# v104: verify `oem log raw` (whole 0xE000 ring) + hunt leftover udm evidence.
set -u
cd ~/dev/p20-root
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

bash flash_cycle.sh artifacts/fullerene-ane-v104-stock.img
sleep 150

echo "=== main read ==="
timeout 260 $UV olog_main_read.py > /tmp/rd104.log 2>&1
echo "main rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v104_main.txt
wc -l logs/olog_v104_main.txt

echo "=== raw read (whole ring) ==="
timeout 260 $UV olog_raw_read.py > /tmp/rd104raw.log 2>&1
echo "raw rc=$?"
cp -f /tmp/olog_raw.txt logs/olog_v104_raw.txt
wc -l logs/olog_v104_raw.txt
grep -i "udm\|panic" logs/olog_v104_raw.txt | head -10
date
