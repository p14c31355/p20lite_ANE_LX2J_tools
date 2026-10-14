#!/bin/bash
# v20 re-fire: the running v19 kernel keeps its own USB enumerated (same
# 18d1:d00d ids), so every fastboot command must wait for the combo to take
# it down first. Combo now; ~25 s later the LK's fastboot is up; flash; boot;
# then the getvar tests run against the v20 kernel's responder.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V20=artifacts/fullerene-ane-v20-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }

say "COMBO now: wait 25 s for the combo to take v19 down, then the LK"
sleep 25
say "waiting for fastboot (LK)"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done
say "FASTBOOT - flashing v20"
timeout 180 fastboot -s "$S" flash kernel "$V20" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V20 BOOTED - waiting 45 s for the kernel's own enumeration"
sleep 45

say "TEST 1: getvar version"
timeout 20 fastboot -s "$S" getvar version 2>&1 | tail -3
say "TEST 2: getvar product"
timeout 20 fastboot -s "$S" getvar product 2>&1 | tail -3
say "DONE - expect 'version: 0.4' / 'product: ANE-LX2J' from the v20 kernel"
