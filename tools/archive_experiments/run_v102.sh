#!/bin/bash
# v102: F2FS userdata mount retry on the 8 MiB heap (the v100 crash retry).
set -u
cd ~/dev/p20-root
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

bash flash_cycle.sh artifacts/fullerene-ane-v102-stock.img
sleep 150

echo "=== log read ==="
timeout 300 $UV olog_main_read.py > /tmp/rd102.log 2>&1
echo "rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v102_main.txt
grep -i "em: ud_\|panic" logs/olog_v102_main.txt | head -15
date
