#!/bin/bash
# l1d2 cycle: the USB bring-up probe now mirrors its 24-entry trace into the
# mark page at 0x348DF100 - the one place tonight's parks, rescues and the
# Android boot never touched (the step marks at 0x348DF000 survived all of
# them). Stage 2 reads that mirror with the v8b probe.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
L1D=artifacts/fullerene-ane-usb-l1d2.img
V8=artifacts/fullerene-ane-log-probe-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }

wait_fastboot(){
  while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done
}

say "armed: waiting for fastboot to flash the l1d2 USB probe"
wait_fastboot
say "FASTBOOT - flashing l1d2 (trace -> mark page mirror)"
timeout 120 fastboot -s "$S" flash kernel "$L1D" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "l1d2 running - host USB attach window open"

say "stage 2: waiting for the next fastboot"
wait_fastboot
say "FASTBOOT - flashing v8b (reads the mark-page mirror)"
timeout 120 fastboot -s "$S" flash kernel "$V8" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V8B BOOTED - render in ~35-45s, PHOTO NOW (24 trace entries from the mirror)"
