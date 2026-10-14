#!/bin/bash
# v7p re-fire with the v18-alive trap handled: the running v18 kernel IS a
# fastboot device (full enumeration), so an immediate flash targets it and
# dies with a protocol error (no bulk yet - by design). The combo must come
# first, killing the v18; after ~25 s the LK's own fastboot is up and the
# flash targets the loader again.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V7P=artifacts/fullerene-ane-log-v7p-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }
say "wait 25 s for the combo to take the v18 down, then the LK fastboot"
sleep 25
say "waiting for fastboot (LK)"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done
say "FASTBOOT - flashing v7p"
timeout 120 fastboot -s "$S" flash kernel "$V7P" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V7P BOOTED - render in ~30-40 s; PHOTO NOW"
say "(ZB = 46 55 4C 4C 45 52... = odds fixed)"
