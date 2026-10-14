#!/bin/bash
# stock -> v11d -> v7g.
# stock  : reset the loader's failure counter (it sent the last boots to eRecovery).
# v11d   : the bring-up + Rust FB + per-stage markers, with the log-size clamp
#          (out-of-range size = treated as empty, so the append can never be
#          pointed outside the readable window again).
# v7g    : reader - scans the whole 1 MiB ramoops window for "USB: ABB=".
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
STOCK=firmware/kernel_stock.bin
V11D=artifacts/fullerene-ane-v11d-stock.img
V7G=artifacts/fullerene-ane-log-v7g-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }
wait_fastboot(){ while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done; }

say "stage 1/3: waiting for fastboot (combo) to restore the STOCK kernel (counter reset)"
wait_fastboot
say "FASTBOOT - flashing stock"
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

say "stage 2/3: waiting for fastboot to flash v11d (clamped log)"
wait_fastboot
say "FASTBOOT - flashing v11d"
timeout 180 fastboot -s "$S" flash kernel "$V11D" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V11D BOOTED - wait ~30 s, then COMBO for stage 3"

say "stage 3/3: waiting for fastboot to flash v7g (reader)"
wait_fastboot
say "FASTBOOT - flashing v7g"
timeout 120 fastboot -s "$S" flash kernel "$V7G" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V7G BOOTED - render in ~30-40 s; PHOTO NOW"
say "(expect: USB: rows + FB: markers; the last FB: line = the stop point)"
