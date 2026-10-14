#!/bin/bash
# v97: genome GPT scan over the eMMC BlockDevice.
set -u
cd ~/dev/p20-root
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

bash flash_cycle.sh artifacts/fullerene-ane-v97-stock.img
sleep 150

echo "=== log read ==="
timeout 300 $UV olog_main_read.py > /tmp/rd97.log 2>&1
echo "rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v97_main.txt
grep -i "em: gpt_\|em: blk_\|panic" logs/olog_v97_main.txt | head -15
date
