#!/bin/bash
# v11c -> v7f: the kernel runs the Rust FB report with per-stage console
# markers (fb: enter/ok/gated/c0../canvas/paint/blits/fallback), all teed
# into the durable log. The next boot's v7f reader renders them from the
# "USB: ABB=" anchor, so the stage list is visible even without a panel render.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V11C=artifacts/fullerene-ane-v11c-stock.img
V7F=artifacts/fullerene-ane-log-v7f-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }
wait_fastboot(){ while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done; }

say "stage 1/2: waiting for fastboot (combo) to flash v11c"
wait_fastboot
say "FASTBOOT - flashing v11c (Rust FB + per-stage markers)"
timeout 180 fastboot -s "$S" flash kernel "$V11C" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V11C BOOTED - markers go to the durable log; wait ~30 s then COMBO 2"

say "stage 2/2: waiting for fastboot to flash v7f (renders the markers)"
wait_fastboot
say "FASTBOOT - flashing v7f (anchor scan)"
timeout 120 fastboot -s "$S" flash kernel "$V7F" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V7F BOOTED - render in ~30 s; PHOTO NOW"
say "(expect: USB: rows + FB: ENTER=/OK=/GATED=/C0=/CANVAS=/PAINT=/BLITS=/FALLBACK= - the LAST fb: line = the stop point)"
