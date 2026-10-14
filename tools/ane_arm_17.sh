#!/bin/bash
# Armed chain for stepmarks17: flash the kernel (report without bus reads +
# the private FTLX text block), boot it, catch the post-death fastboot window,
# then flash the v5 probe (renders the FTLX tail) and announce the photo.
set -u
cd /home/placeless/dev/p20-root
S=SCV7N18927000473
K17=artifacts/fullerene-ane-stepmarks17-stock.img
PROBE=artifacts/fullerene-ane-log-probe-stock.img
say() { echo "[$(date '+%H:%M:%S')] $*"; }
wait_fastboot() {
  for i in $(seq 1 "$1"); do
    if timeout 6 fastboot devices 2>/dev/null | grep -q "^$S"; then return 0; fi
    sleep 1
  done
  return 1
}
say "armed: waiting for fastboot to flash stepmarks17 (GICv2 IRQ ack/eoi + PPI30)"
if ! wait_fastboot 5400; then say "TIMEOUT waiting for the first fastboot"; exit 1; fi
say "FASTBOOT #1"
sleep 1
timeout 120 fastboot -s "$S" flash kernel "$K17" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | head -1
say "stepmarks17 booted - waiting for the post-death fastboot window (40 min budget)"
if ! wait_fastboot 2400; then say "NO WINDOW (eRecovery?) - combo needed for the probe"; exit 2; fi
say "FASTBOOT #2 (window)"
sleep 1
timeout 120 fastboot -s "$S" flash kernel "$PROBE" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | head -1
say "PROBE v5 BOOTED - render in ~35-45s, PHOTO NOW (full log tail + RC + ZH)"
exit 0
