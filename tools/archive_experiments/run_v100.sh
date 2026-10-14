#!/bin/bash
# v99: system-partition readdir + full build.prop hash.
set -u
cd ~/dev/p20-root
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

bash flash_cycle.sh artifacts/fullerene-ane-v100-stock.img
sleep 150

echo "=== log read ==="
timeout 300 $UV olog_main_read.py > /tmp/rd99.log 2>&1
echo "rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v100_main.txt
grep -i "em: ud_\|em: ex_\|panic" logs/olog_v100_main.txt | head -15
date
