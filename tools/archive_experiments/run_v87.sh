#!/bin/bash
# v87: reproduce the getvar-session crash with the panic logger armed.
set -u
cd ~/dev/p20-root
bash flash_cycle.sh artifacts/fullerene-ane-v87-stock.img
sleep 150
echo "=== session 1: olog read ==="
timeout 300 /home/placeless/.hermes/bin/uv run --no-project --with pyusb python3 olog_main_read.py > /tmp/rd87a.log 2>&1
echo "rc=$?"
sleep 2
echo "=== session 2: fb_getvar (repro attempt) ==="
timeout 120 /home/placeless/.hermes/bin/uv run --no-project --with pyusb python3 fb_getvar.py "getvar:partition-size:kernel"
echo "rc=$?"
sleep 6
lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct
if lsusb -v -d 18d1:d00d 2>/dev/null | grep -q "Fastboot2.0"; then
  echo "=== LK up after crash: reboot to kernel ==="
  timeout 60 fastboot -s SCV7N18927000473 reboot
  sleep 25
fi
echo "=== post log read ==="
timeout 300 /home/placeless/.hermes/bin/uv run --no-project --with pyusb python3 olog_main_read.py > /tmp/rd87b.log 2>&1
echo "rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v87_main.txt
echo "=== panic lines ==="
grep -i "panic" logs/olog_v87_main.txt | head -5
date
