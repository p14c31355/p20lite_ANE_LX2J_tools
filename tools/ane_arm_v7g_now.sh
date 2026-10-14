#!/bin/bash
# v7g stage for the v15 boot that is already running (the fixed-offset log copy
# test). Flashes and reboots; the render lands ~30-40 s later.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V7G=artifacts/fullerene-ane-log-v7g-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }
say "waiting for fastboot (combo) to flash v7g"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done
say "FASTBOOT - flashing v7g"
timeout 120 fastboot -s "$S" flash kernel "$V7G" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V7G BOOTED - render in ~30-40 s; PHOTO NOW"
