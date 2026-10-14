#!/bin/bash
# Wait ONLY for the loader's fastboot (iProduct "Fastboot2.0", i.e. the user's
# vol-down+power combo), then flash the given image and reboot. Runs until the
# LK is seen (no other path). Usage: lk_flash_wait.sh [image]
set -u
cd ~/dev/p20-root
IMG="${1:-artifacts/fullerene-ane-v128-launchd-stock.img}"
S=SCV7N18927000473
echo "=== LK-only catcher armed $(date +%H:%M:%S); waiting for combo ==="
while true; do
  P=$(lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct | head -1)
  case "$P" in
    *Fastboot2.0*)
      echo "*** LK UP $(date +%H:%M:%S) ***"
      sleep 1
      timeout 120 fastboot -s $S flash kernel "$IMG" 2>&1 | tail -2
      timeout 15 fastboot -s $S reboot 2>&1 | tail -1
      echo "=== FLASHED $(date +%H:%M:%S) ==="
      exit 0
      ;;
  esac
  sleep 1
done
