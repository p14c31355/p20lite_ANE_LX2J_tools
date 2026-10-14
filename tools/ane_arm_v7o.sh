#!/bin/bash
# v7o: the v7n reader plus a ZB row dumping the log's first bytes as raw hex
# pairs ("ZB XX XX ..."), straight from what the loader-side world sees, so
# the odd/even degradation pattern of the kernel's stores can be read exactly.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V7O=artifacts/fullerene-ane-log-v7o-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }
say "waiting for fastboot (combo) to flash v7o (ZB raw-byte dump)"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done
say "FASTBOOT - flashing v7o"
timeout 120 fastboot -s "$S" flash kernel "$V7O" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V7O BOOTED - render in ~30-40 s; PHOTO NOW"
say "(look for the ZB row at the bottom: raw hex bytes of the log start)"
