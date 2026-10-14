#!/bin/bash
# Two-stage cycle for the USB bring-up measurement:
#   stage 1: flash the l1d USB probe (vendor 8-step bring-up + attach attempt +
#            the 24-entry trace at 0x348C0000), let it hang with the pull-up
#            on - the host watches for OUR device on the bus.
#   stage 2: the l1d hang falls back to fastboot via the loader; flash the v8
#            trace-dump probe to read the trace it left.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
L1D=artifacts/fullerene-ane-usb-l1d.img
V8=artifacts/fullerene-ane-log-probe-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }

wait_fastboot(){
  while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 3; done
}

say "stage 1 armed: waiting for fastboot to flash the l1d USB probe"
wait_fastboot
say "FASTBOOT - flashing l1d probe; host-visible attach window opens shortly"
timeout 120 fastboot -s "$S" flash kernel "$L1D" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "l1d running now - any host USB attach in this window is OURS"

say "stage 2: waiting for the next fastboot (l1d hang -> loader fallback)"
wait_fastboot
say "FASTBOOT - flashing v8 trace dump"
timeout 120 fastboot -s "$S" flash kernel "$V8" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V8 BOOTED - render in ~35-45s, PHOTO NOW (24 trace entries)"
