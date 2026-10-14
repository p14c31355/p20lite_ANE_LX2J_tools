#!/bin/bash
# l1d3 cycle: the USB bring-up probe now feeds the SP805 from inside its hold,
# so the loader's watchdog never bites and the park (eRecovery) - whose boot
# scrubs the whole diagnostic page to 0xAA - never runs. The trace stays
# readable until a manual combo. Two combos: one to start the probe, one to
# bring up fastboot for the v8b read.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
L1D=artifacts/fullerene-ane-usb-l1d3.img
V8=artifacts/fullerene-ane-log-probe-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }

wait_fastboot(){
  while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done
}

say "armed: waiting for fastboot to flash the l1d3 USB probe (combo 1)"
wait_fastboot
say "FASTBOOT - flashing l1d3 (SP805-fed hold, trace -> mark-page mirror)"
timeout 120 fastboot -s "$S" flash kernel "$L1D" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "l1d3 running - it should hold forever now; no park expected"
say "wait ~60-90s, confirm no rescue, then COMBO 2 for the read"

say "stage 2: waiting for the next fastboot (your combo 2)"
wait_fastboot
say "FASTBOOT - flashing v8b (reads the mark-page mirror)"
timeout 120 fastboot -s "$S" flash kernel "$V8" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V8B BOOTED - render in ~35-45s, PHOTO NOW (traces 1-27 should be painted)"
