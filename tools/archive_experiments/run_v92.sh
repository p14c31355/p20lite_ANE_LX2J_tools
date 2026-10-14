#!/bin/bash
# v92 verification (fire after the catcher's FLASH OK + kernel up):
# client-first flash with the clean getvars + the CMD25 write path.
set -u
cd ~/dev/p20-root
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

echo "=== A: real client getvar checks ==="
timeout 60 fastboot -s SCV7N18927000473 getvar max-download-size 2>&1 | tail -2
timeout 60 fastboot -s SCV7N18927000473 getvar partition-size:kernel 2>&1 | tail -2

echo "=== B: real client flash kernel (v92, CMD25 path) ==="
timeout 480 fastboot -s SCV7N18927000473 flash kernel artifacts/fullerene-ane-v92-stock.img
echo "client rc=$?"
sleep 5
lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct

echo "=== C: pyusb ps probe (post-flash) ==="
timeout 120 $UV fb_getvar.py "getvar:partition-size:kernel"
echo "rc=$?"
sleep 3
lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct

echo "=== log read ==="
timeout 300 $UV olog_main_read.py > /tmp/rd92.log 2>&1
echo "rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v92_main.txt
grep -i "fb: ps\|fb: flash\|em: wr_prog\|em: c25_sent\|fb: dl_timeout\|panic" logs/olog_v92_main.txt | head -25
date
