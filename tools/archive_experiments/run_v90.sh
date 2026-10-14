#!/bin/bash
# v90: step-by-step bisect of the partition-size crash: oem ps1..ps4 and
# oem touch, each a separate command with a USB state check around it.
set -u
cd ~/dev/p20-root
UV="/home/placeless/.hermes/bin/uv run --no-project --with pyusb python3"

bash flash_cycle.sh artifacts/fullerene-ane-v90-stock.img
sleep 150

step () {
  echo "=== $1 ==="
  P0=$(lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct | awk '{print $2, $3}')
  echo "before: ${P0:-GONE}"
  timeout 90 $UV fb_getvar.py "$1"
  echo "rc=$?"
  sleep 3
  P1=$(lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct | awk '{print $2, $3}')
  echo "after:  ${P1:-GONE}"
  if lsusb -v -d 18d1:d00d 2>/dev/null | grep -q "Fastboot2.0"; then
    echo "### CRASH at [$1] - reboot to kernel"
    timeout 60 fastboot -s SCV7N18927000473 reboot
    sleep 25
  fi
}

step "oem ps1"
step "oem touch"
step "oem ps3"
step "oem ps4"
step "oem ps2"

echo "=== log read ==="
timeout 300 $UV olog_main_read.py > /tmp/rd90.log 2>&1
echo "rc=$?"
cp -f /tmp/olog_main.txt logs/olog_v90_main.txt
grep -i "panic\|ps1\|ps2a\|ps2b\|ps3a\|ps3b\|ps4a\|ps4b\|ot_ok" logs/olog_v90_main.txt | head -20
date
