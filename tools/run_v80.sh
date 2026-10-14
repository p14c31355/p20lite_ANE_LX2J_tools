#!/bin/bash
# v80 cycle: GPT entries dump (read-only).
set -u
cd ~/dev/p20-root
bash flash_cycle.sh artifacts/fullerene-ane-v80-stock.img
sleep 120
timeout 300 /home/placeless/.hermes/bin/uv run --no-project --with pyusb python3 olog_main_read.py > /tmp/rd80.log 2>&1
echo "read rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v80_main.txt
echo "--- v80 GPT ---"
grep -i "em: g_ent\|em: g_nent\|em: g_esize\|em: g_secs\|em: ge_" /tmp/olog_main.txt
date
