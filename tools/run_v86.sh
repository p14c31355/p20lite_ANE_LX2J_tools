#!/bin/bash
# v86 cycle: getvar fixes + CMD25 trial (boot log) + real-client flash speed.
set -u
cd ~/dev/p20-root
bash flash_cycle.sh artifacts/fullerene-ane-v86-stock.img
sleep 150
echo "=== getvar probes ==="
timeout 60 fastboot -s SCV7N18927000473 getvar max-download-size 2>&1 | tail -2
timeout 60 fastboot -s SCV7N18927000473 getvar partition-size:kernel 2>&1 | tail -2
echo "=== real client: flash kernel (v86) ==="
timeout 480 fastboot -s SCV7N18927000473 flash kernel artifacts/fullerene-ane-v86-stock.img
echo "client rc=$?"
sleep 5
echo "=== log read ==="
timeout 400 /home/placeless/.hermes/bin/uv run --no-project --with pyusb python3 olog_main_read.py > /tmp/rd86.log 2>&1
echo "read rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v86_main.txt
grep -i "em: m_\|em: c25_\|fb: flash" /tmp/olog_main.txt | head -30
date
