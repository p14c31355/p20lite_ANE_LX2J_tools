#!/bin/bash
# liveness cycle: flash the LIFE-marker probe. Its two stores decide whether
# the loader enters payloads built this way at all - the full bring-up probes
# left no trace across three runs, so first prove the code runs.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
LIVE=artifacts/fullerene-ane-usb-livefeed-stock.img
V8=artifacts/fullerene-ane-log-probe-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }

wait_fastboot(){
  while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done
}

say "armed: waiting for fastboot to flash the liveness probe (combo 1)"
wait_fastboot
say "FASTBOOT - flashing liveness probe (LIFE marker + counter, STOCK-SIZED + SP805-fed)"
timeout 120 fastboot -s "$S" flash kernel "$LIVE" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "liveness probe running - it writes LIFE + a climbing counter instantly"
say "wait ~60-90s (the feed holds it: NO park should come), then COMBO 2"

say "stage 2: waiting for the next fastboot (your combo 2)"
wait_fastboot
say "FASTBOOT - flashing v8b (reads the marker + counter)"
timeout 120 fastboot -s "$S" flash kernel "$V8" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V8B BOOTED - render in ~35-45s, PHOTO NOW (entry1 = LIFE, entry2 = counter)"
