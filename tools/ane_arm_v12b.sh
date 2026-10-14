#!/bin/bash
# v12b -> v7g: the EP0 responder with the setup re-arm state machine and the
# widened canvas gate (the kernel-image window is protected now). After the
# host's enumeration attempt, the v7g renders this boot's console log - the
# "ud:" markers say how far the device-side service got.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V12B=artifacts/fullerene-ane-v12b-stock.img
V7G=artifacts/fullerene-ane-log-v7g-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }
wait_fastboot(){ while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done; }

say "stage 1/2: waiting for fastboot (combo) to flash v12b"
wait_fastboot
say "FASTBOOT - flashing v12b"
timeout 180 fastboot -s "$S" flash kernel "$V12B" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V12B BOOTED - host enumeration expected within ~25 s; wait ~30 s then COMBO 2"

say "stage 2/2: waiting for fastboot to flash v7g (renders this boot's log)"
wait_fastboot
say "FASTBOOT - flashing v7g"
timeout 120 fastboot -s "$S" flash kernel "$V7G" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V7G BOOTED - render in ~30-40 s; PHOTO NOW"
say "(look for: USB: rows + ud: init/dcfg/armed/enter/enumdone/setupbcnt markers)"
