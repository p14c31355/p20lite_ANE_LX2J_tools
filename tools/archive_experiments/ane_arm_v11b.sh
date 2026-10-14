#!/bin/bash
# v11b: same as v11 (Rust FB self-report) plus sweep diagnostics - the stats
# and the candidate values render on screen, and a fixed fallback blit
# (0x31000000) guarantees visibility even when the sweep accepts nothing.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V11B=artifacts/fullerene-ane-v11b-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }

say "armed: waiting for fastboot to flash v11b (Rust FB + sweep stats)"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done

say "FASTBOOT - flashing v11b (11.4MB stock-shaped)"
timeout 180 fastboot -s "$S" flash kernel "$V11B" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V11B BOOTED - the Rust FB report + SWEEP stats render in ~30 s; PHOTO NOW"
say "(expect: USB: ABB= / DCTL= rows + SWEEP: OK=x GATED=x + C0..C2)"
