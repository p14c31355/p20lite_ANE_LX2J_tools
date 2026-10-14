#!/bin/bash
# Wait for the ANE's fastboot window, then flash the v6 trace-dump probe and
# reboot into it. Single stage on purpose: the FTLX zone's content is already
# in RAM from the last kernel run (stepmarks21); the v6 probe renders that
# zone whatever its header says, so one photo shows whether the beats are
# intact inside it or the whole zone was overwritten.
set -u
S=SCV7N18927000473
PROBE=artifacts/fullerene-ane-log-probe-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }
say "armed: waiting for fastboot to flash the v6 trace-dump probe"
while true; do
  if timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; then
    say "FASTBOOT - flashing v6 probe"
    timeout 120 fastboot -s "$S" flash kernel "$PROBE" 2>&1 | tail -2
    timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
    say "PROBE v6 BOOTED - render in ~35-45s, PHOTO NOW (forced FTLX tail + RC + ZH)"
    exit 0
  fi
  sleep 3
done
