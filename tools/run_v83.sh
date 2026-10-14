#!/bin/bash
# v83 cycle: partition-head reads (kernel / bootfail_info / erecovery).
set -u
cd ~/dev/p20-root
bash flash_cycle.sh artifacts/fullerene-ane-v83-stock.img
sleep 150
timeout 400 /home/placeless/.hermes/bin/uv run --no-project --with pyusb python3 olog_main_read.py > /tmp/rd83.log 2>&1
echo "read rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v83_main.txt
echo "--- v83 partition heads ---"
grep -i "em: kp_\|em: bp_\|em: ep_" /tmp/olog_main.txt
date
