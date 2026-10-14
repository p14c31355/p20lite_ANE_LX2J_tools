#!/bin/bash
# v9 -> v7: the .rs boot (Fullerene) does the whole USB bring-up with the abb
# (proven attach); its uart output tees into the FTLX. The NEXT boot renders
# the FTLX log tail with the inverse-scan probe (v7) - so the USB report
# becomes visible on screen without any .S-side USB code.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V9=artifacts/fullerene-ane-v9-stock.img
V7=artifacts/fullerene-ane-log-v7d-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }
wait_fastboot(){ while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done; }

say "armed: waiting for fastboot to flash v9 (combo 1)"
wait_fastboot
say "FASTBOOT - flashing v9 (abb + USB bring-up + report to FTLX)"
timeout 180 fastboot -s "$S" flash kernel "$V9" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "v9 running - it holds itself (SP805 fed); wait ~60s, then COMBO 2"

say "stage 2: waiting for the next fastboot (your combo 2)"
wait_fastboot
say "FASTBOOT - flashing v7 (renders the FTLX from +12 (the fresh log start: marks/memory/timer/usb lines))"
timeout 120 fastboot -s "$S" flash kernel "$V7" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V7 BOOTED - the FTLX log tail renders in ~30-40s; PHOTO NOW"
say "(expect the usb: abb=/ppll0=/gusbcfg=/dcfg=/dctl=/gintsts= lines)"
