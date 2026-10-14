#!/bin/bash
# v95: erase: implementation test (client erase on the 1 MB hisitest1
# scratch) + flash regression + log.
set -u
cd ~/dev/p20-root
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

bash flash_cycle.sh artifacts/fullerene-ane-v95-stock.img
sleep 150

echo "=== A: real client erase hisitest1 ==="
timeout 180 fastboot -s SCV7N18927000473 erase hisitest1
echo "erase rc=$?"
sleep 3
lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct

echo "=== B: real client flash kernel (regression) ==="
timeout 480 fastboot -s SCV7N18927000473 flash kernel artifacts/fullerene-ane-v95-stock.img
echo "flash rc=$?"
sleep 5
lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct

echo "=== log read ==="
timeout 300 $UV olog_main_read.py > /tmp/rd95.log 2>&1
echo "rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v95_main.txt
grep -i "fb: erase\|em: er35\|em: er36\|em: er38\|em: er13\|fb: flash_ok\|fb: flash_bad\|panic" logs/olog_v95_main.txt | head -30
date
