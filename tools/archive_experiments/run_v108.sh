#!/bin/bash
# v108: compact BFM scan - misc (16K), oeminfo (20K head), BFI (6K).
set -u
cd ~/dev/p20-root
SER="SCV7N18927000473"
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

bash flash_cycle.sh artifacts/fullerene-ane-v108-stock.img
sleep 100

echo "=== scans ==="
timeout 60 fastboot -s "$SER" oem scan 7C000 20 2>&1 | tail -1
sleep 1
timeout 60 fastboot -s "$SER" oem scan 8000 40 2>&1 | tail -1
sleep 1
timeout 60 fastboot -s "$SER" oem scan 1E8000 12 2>&1 | tail -1
sleep 3

echo "=== read ==="
timeout 600 $UV olog_raw_read.py > /tmp/rd108raw.log 2>&1
echo "raw rc=$?"
grep -i "nz_lba\|nz_bm\|nz_w\|scan_done\|scan_bad\|scan_req" /tmp/olog_raw.txt > logs/scan_v108.txt 2>&1
wc -l logs/scan_v108.txt
head -80 logs/scan_v108.txt
date
