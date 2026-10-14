#!/bin/bash
# v82 cycle: ALL GPT entries (non-empty only), read-only.
set -u
cd ~/dev/p20-root
bash flash_cycle.sh artifacts/fullerene-ane-v82-stock.img
sleep 150
timeout 400 /home/placeless/.hermes/bin/uv run --no-project --with pyusb python3 olog_main_read.py > /tmp/rd82.log 2>&1
echo "read rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v82_main.txt
echo "ge lines: $(grep -ci 'em: ge_' /tmp/olog_main.txt)"
python3 gpt_decode.py logs/olog_v82_main.txt > logs/gpt_map_v82.txt 2>&1
cat logs/gpt_map_v82.txt
date
