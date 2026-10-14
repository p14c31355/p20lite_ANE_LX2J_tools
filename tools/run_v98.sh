#!/bin/bash
# v98: first ext4 filesystem access (mount "system", read /build.prop).
set -u
cd ~/dev/p20-root
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

bash flash_cycle.sh artifacts/fullerene-ane-v98-stock.img
sleep 150

echo "=== log read ==="
timeout 300 $UV olog_main_read.py > /tmp/rd98.log 2>&1
echo "rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v98_main.txt
grep -i "em: ex_\|em: gpt_\|em: blk_\|panic" logs/olog_v98_main.txt | head -20
date
