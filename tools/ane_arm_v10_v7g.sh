#!/bin/bash
# v10 (the known-good binary from 20:23, when the log was still landing) -> v7g.
# Purpose: separate "the code broke the log" from "the region stopped taking
# writes". No stock boot in this cycle - flash only - so the loader state stays
# as-is.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V10=artifacts/fullerene-ane-v10-stock.img
V7G=artifacts/fullerene-ane-log-v7g-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }
say "stage 1/2: waiting for fastboot (combo) to flash v10 (known-good binary)"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done
say "FASTBOOT - flashing v10"
timeout 180 fastboot -s "$S" flash kernel "$V10" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V10 BOOTED - wait ~30 s then COMBO for stage 2"
say "stage 2/2: waiting for fastboot to flash v7g"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done
say "FASTBOOT - flashing v7g"
timeout 120 fastboot -s "$S" flash kernel "$V7G" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V7G BOOTED - render in ~30-40 s; PHOTO NOW"
say "(v10 log found = the code is the suspect; absent = the region/loader is)"
