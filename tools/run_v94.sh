#!/bin/bash
# v94: clock ladder verify (r1 = 25 MHz, r2 = HS 50 MHz/8-bit) + the
# real-client flash speed at whatever rung holds.
set -u
cd ~/dev/p20-root
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

bash flash_cycle.sh artifacts/fullerene-ane-v94-stock.img
sleep 150

echo "=== real client flash kernel (v94) ==="
timeout 480 fastboot -s SCV7N18927000473 flash kernel artifacts/fullerene-ane-v94-stock.img
echo "client rc=$?"
sleep 5
lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct

echo "=== log read ==="
timeout 300 $UV olog_main_read.py > /tmp/rd94.log 2>&1
echo "rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v94_main.txt
grep -i "em: r1_\|em: hs_\|em: clk_set\|em: final_rd\|fb: flash_ok\|fb: flash_bad\|panic" logs/olog_v94_main.txt | head -40
date
