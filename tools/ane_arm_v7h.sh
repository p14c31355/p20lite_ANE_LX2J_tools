#!/bin/bash
# v7h: the v7g reader plus an unconditional fingerprint write (magic FTLX,
# size 0xFEED, cap 0xBEEF) into the private block header, then the ZH row
# reads it back on the same boot. FEED visible = this CPU's plain stores do
# reach 0x348D0000; FEED absent = the region is physically shielded now.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V7H=artifacts/fullerene-ane-log-v7h-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }
say "waiting for fastboot (combo) to flash v7h (fingerprint test)"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done
say "FASTBOOT - flashing v7h"
timeout 120 fastboot -s "$S" flash kernel "$V7H" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V7H BOOTED - render in ~30-40 s; PHOTO NOW"
say "(look for: ZH 46544C58 FEED0000 .. = writes land / anything else = shielded)"
