#!/bin/bash
# v88: step bisect - oem touch (plain CMD17 from USB ctx), then the
# partition-size repro with ps1..ps4 step logs. Panic note armed.
set -u
cd ~/dev/p20-root
bash flash_cycle.sh artifacts/fullerene-ane-v88-stock.img
sleep 150
echo "=== session 1: olog read ==="
timeout 300 /home/placeless/.hermes/bin/uv run --no-project --with pyusb python3 olog_main_read.py > /tmp/rd88a.log 2>&1
echo "rc=$?"
sleep 2
echo "=== session 2: oem touch (plain CMD17) ==="
timeout 60 /home/placeless/.hermes/bin/uv run --no-project --with pyusb python3 fb_send2.py "oem touch"
echo "rc=$?"
sleep 4
lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct
if lsusb -v -d 18d1:d00d 2>/dev/null | grep -q "Fastboot2.0"; then
  echo "=== crash after touch: reboot to kernel ==="
  timeout 60 fastboot -s SCV7N18927000473 reboot
  sleep 25
fi
echo "=== session 3: partition-size repro ==="
timeout 120 /home/placeless/.hermes/bin/uv run --no-project --with pyusb python3 fb_getvar.py "getvar:partition-size:kernel"
echo "rc=$?"
sleep 6
lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct
if lsusb -v -d 18d1:d00d 2>/dev/null | grep -q "Fastboot2.0"; then
  echo "=== crash after ps: reboot to kernel ==="
  timeout 60 fastboot -s SCV7N18927000473 reboot
  sleep 25
fi
echo "=== post log read ==="
timeout 300 /home/placeless/.hermes/bin/uv run --no-project --with pyusb python3 olog_main_read.py > /tmp/rd88b.log 2>&1
echo "rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v88_main.txt
echo "=== key lines ==="
grep -i "panic\|ps1\|ps2\|ps3\|ps4\|ot1\|ot2\|ot_ok\|ot_w0\|ot_err" logs/olog_v88_main.txt | head -25
date
