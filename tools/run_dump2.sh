#!/bin/bash
# Dump round 2: misc vendor area (2K-4K = the likely Huawei BFR/rrecord spot).
set -u
cd ~/dev/p20-root
SER="SCV7N18927000473"
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

echo "=== dump misc 2K-4K (LBA 0x7C004..7) ==="
timeout 40 fastboot -s "$SER" oem dump 7C004 4 2>&1 | tail -1
sleep 2

echo "=== raw read (20 min window) ==="
timeout 1200 $UV olog_raw_read.py > /tmp/rd_misc2.log 2>&1
echo "raw rc=$?"
python3 dump_decode.py /tmp/olog_raw.txt > logs/dump_misc2.txt 2>&1
grep -n "=== sector" logs/dump_misc2.txt | head -10
sed -n "$(grep -n '0x7C004' logs/dump_misc2.txt | head -1 | cut -d: -f1),+34p" logs/dump_misc2.txt 2>/dev/null | head -40
date
