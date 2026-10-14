#!/bin/bash
# stock -> v15 -> v7g.
# v15 = v13 (fb off, usb_dev on) + a header-independent log copy at FTLX+0x4000.
# If the v7g still cannot find "USB: ABB=" anywhere in the 1 MB pstore window,
# the region itself is not receiving writes and the loader is the suspect.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
STOCK=firmware/kernel_stock.bin
V15=artifacts/fullerene-ane-v15-stock.img
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

say "stage 2/3: waiting for fastboot to flash v15"
wait_fastboot
say "FASTBOOT - flashing v15"
timeout 180 fastboot -s "$S" flash kernel "$V15" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V15 BOOTED - host enumeration expected within ~25 s; wait ~30 s then COMBO for stage 3"

say "stage 3/3: waiting for fastboot to flash v7g"
wait_fastboot
say "FASTBOOT - flashing v7g"
timeout 120 fastboot -s "$S" flash kernel "$V7G" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V7G BOOTED - render in ~30-40 s; PHOTO NOW"
say "(success = USB: rows + ud: markers; ZH size should be ~1-2 KB now)"
