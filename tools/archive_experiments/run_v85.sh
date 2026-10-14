#!/bin/bash
# v85 cycle: real fastboot client `flash kernel` test against the kernel's
# own responder (download 11.4 MB -> flash:kernel -> OKAY).
set -u
cd ~/dev/p20-root
bash flash_cycle.sh artifacts/fullerene-ane-v85-stock.img
sleep 150
echo "=== real client: flash kernel ==="
timeout 480 fastboot -s SCV7N18927000473 flash kernel artifacts/fullerene-ane-v85-stock.img
echo "client rc=$?"
sleep 5
echo "=== log read ==="
timeout 400 /home/placeless/.hermes/bin/uv run --no-project --with pyusb python3 olog_main_read.py > /tmp/rd85.log 2>&1
echo "read rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v85_main.txt
grep -i "fb: flash\|fb: dl_\|EM: WR_PROG" /tmp/olog_main.txt | head -30
date
