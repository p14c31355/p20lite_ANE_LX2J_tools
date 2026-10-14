#!/bin/bash
# stock -> v16 -> v7g.
# v16 = v15 + the vendor's exact status-OUT arm (xfersize=64/pktcnt=1/supcnt=3,
# cil.c dwc_otg_ep0_start_transfer) + an snpsid log line. The v15 boot stalled
# the device descriptor (-71), so this is the direct fix attempt; the v7g read
# doubles as another log-liveness test.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
STOCK=firmware/kernel_stock.bin
V16=artifacts/fullerene-ane-v16-stock.img
V7G=artifacts/fullerene-ane-log-v7g-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }
wait_fastboot(){ while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done; }

say "stage 1/3: waiting for fastboot (combo) to restore the STOCK kernel"
wait_fastboot
say "FASTBOOT - flashing stock (counter reset)"
timeout 300 fastboot -s "$S" flash kernel "$STOCK" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "STOCK BOOTED - waiting up to 120 s for adb -> reboot bootloader"
switched=0
for i in $(seq 1 24); do
  if timeout 5 adb -s "$S" devices 2>/dev/null | grep -q "$S"; then
    timeout 10 adb -s "$S" reboot bootloader >/dev/null 2>&1 && switched=1 && break
  fi
  sleep 5
done
[ "$switched" = 1 ] && say "adb switched to fastboot" || say "no adb - use the combo for stage 2"

say "stage 2/3: waiting for fastboot to flash v16"
wait_fastboot
say "FASTBOOT - flashing v16"
timeout 180 fastboot -s "$S" flash kernel "$V16" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V16 BOOTED - host enumeration expected within ~25 s; wait ~30 s then COMBO for stage 3"

say "stage 3/3: waiting for fastboot to flash v7g"
wait_fastboot
say "FASTBOOT - flashing v7g"
timeout 120 fastboot -s "$S" flash kernel "$V7G" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V7G BOOTED - render in ~30-40 s; PHOTO NOW"
