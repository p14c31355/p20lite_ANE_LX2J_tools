#!/bin/bash
# v7g-only: the v11c's log is already in the ramoops window (20:45 boot);
# the v7g scans the WHOLE 1 MiB window (FTLX + pmsg + gap) for the last
# "USB: ABB=" anchor, so a log that landed outside the FTLX span still shows.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V7G=artifacts/fullerene-ane-log-v7g-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }

say "armed: ONE combo - waiting for fastboot to flash v7g (whole-window scan)"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done

say "FASTBOOT - flashing v7g (scan 0x34800000..0x348FFFF0)"
timeout 120 fastboot -s "$S" flash kernel "$V7G" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V7G BOOTED - render in ~30-40s; PHOTO NOW"
say "(expect: USB: ABB rows + FB: markers - the last FB: line = the stop point)"
