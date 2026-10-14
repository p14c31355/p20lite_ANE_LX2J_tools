#!/bin/bash
# v96: eMMC genome BlockDevice probe (SEC_COUNT + trait-path MBR read).
set -u
cd ~/dev/p20-root
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

bash flash_cycle.sh artifacts/fullerene-ane-v96-stock.img
sleep 150

echo "=== log read ==="
timeout 300 $UV olog_main_read.py > /tmp/rd96.log 2>&1
echo "rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v96_main.txt
grep -i "em: blk_\|em: hs_ok\|em: r1_ok\|em: final_rd\|panic" logs/olog_v96_main.txt | head -20
date
