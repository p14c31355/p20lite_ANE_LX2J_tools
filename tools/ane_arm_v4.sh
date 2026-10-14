#!/bin/bash
# Armed probe-v4 deployment: on the next fastboot window, flash the 13-row
# log probe (450-char tail + RC two rows + ZH zone-header row), boot it, and
# mark the moment so the render can be photographed.
set -u
cd /home/placeless/dev/p20-root
S=SCV7N18927000473
PROBE=artifacts/fullerene-ane-log-probe-stock.img
say() { echo "[$(date '+%H:%M:%S')] $*"; }
say "armed: waiting for the ANE fastboot window (user combo after coffee)"
for i in $(seq 1 5400); do
  if timeout 6 fastboot devices 2>/dev/null | grep -q "^$S"; then
    say "FASTBOOT_READY (waited ${i} iterations)"
    sleep 1
    out=$(timeout 120 fastboot -s "$S" flash kernel "$PROBE" 2>&1)
    echo "$out" | tail -3
    if ! echo "$out" | grep -q "Finished"; then
      say "FLASH not confirmed - retrying once"
      sleep 3
      timeout 120 fastboot -s "$S" flash kernel "$PROBE" 2>&1 | tail -2
    fi
    timeout 60 fastboot -s "$S" reboot 2>&1 | head -1
    say "PROBE v4 BOOTED - render in ~35-45s, photo window ~2 min"
    exit 0
  fi
  sleep 1
done
say "WATCH_TIMEOUT"
exit 1
