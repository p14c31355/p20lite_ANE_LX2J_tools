#!/bin/bash
# v91: fmt_okay_hex fix verification - partition-size reply, then the full
# real-client flash with the CMD25 write path.
set -u
cd ~/dev/p20-root
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

# the device is in the LK from the v90 ps2/ps4 crashes: boot the kernel first
if lsusb -v -d 18d1:d00d 2>/dev/null | grep -q "Fastboot2.0"; then
  timeout 60 fastboot -s SCV7N18927000473 reboot
  sleep 22
fi

bash flash_cycle.sh artifacts/fullerene-ane-v91-stock.img
sleep 150

echo "=== A: partition-size via pyusb (the crash command) ==="
timeout 120 $UV fb_getvar.py "getvar:partition-size:kernel"
echo "rc=$?"
sleep 3
lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct

echo "=== B: real client getvar checks ==="
timeout 60 fastboot -s SCV7N18927000473 getvar max-download-size 2>&1 | tail -2
timeout 60 fastboot -s SCV7N18927000473 getvar partition-size:kernel 2>&1 | tail -2

echo "=== C: real client flash kernel (v91, CMD25 path) ==="
timeout 480 fastboot -s SCV7N18927000473 flash kernel artifacts/fullerene-ane-v91-stock.img
echo "client rc=$?"
sleep 5
lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct

echo "=== log read ==="
timeout 300 $UV olog_main_read.py > /tmp/rd91.log 2>&1
echo "rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v91_main.txt
grep -i "fb: ps\|fb: flash\|em: wr_prog\|em: c25_sent\|panic" logs/olog_v91_main.txt | head -25
date
