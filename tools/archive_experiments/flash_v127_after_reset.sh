#!/bin/bash
# After a physical reset: catch the fresh boot's responder, reboot into the
# loader, flash the given image, reboot. One shot, verbose.
set -u
cd ~/dev/p20-root
IMG="${1:-artifacts/fullerene-ane-v127-launchd-stock.img}"
S=SCV7N18927000473
echo "=== waiting for kernel responder or LK (10 min) ==="
for i in $(seq 1 600); do
  P=$(lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct | head -1)
  case "$P" in
    *"ANE fastboot"*) echo "kernel up $(date +%H:%M:%S)"; break;;
    *Fastboot2.0*) echo "LK directly! $(date +%H:%M:%S)"; timeout 120 fastboot -s $S flash kernel "$IMG" 2>&1 | tail -2; timeout 15 fastboot -s $S reboot 2>&1 | tail -1; echo "=== FLASHED via LK $(date +%H:%M:%S) ==="; exit 0;;
  esac
  sleep 1
done
echo "=== kernel seen; reboot-bootloader ==="
timeout 25 fastboot -s $S reboot-bootloader 2>&1 | tail -1
for i in $(seq 1 120); do
  P=$(lsusb -v -d 18d1:d00d 2>/dev/null | grep -i iProduct | head -1)
  case "$P" in *Fastboot2.0*) echo "LK $(date +%H:%M:%S)"; break;; esac
  sleep 0.5
done
timeout 120 fastboot -s $S flash kernel "$IMG" 2>&1 | tail -2
timeout 15 fastboot -s $S reboot 2>&1 | tail -1
echo "=== FLASHED $(date +%H:%M:%S) ==="
