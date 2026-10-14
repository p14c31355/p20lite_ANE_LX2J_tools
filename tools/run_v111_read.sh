#!/bin/bash
# After v111 boots: read the launchd markers (the syscall pump should keep
# the USB alive past the launchd entry).
set -u
cd ~/dev/p20-root
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

sleep 45
echo "=== state ==="
lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct

echo "=== read main ==="
timeout 300 $UV olog_main_read.py > /tmp/rd111.log 2>&1
echo "rc=$?"
grep -in "launchd\|staging\|bkp\|panic\|irq id" /tmp/olog_main.txt | head -20
cp -f /tmp/olog_main.txt logs/olog_v111_main.txt

if ! grep -qi "launchd" /tmp/olog_main.txt; then
  echo "=== raw read ==="
  timeout 600 $UV olog_raw_read.py > /tmp/rd111raw.log 2>&1
  grep -in "launchd\|staging" /tmp/olog_raw.txt | head -20
  cp -f /tmp/olog_raw.txt logs/olog_v111_raw.txt
fi
echo "=== final state ==="
lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct
date
