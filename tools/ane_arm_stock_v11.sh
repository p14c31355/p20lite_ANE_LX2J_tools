#!/bin/bash
# stock -> v11: the phone sits in eRecovery (the loader's failure counter),
# so the stock kernel boots once to reset it, then v11 (the Rust FB
# self-report) is flashed and paints its own report in the bringing-up boot.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
STOCK=firmware/kernel_stock.bin
V11=artifacts/fullerene-ane-v11-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }
wait_fastboot(){ while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done; }

say "stage 1/2: waiting for fastboot (combo) to restore the STOCK kernel"
wait_fastboot
say "FASTBOOT - flashing stock ($(stat -c %s "$STOCK") B) to reset the loader counter"
timeout 300 fastboot -s "$S" flash kernel "$STOCK" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "STOCK BOOTED - waiting up to 120 s for adb (then 'adb reboot bootloader', no combo needed)"
switched=0
for i in $(seq 1 24); do
  if timeout 5 adb -s "$S" devices 2>/dev/null | grep -q "$S"; then
    timeout 10 adb -s "$S" reboot bootloader >/dev/null 2>&1 && switched=1 && break
  fi
  sleep 5
done
[ "$switched" = 1 ] && say "adb switched the phone to fastboot" || say "no adb seen - use the combo for stage 2"

say "stage 2/2: waiting for fastboot to flash v11"
wait_fastboot
say "FASTBOOT - flashing v11 (Rust FB self-report, lattice font)"
timeout 180 fastboot -s "$S" flash kernel "$V11" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V11 BOOTED - the Rust FB report renders in ~30 s; PHOTO NOW"
say "(expect: ANE SELF-REPORT / USB: ABB= / DCTL= / PHY rows in the top area)"
