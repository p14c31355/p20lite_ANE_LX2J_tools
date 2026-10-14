#!/bin/bash
# Catch the loader fastboot (after the user's combo) and flash v111, then reboot.
set -u
cd ~/dev/p20-root
SER="SCV7N18927000473"
for i in $(seq 1 2400); do
  P=$(lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct | head -1)
  case "$P" in
  *Fastboot2.0*)
    echo "LK WINDOW $(date +%H:%M:%S) - flashing v111"
    timeout 40 fastboot -s "$SER" flash kernel artifacts/fullerene-ane-v111-launchd-stock.img 2>&1 | tail -1
    timeout 15 fastboot -s "$SER" reboot 2>&1 | tail -1
    echo "done $(date +%H:%M:%S)"
    break
    ;;
  esac
  sleep 0.4
done
date
