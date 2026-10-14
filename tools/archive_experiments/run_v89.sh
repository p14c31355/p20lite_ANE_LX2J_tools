#!/bin/bash
# v89 (host-side bisect on the running v88 kernel): is the crash the
# getvar:version sacrifice path or the partition-size path?
set -u
cd ~/dev/p20-root
echo "=== session A: getvar:version x2 (pure sacrifice pattern) ==="
timeout 60 /home/placeless/.hermes/bin/uv run --no-project --with pyusb python3 fb_send2.py "getvar:version"
echo "rc=$?"
sleep 4
lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct
if lsusb -v -d 18d1:d00d 2>/dev/null | grep -q "Fastboot2.0"; then
  echo "### A CRASHED (version path) - reboot to kernel"
  timeout 60 fastboot -s SCV7N18927000473 reboot
  sleep 25
  echo "=== post-A log read ==="
  timeout 300 /home/placeless/.hermes/bin/uv run --no-project --with pyusb python3 olog_main_read.py > /tmp/rd89a.log 2>&1
  cp -f /tmp/olog_main.txt logs/olog_v89_a.txt
  grep -i "panic\|ps1\|ot1\|ot_ok" logs/olog_v89_a.txt | head
  date
  exit 0
fi
echo "=== A survived; session B: partition-size repro ==="
timeout 120 /home/placeless/.hermes/bin/uv run --no-project --with pyusb python3 fb_getvar.py "getvar:partition-size:kernel"
echo "rc=$?"
sleep 6
lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct
if lsusb -v -d 18d1:d00d 2>/dev/null | grep -q "Fastboot2.0"; then
  echo "### B CRASHED (partition-size path) - reboot to kernel"
  timeout 60 fastboot -s SCV7N18927000473 reboot
  sleep 25
fi
echo "=== post-B log read ==="
timeout 300 /home/placeless/.hermes/bin/uv run --no-project --with pyusb python3 olog_main_read.py > /tmp/rd89b.log 2>&1
cp -f /tmp/olog_main.txt logs/olog_v89_b.txt
grep -i "panic\|ps1\|ps2\|ps3\|ps4" logs/olog_v89_b.txt | head
date
