#!/bin/bash
# v81 cycle: full GPT entry dump (entries 0..23, read-only).
set -u
cd ~/dev/p20-root
bash flash_cycle.sh artifacts/fullerene-ane-v81-stock.img
sleep 120
timeout 300 /home/placeless/.hermes/bin/uv run --no-project --with pyusb python3 olog_main_read.py > /tmp/rd81.log 2>&1
echo "read rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v81_main.txt
echo "--- v81 GPT full ---"
grep -i "em: g_ent\|em: g_nent\|em: g_esize\|em: g_secs" /tmp/olog_main.txt
grep -ci "em: ge_" /tmp/olog_main.txt
date
