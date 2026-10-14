#!/bin/bash
# v20: EP1 fastboot bulk pair + protocol responder. adb drives the flash;
# after the kernel boots (~45 s), the host fastboot tool talks to the
# RUNNING kernel's own responder - the first in-kernel fastboot exchange.
set -u
cd "$(dirname "$0")"
S=SCV7N18927000473
V20=artifacts/fullerene-ane-v20-stock.img
say(){ echo "[$(date +%H:%M:%S)] $*"; }

say "adb: rebooting to the bootloader"
timeout 20 adb -s "$S" reboot bootloader >/dev/null 2>&1 || echo "(adb reboot failed)"
say "waiting for fastboot (LK)"
while ! timeout 10 fastboot devices 2>/dev/null | grep -q "$S"; do sleep 2; done
say "FASTBOOT - flashing v20"
timeout 180 fastboot -s "$S" flash kernel "$V20" 2>&1 | tail -2
timeout 60 fastboot -s "$S" reboot 2>&1 | tail -1
say "V20 BOOTED - waiting 45 s for the kernel's own enumeration"
sleep 45

say "TEST 1: fastboot getvar version  (host <-> kernel fastboot)"
timeout 20 fastboot -s "$S" getvar version 2>&1 | tail -3
say "TEST 2: fastboot getvar product"
timeout 20 fastboot -s "$S" getvar product 2>&1 | tail -3
say "TEST 3: fastboot getvar serialno"
timeout 20 fastboot -s "$S" getvar serialno 2>&1 | tail -3
say "DONE - expect 'version: 0.4' / 'product: ANE-LX2J' from the RUNNING kernel"
