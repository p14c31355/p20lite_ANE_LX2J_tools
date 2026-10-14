#!/bin/bash
# v107: BFM forensics - dump misc / oeminfo / bootfail_info via `oem dump`.
set -u
cd ~/dev/p20-root
SER="SCV7N18927000473"
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

bash flash_cycle.sh artifacts/fullerene-ane-v107-stock.img
sleep 120

echo "=== dump misc (0x7C000) ==="
timeout 30 fastboot -s "$SER" oem dump 7C000 1 2>&1 | tail -1
sleep 2
echo "=== dump oeminfo head (0x8000) ==="
timeout 30 fastboot -s "$SER" oem dump 8000 2 2>&1 | tail -1
sleep 2
echo "=== dump bootfail_info head (0x1E8000) ==="
timeout 30 fastboot -s "$SER" oem dump 1E8000 2 2>&1 | tail -1
sleep 3

echo "=== log read ==="
timeout 260 $UV olog_main_read.py > /tmp/rd107.log 2>&1
echo "rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v107_main.txt
python3 dump_decode.py logs/olog_v107_main.txt > logs/dump_v107.txt 2>&1
wc -l logs/dump_v107.txt
head -40 logs/dump_v107.txt
date
