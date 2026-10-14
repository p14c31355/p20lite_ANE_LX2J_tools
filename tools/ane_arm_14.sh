#!/bin/bash
# Armed chain: flash stepmarks14 (the C=0 determinism experiment), let it boot,
# then catch the post-death fastboot window and flash the v4 probe so the new
# record can be photographed.
set -u
cd /home/placeless/dev/p20-root
S=SCV7N18927000473
K14=artifacts/fullerene-ane-stepmarks14-stock.img
PROBE=artifacts/fullerene-ane-log-probe-stock.img
say() { echo "[$(date '+%H:%M:%S')] $*"; }
wait_fastboot() {
  for i in $(seq 1 "$1"); do
    if timeout 6 fastboot devices 2>/dev/null | grep -q "^$S"; then return 0; fi
    sleep 1
  done
  return 1
}
say "armed: waiting for fastboot to flash stepmarks14 (C=0 experiment)"
if ! wait_fastboot 5400; then say "TIMEOUT waiting for the first fastboot"; exit 1; fi
say "FASTBOOT #1"
sleep 1
timeout 120 fastboot -s "$S" flash kernel "$K14" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | head -1
say "stepmarks14 booted - waiting for the post-death fastboot window (40 min budget)"
if ! wait_fastboot 2400; then say "NO WINDOW (eRecovery?) - combo needed for the probe"; exit 2; fi
say "FASTBOOT #2 (window)"
sleep 1
timeout 120 fastboot -s "$S" flash kernel "$PROBE" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | head -1
say "PROBE BOOTED - render in ~35-45s, PHOTO NOW (RC + ZH rows)"
exit 0
