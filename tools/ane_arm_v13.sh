#!/bin/bash
# v13 -> v7g: the device-side USB without the fb path, so this is the first
# fair EP0 test (every earlier v11+/v12 run had the ane_fb corrupting the
# boot's own state) and the console log should come back, which the v7g
# renders (ud: markers = how far the EP0 service gets).
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V13=artifacts/fullerene-ane-v13-stock.img
V7G=artifacts/fullerene-ane-log-v7g-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }
wait_fastboot(){ while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done; }

say "stage 1/2: waiting for fastboot (combo) to flash v13 (no fb, EP0 first fair test)"
wait_fastboot
say "FASTBOOT - flashing v13"
timeout 180 fastboot -s "$S" flash kernel "$V13" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V13 BOOTED - host enumeration expected within ~25 s; wait ~30 s then COMBO 2"

say "stage 2/2: waiting for fastboot to flash v7g (renders this boot's log)"
wait_fastboot
say "FASTBOOT - flashing v7g"
timeout 120 fastboot -s "$S" flash kernel "$V7G" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V7G BOOTED - render in ~30-40 s; PHOTO NOW"
say "(expect: USB: rows + ud: markers again - and maybe no USB: rows if the log path also changes)"
