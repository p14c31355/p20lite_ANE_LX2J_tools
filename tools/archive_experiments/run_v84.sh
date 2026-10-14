#!/bin/bash
# v84 cycle: download: protocol test (host) + first eMMC write test (boot log).
set -u
cd ~/dev/p20-root
bash flash_cycle.sh artifacts/fullerene-ane-v84-stock.img
sleep 150
echo "=== download protocol test ==="
timeout 120 /home/placeless/.hermes/bin/uv run --no-project --with pyusb python3 dl_test.py
sleep 5
echo "=== log read ==="
timeout 400 /home/placeless/.hermes/bin/uv run --no-project --with pyusb python3 olog_main_read.py > /tmp/rd84.log 2>&1
echo "read rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v84_main.txt
grep -c "em: w0_\|em: w1_\|fb: dl_" /tmp/olog_main.txt
date
