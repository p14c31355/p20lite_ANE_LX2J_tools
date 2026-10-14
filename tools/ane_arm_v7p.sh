#!/bin/bash
# v7p: the v7o reader with the ZB raw-byte row moved before the RC record
# rows so it lands inside the rendered 14 rows (it was the 15th and fell off).
# ZB shows FTLX+0xC.. as raw hex bytes - the exact odd/even degradation of
# the kernel's stores, decoded directly from the reader's world.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V7P=artifacts/fullerene-ane-log-v7p-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }
say "waiting for fastboot (combo) to flash v7p (ZB row inside the render)"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done
say "FASTBOOT - flashing v7p"
timeout 120 fastboot -s "$S" flash kernel "$V7P" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V7P BOOTED - render in ~30-40 s; PHOTO NOW"
say "(ZB row = raw hex bytes of the log start, right above the RC rows)"
