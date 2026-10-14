#!/bin/bash
# v18 -> v7p.
# v18: the kernel with SCTLR.C=1 (data cache ON) and the tee_flush now also
# cleaning the fixed log copy. Test of the odd-byte store loss: with C=0 the
# kernel's byte stores landed only on even addresses (ZB: 46 00 4C 44 45 00),
# while the same addresses were clean from the loader-side world.
# v7p: the reader with the ZB raw-byte row - its verdict decides.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V18=artifacts/fullerene-ane-v18-stock.img
V7P=artifacts/fullerene-ane-log-v7p-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }
wait_fastboot(){ while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done; }

say "stage 1/2: waiting for fastboot (combo) to flash v18 (C=1 test)"
wait_fastboot
say "FASTBOOT - flashing v18"
timeout 180 fastboot -s "$S" flash kernel "$V18" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V18 BOOTED - wait ~40 s then COMBO for stage 2"

say "stage 2/2: waiting for fastboot to flash v7p (ZB verdict)"
wait_fastboot
say "FASTBOOT - flashing v7p"
timeout 120 fastboot -s "$S" flash kernel "$V7P" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V7P BOOTED - render in ~30-40 s; PHOTO NOW"
say "(ZB = 46 55 4C 4C 45 52... = odds fixed / 46 00 4C 44... = still broken)"
