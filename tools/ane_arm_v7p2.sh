#!/bin/bash
# v7p re-fire: the v18 boot already proved the C=1 fix on the host side
# (full enumeration as Fullerene/ANE fastboot). This reads back the log the
# v18 kernel wrote and shows the ZB raw bytes - the odds verdict.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V7P=artifacts/fullerene-ane-log-v7p-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }
say "waiting for fastboot (combo) to flash v7p"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done
say "FASTBOOT - flashing v7p"
timeout 120 fastboot -s "$S" flash kernel "$V7P" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V7P BOOTED - render in ~30-40 s; PHOTO NOW"
say "(ZB = 46 55 4C 4C 45 52... = odds fixed)"
