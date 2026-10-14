#!/bin/bash
# v106: instrumented launchd on ANE - confirm how far launchd::run gets.
# Markers: "launchd: calling run" (main.rs) + "user-launchd: staging-length="
# (initramfs read result) + any failure line.
set -u
cd ~/dev/p20-root
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

bash flash_cycle.sh artifacts/fullerene-ane-v106-launchd-instr-stock.img
sleep 150

echo "=== log read ==="
timeout 260 $UV olog_main_read.py > /tmp/rd106.log 2>&1
echo "rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v106_main.txt
grep -i "launchd\|panic\|probe_done\|staging" logs/olog_v106_main.txt | head -20
date
